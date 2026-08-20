terraform {
  required_version = ">= 1.8"

  required_providers {
    yandex = {
      source  = "yandex-cloud/yandex"
      version = "~> 0.129"
    }
  }
}

provider "yandex" {
  cloud_id  = var.cloud_id
  folder_id = var.folder_id
  zone      = var.default_zone

  service_account_key_file = var.service_account_key_file != "" ? pathexpand(var.service_account_key_file) : null
  token                    = var.yc_token != "" ? var.yc_token : null
}

###############################################################################
# Источники данных
###############################################################################

data "yandex_compute_image" "ubuntu" {
  family = var.vm_image_family
}

###############################################################################
# Локальные значения
###############################################################################

locals {
  # Общие метки. Разделение по контуру нужно для учёта затрат и для аудита ИБ.
  common_labels = {
    project     = "future-2-0"
    environment = var.environment
    managed_by  = "terraform"
  }

  # Подсети платформы: имеют маршрут в NAT-шлюз, то есть исходящий интернет.
  platform_subnets = {
    for zone, cidr in var.platform_subnet_cidrs : zone => cidr
  }
}

###############################################################################
# IAM: сервисные аккаунты
###############################################################################

resource "yandex_iam_service_account" "platform" {
  name        = "${var.name_prefix}-platform-sa"
  description = "Сервисный аккаунт узлов платформы данных"
  folder_id   = var.folder_id
}

resource "yandex_iam_service_account" "storage" {
  name        = "${var.name_prefix}-storage-sa"
  description = "Сервисный аккаунт для доступа к бакету Lakehouse"
  folder_id   = var.folder_id
}

resource "yandex_resourcemanager_folder_iam_member" "platform_compute" {
  folder_id = var.folder_id
  role      = "compute.viewer"
  member    = "serviceAccount:${yandex_iam_service_account.platform.id}"
}

resource "yandex_resourcemanager_folder_iam_member" "storage_admin" {
  folder_id = var.folder_id
  role      = "storage.admin"
  member    = "serviceAccount:${yandex_iam_service_account.storage.id}"
}

resource "yandex_resourcemanager_folder_iam_member" "kms_encrypter" {
  folder_id = var.folder_id
  role      = "kms.keys.encrypterDecrypter"
  member    = "serviceAccount:${yandex_iam_service_account.storage.id}"
}

resource "yandex_iam_service_account_static_access_key" "storage" {
  service_account_id = yandex_iam_service_account.storage.id
  description        = "Ключ S3 API для доступа к бакету Lakehouse"
}

###############################################################################
# KMS: ключ шифрования
###############################################################################

resource "yandex_kms_symmetric_key" "data" {
  name              = "${var.name_prefix}-data-key"
  description       = "Шифрование бакета Lakehouse и дисков контура медданных"
  default_algorithm = "AES_256"
  rotation_period   = "2160h" # 90 дней
  folder_id         = var.folder_id
  labels            = local.common_labels
}

###############################################################################
# Сеть
###############################################################################

resource "yandex_vpc_network" "main" {
  name        = "${var.name_prefix}-network"
  description = "Общая сеть платформы данных"
  folder_id   = var.folder_id
  labels      = local.common_labels
}

resource "yandex_vpc_gateway" "nat" {
  name      = "${var.name_prefix}-nat-gateway"
  folder_id = var.folder_id
  labels    = local.common_labels

  shared_egress_gateway {}
}

resource "yandex_vpc_route_table" "nat" {
  name       = "${var.name_prefix}-nat-route-table"
  network_id = yandex_vpc_network.main.id
  folder_id  = var.folder_id
  labels     = local.common_labels

  static_route {
    destination_prefix = "0.0.0.0/0"
    gateway_id         = yandex_vpc_gateway.nat.id
  }
}

resource "yandex_vpc_subnet" "platform" {
  for_each = local.platform_subnets

  name           = "${var.name_prefix}-platform-${each.key}"
  zone           = each.key
  network_id     = yandex_vpc_network.main.id
  v4_cidr_blocks = [each.value]
  route_table_id = yandex_vpc_route_table.nat.id
  folder_id      = var.folder_id
  labels         = local.common_labels
}

# Подсеть контура медданных.
resource "yandex_vpc_subnet" "phi" {
  name           = "${var.name_prefix}-phi-${var.phi_zone}"
  zone           = var.phi_zone
  network_id     = yandex_vpc_network.main.id
  v4_cidr_blocks = [var.phi_subnet_cidr]
  folder_id      = var.folder_id
  labels         = merge(local.common_labels, { contour = "phi" })
}

###############################################################################
# Группы безопасности
###############################################################################

