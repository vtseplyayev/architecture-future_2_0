###############################################################################
# Ключевые параметры развёрнутой инфраструктуры
###############################################################################

output "bastion_public_ip" {
  description = "Публичный адрес бастиона — единственная точка входа в инфраструктуру"
  value       = yandex_compute_instance.bastion.network_interface.0.nat_ip_address
}

output "bastion_ssh_command" {
  description = "Готовая команда подключения к бастиону"
  value       = "ssh ubuntu@${yandex_compute_instance.bastion.network_interface.0.nat_ip_address}"
}

output "platform_nodes" {
  description = "Внутренние адреса и роли узлов платформы данных"

  value = {
    for name, vm in yandex_compute_instance.platform : name => {
      internal_ip = vm.network_interface.0.ip_address
      zone        = vm.zone
      cores       = vm.resources.0.cores
      memory_gb   = vm.resources.0.memory
    }
  }
}

output "phi_node_internal_ip" {
  description = "Внутренний адрес узла контура медданных. Публичного адреса у него нет по построению"
  value       = yandex_compute_instance.phi.network_interface.0.ip_address
}

output "network_id" {
  description = "Идентификатор сети платформы"
  value       = yandex_vpc_network.main.id
}

output "nat_gateway_id" {
  description = "Идентификатор NAT-шлюза, через который выходят узлы без публичных адресов"
  value       = yandex_vpc_gateway.nat.id
}

output "platform_subnet_ids" {
  description = "Подсети платформы по зонам доступности"
  value       = { for zone, subnet in yandex_vpc_subnet.platform : zone => subnet.id }
}

output "phi_subnet_id" {
  description = "Подсеть изолированного контура. Маршрута по умолчанию не имеет"
  value       = yandex_vpc_subnet.phi.id
}

output "lakehouse_bucket" {
  description = "Имя бакета Lakehouse и его endpoint для S3-совместимых клиентов"

  value = {
    bucket   = yandex_storage_bucket.lakehouse.bucket
    endpoint = "https://storage.yandexcloud.net"
  }
}

output "lakehouse_access_key" {
  description = "Идентификатор ключа доступа к бакету. Секретная часть помечена sensitive"
  value       = yandex_iam_service_account_static_access_key.storage.access_key
}

output "lakehouse_secret_key" {
  description = "Секретный ключ доступа к бакету"
  value       = yandex_iam_service_account_static_access_key.storage.secret_key
  sensitive   = true
}

output "kms_key_id" {
  description = "Ключ шифрования данных под регулированием"
  value       = yandex_kms_symmetric_key.data.id
}

output "postgres_fqdns" {
  description = "Адреса хостов кластера метаданных. Пустой список, если кластер отключён"
  value       = var.enable_managed_postgres ? [for h in yandex_mdb_postgresql_cluster.metadata[0].host : h.fqdn] : []
}

output "postgres_connection_uri" {
  description = "Строка подключения к БД метаданных без пароля"

  value = var.enable_managed_postgres ? format(
    "postgresql://%s@%s:6432/%s",
    var.postgres_user,
    yandex_mdb_postgresql_cluster.metadata[0].host.0.fqdn,
    yandex_mdb_postgresql_database.catalog[0].name,
  ) : null
}

output "deployment_summary" {
  description = "Сводка по развёрнутой инфраструктуре"

  value = {
    environment       = var.environment
    platform_vm_count = length(yandex_compute_instance.platform)
    phi_vm_count      = 1
    bastion_count     = 1
    subnets_total     = length(yandex_vpc_subnet.platform) + 1
    data_disks        = length(yandex_compute_disk.platform_data)
  }
}
