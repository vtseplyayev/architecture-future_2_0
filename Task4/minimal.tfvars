# Управляемый кластер PostgreSQL
enable_managed_postgres = false

# Два узла вместо четырёх: движок запросов и брокер.
platform_nodes = {
  query-engine = {
    zone           = "ru-central1-a"
    cores          = 2
    memory         = 8
    core_fraction  = 20
    boot_disk_size = 30
    data_disk_size = 20
    data_disk_type = "network-hdd"
  }

  kafka = {
    zone           = "ru-central1-b"
    cores          = 2
    memory         = 4
    core_fraction  = 20
    boot_disk_size = 30
    data_disk_size = 20
    data_disk_type = "network-hdd"
  }
}

# Узел контура медданных: изоляцию демонстрируем, но на минимальных ресурсах.
phi_node = {
  cores          = 2
  memory         = 4
  core_fraction  = 20
  boot_disk_size = 30
}

# Хранение остаётся, оно почти ничего не стоит на пустом бакете.
lakehouse_cold_transition_days = 30