resource "yandex_vpc_security_group" "bastion" {
  name        = "${var.name_prefix}-sg-bastion"
  description = "Единственная точка входа по SSH из доверенных сетей"
  network_id  = yandex_vpc_network.main.id
  folder_id   = var.folder_id
  labels      = local.common_labels

  ingress {
    protocol       = "TCP"
    description    = "SSH из корпоративной сети"
    v4_cidr_blocks = var.trusted_ssh_cidrs
    port           = 22
  }

  egress {
    protocol       = "ANY"
    description    = "Исходящий трафик без ограничений"
    v4_cidr_blocks = ["0.0.0.0/0"]
  }
}

resource "yandex_vpc_security_group" "platform" {
  name        = "${var.name_prefix}-sg-platform"
  description = "Узлы платформы данных"
  network_id  = yandex_vpc_network.main.id
  folder_id   = var.folder_id
  labels      = local.common_labels

  ingress {
    protocol          = "TCP"
    description       = "SSH только через бастион"
    security_group_id = yandex_vpc_security_group.bastion.id
    port              = 22
  }

  ingress {
    protocol       = "ANY"
    description    = "Обмен между узлами платформы внутри сети"
    v4_cidr_blocks = values(var.platform_subnet_cidrs)
  }

  ingress {
    protocol       = "TCP"
    description    = "HTTPS к порталу самообслуживания из корпоративной сети"
    v4_cidr_blocks = var.trusted_ssh_cidrs
    port           = 443
  }

  egress {
    protocol       = "ANY"
    description    = "Исходящий трафик через NAT"
    v4_cidr_blocks = ["0.0.0.0/0"]
  }
}

# Контур медданных: входящий трафик только от платформы по прикладному порту,
resource "yandex_vpc_security_group" "phi" {
  name        = "${var.name_prefix}-sg-phi"
  description = "Изолированный контур медицинских данных"
  network_id  = yandex_vpc_network.main.id
  folder_id   = var.folder_id
  labels      = merge(local.common_labels, { contour = "phi" })

  ingress {
    protocol          = "TCP"
    description       = "SSH только через бастион"
    security_group_id = yandex_vpc_security_group.bastion.id
    port              = 22
  }

  ingress {
    protocol       = "TCP"
    description    = "Обращения ИИ-сервисов внутри контура"
    v4_cidr_blocks = [var.phi_subnet_cidr]
    port           = 8443
  }

  egress {
    protocol       = "ANY"
    description    = "Только внутри контура: выхода в интернет нет"
    v4_cidr_blocks = [var.phi_subnet_cidr]
  }
}

###############################################################################
# Бастион
###############################################################################

resource "yandex_compute_instance" "bastion" {
  name        = "${var.name_prefix}-bastion"
  hostname    = "bastion"
  zone        = var.default_zone
  folder_id   = var.folder_id
  platform_id = var.vm_platform_id
  labels      = local.common_labels

  # Прерываемая ВМ: бастион не хранит состояние, простой некритичен, цена ниже.
  scheduling_policy {
    preemptible = var.bastion_preemptible
  }

  resources {
    cores         = var.bastion_resources.cores
    memory        = var.bastion_resources.memory
    core_fraction = var.bastion_resources.core_fraction
  }

  boot_disk {
    initialize_params {
      image_id = data.yandex_compute_image.ubuntu.id
      size     = var.bastion_resources.disk_size
      type     = "network-hdd"
    }
  }

  network_interface {
    subnet_id          = yandex_vpc_subnet.platform[var.default_zone].id
    nat                = true # единственный узел с публичным адресом
    security_group_ids = [yandex_vpc_security_group.bastion.id]
  }

  metadata = {
    ssh-keys  = "ubuntu:${var.ssh_public_key}"
    user-data = file("${path.module}/cloud-init.yaml")
  }
}

###############################################################################
# Узлы платформы данных
###############################################################################

resource "yandex_compute_disk" "platform_data" {
  for_each = { for k, v in var.platform_nodes : k => v if v.data_disk_size > 0 }

  name      = "${var.name_prefix}-${each.key}-data"
  zone      = each.value.zone
  size      = each.value.data_disk_size
  type      = each.value.data_disk_type
  folder_id = var.folder_id
  labels    = merge(local.common_labels, { role = each.key })
}

