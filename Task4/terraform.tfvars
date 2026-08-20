# Облако cloud-viktor-tseplyayev
cloud_id = "b1gga0ube5flgd8fnhja"

# Каталог внутри облака cloud-viktor-tseplyayev
folder_id = "b1gjfhtn0l2tui6nt8p0"

# --- Аутентификация -------------------------------------------------------------
#
# В ЭТОМ ФАЙЛЕ ПАРОЛИ И КЛЮЧИ НЕ ХРАНЯТСЯ: он коммитится в публичный репозиторий.
# Здесь указывается только ПУТЬ к файлу ключа, сам файл лежит вне репозитория.
#
# Секреты задаются так:
#   export TF_VAR_postgres_password='...'   пароль БД метаданных, от 12 символов
#   export TF_VAR_yc_token='...'            OAuth-токен вместо ключа сервисного аккаунта
#
# Подробнее — раздел «Где задавать пароли и секреты» в README.md.

service_account_key_file = "~/.yc/terraform-sa-key.json"

default_zone = "ru-central1-a"
environment  = "dev"
name_prefix  = "future20"

# --- Сеть ---------------------------------------------------------------------

platform_subnet_cidrs = {
  "ru-central1-a" = "10.10.1.0/24"
  "ru-central1-b" = "10.10.2.0/24"
  "ru-central1-d" = "10.10.3.0/24"
}

phi_zone        = "ru-central1-a"
phi_subnet_cidr = "10.10.100.0/24"

# Только корпоративные сети. Значение 0.0.0.0/0 отклоняется валидацией.
trusted_ssh_cidrs = [
  "203.0.113.0/24",
  "198.51.100.0/24",
]

# --- Доступ ---------------------------------------------------------------------

ssh_public_key = "ssh-ed25519 AAAAC3NzaC1lZDI1NTE5AAAAIB5YE+d3jI9NtZqPmNr/TdmWCVKnhGnQLH98EKLo5Cyz future20"

# --- Бастион ----------------------------------------------------------------------

bastion_preemptible = true

bastion_resources = {
  cores         = 2
  memory        = 2
  core_fraction = 20
  disk_size     = 20
}

# --- Узлы платформы данных ----------------------------------------------------------

platform_nodes = {
  query-engine = {
    zone           = "ru-central1-a"
    cores          = 8
    memory         = 32
    core_fraction  = 100
    boot_disk_size = 50
    data_disk_size = 200
    data_disk_type = "network-ssd"
  }

  kafka = {
    zone           = "ru-central1-b"
    cores          = 4
    memory         = 16
    core_fraction  = 100
    boot_disk_size = 50
    data_disk_size = 500
    data_disk_type = "network-ssd"
  }

  catalog = {
    zone           = "ru-central1-a"
    cores          = 2
    memory         = 8
    core_fraction  = 50
    boot_disk_size = 40
    data_disk_size = 0
    data_disk_type = "network-ssd"
  }

  orchestrator = {
    zone           = "ru-central1-d"
    cores          = 2
    memory         = 8
    core_fraction  = 50
    boot_disk_size = 40
    data_disk_size = 100
    data_disk_type = "network-hdd"
  }
}

# --- Контур медданных ----------------------------------------------------------------

phi_node = {
  cores          = 4
  memory         = 16
  core_fraction  = 100
  boot_disk_size = 100
}

# --- Объектное хранилище ---------------------------------------------------------------

lakehouse_bucket_name          = "future20-lakehouse-vtseplyayev"
lakehouse_cold_transition_days = 90

# --- Метаданные ---------------------------------------------------------------------

postgres_version = "16"
postgres_zones   = ["ru-central1-a", "ru-central1-b"]

postgres_resources = {
  preset    = "s3-c2-m8"
  disk_type = "network-ssd"
  disk_size = 50
}

postgres_user = "platform"