resource "yandex_compute_instance" "platform" {
  for_each = var.platform_nodes

  name        = "${var.name_prefix}-${each.key}"
  hostname    = each.key
  zone        = each.value.zone
  folder_id   = var.folder_id
  platform_id = var.vm_platform_id
  labels      = merge(local.common_labels, { role = each.key })

  service_account_id = yandex_iam_service_account.platform.id

  resources {
    cores         = each.value.cores
    memory        = each.value.memory
    core_fraction = each.value.core_fraction
  }

  boot_disk {
    initialize_params {
      image_id = data.yandex_compute_image.ubuntu.id
      size     = each.value.boot_disk_size
      type     = "network-ssd"
    }
  }

  dynamic "secondary_disk" {
    for_each = each.value.data_disk_size > 0 ? [1] : []

    content {
      disk_id     = yandex_compute_disk.platform_data[each.key].id
      auto_delete = false
      device_name = "data"
    }
  }

  network_interface {
    subnet_id          = yandex_vpc_subnet.platform[each.value.zone].id
    nat                = false # выход только через NAT-шлюз
    security_group_ids = [yandex_vpc_security_group.platform.id]
  }

  metadata = {
    ssh-keys  = "ubuntu:${var.ssh_public_key}"
    user-data = file("${path.module}/cloud-init.yaml")
  }
}

###############################################################################
# Узел контура медданных
###############################################################################

resource "yandex_compute_instance" "phi" {
  name        = "${var.name_prefix}-phi-node"
  hostname    = "phi-node"
  zone        = var.phi_zone
  folder_id   = var.folder_id
  platform_id = var.vm_platform_id
  labels      = merge(local.common_labels, { contour = "phi", role = "phi-node" })

  resources {
    cores         = var.phi_node.cores
    memory        = var.phi_node.memory
    core_fraction = var.phi_node.core_fraction
  }

  boot_disk {
    initialize_params {
      image_id = data.yandex_compute_image.ubuntu.id
      size     = var.phi_node.boot_disk_size
      type     = "network-ssd"
    }
  }

  network_interface {
    subnet_id          = yandex_vpc_subnet.phi.id
    nat                = false # публичного адреса нет принципиально
    security_group_ids = [yandex_vpc_security_group.phi.id]
  }

  metadata = {
    ssh-keys = "ubuntu:${var.ssh_public_key}"
  }
}

###############################################################################
# Объектное хранилище: Lakehouse
###############################################################################

resource "yandex_storage_bucket" "lakehouse" {
  bucket     = var.lakehouse_bucket_name
  folder_id  = var.folder_id
  access_key = yandex_iam_service_account_static_access_key.storage.access_key
  secret_key = yandex_iam_service_account_static_access_key.storage.secret_key

  # Приватность обеспечивается блоком anonymous_access_flags ниже:
  # аргумент acl объявлен провайдером устаревшим.

  versioning {
    enabled = true
  }

  server_side_encryption_configuration {
    rule {
      apply_server_side_encryption_by_default {
        kms_master_key_id = yandex_kms_symmetric_key.data.id
        sse_algorithm     = "aws:kms"
      }
    }
  }

  # Управление стоимостью хранения: холодные данные уезжают в дешёвый класс,
  # незавершённые загрузки не копятся.
  lifecycle_rule {
    id      = "cold-storage-transition"
    enabled = true

    transition {
      days          = var.lakehouse_cold_transition_days
      storage_class = "COLD"
    }

    abort_incomplete_multipart_upload_days = 7
  }

  anonymous_access_flags {
    read        = false
    list        = false
    config_read = false
  }
}

###############################################################################
# Управляемая PostgreSQL: метаданные каталога и оркестратора
###############################################################################

resource "yandex_mdb_postgresql_cluster" "metadata" {
  count = var.enable_managed_postgres ? 1 : 0

  name        = "${var.name_prefix}-metadata-pg"
  environment = var.environment == "prod" ? "PRODUCTION" : "PRESTABLE"
  network_id  = yandex_vpc_network.main.id
  folder_id   = var.folder_id
  labels      = local.common_labels

  security_group_ids = [yandex_vpc_security_group.platform.id]

  config {
    version = var.postgres_version

    resources {
      resource_preset_id = var.postgres_resources.preset
      disk_type_id       = var.postgres_resources.disk_type
      disk_size          = var.postgres_resources.disk_size
    }

    backup_window_start {
      hours   = 2
      minutes = 0
    }
  }

  # Хосты в разных зонах: отказ одной зоны не выводит метаданные из строя.
  dynamic "host" {
    for_each = var.postgres_zones

    content {
      zone      = host.value
      subnet_id = yandex_vpc_subnet.platform[host.value].id
    }
  }
}

resource "yandex_mdb_postgresql_database" "catalog" {
  count = var.enable_managed_postgres ? 1 : 0

  cluster_id = yandex_mdb_postgresql_cluster.metadata[0].id
  name       = "datahub"
  owner      = yandex_mdb_postgresql_user.platform[0].name
}

resource "yandex_mdb_postgresql_user" "platform" {
  count = var.enable_managed_postgres ? 1 : 0

  cluster_id = yandex_mdb_postgresql_cluster.metadata[0].id
  name       = var.postgres_user
  password   = var.postgres_password
}
