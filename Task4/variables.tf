# --- Учётные данные и расположение ------------------------------------------

variable "cloud_id" {
  description = "Идентификатор облака Yandex Cloud"
  type        = string
}

variable "folder_id" {
  description = "Идентификатор каталога, в котором создаются ресурсы"
  type        = string
}

variable "service_account_key_file" {
  description = "Путь к файлу авторизованного ключа сервисного аккаунта. Пустая строка означает, что используется OAuth-токен. Файл в репозиторий не коммитится"
  type        = string
  default     = ""
}

variable "yc_token" {
  description = "OAuth-токен Yandex Cloud. Альтернатива ключу сервисного аккаунта, удобна для учебного контура. Передавать через TF_VAR_yc_token, а не через tfvars"
  type        = string
  default     = ""
  sensitive   = true
}

variable "default_zone" {
  description = "Зона доступности по умолчанию, в ней размещается бастион"
  type        = string
  default     = "ru-central1-a"

  validation {
    condition     = can(regex("^ru-central1-[abd]$", var.default_zone))
    error_message = "Зона должна быть одной из: ru-central1-a, ru-central1-b, ru-central1-d."
  }
}

variable "environment" {
  description = "Контур развёртывания: dev, stage или prod"
  type        = string
  default     = "dev"

  validation {
    condition     = contains(["dev", "stage", "prod"], var.environment)
    error_message = "Допустимые значения: dev, stage, prod."
  }
}

variable "name_prefix" {
  description = "Префикс имён ресурсов. Позволяет держать несколько контуров в одном каталоге"
  type        = string
  default     = "future20"

  validation {
    condition     = can(regex("^[a-z][a-z0-9-]{1,20}$", var.name_prefix))
    error_message = "Префикс: строчные латинские буквы, цифры и дефис, от 2 до 21 символа."
  }
}

# --- Сеть --------------------------------------------------------------------

variable "platform_subnet_cidrs" {
  description = "Подсети платформы по зонам доступности. Имеют маршрут в NAT-шлюз"
  type        = map(string)

  default = {
    "ru-central1-a" = "10.10.1.0/24"
    "ru-central1-b" = "10.10.2.0/24"
    "ru-central1-d" = "10.10.3.0/24"
  }
}

variable "phi_zone" {
  description = "Зона размещения контура медицинских данных"
  type        = string
  default     = "ru-central1-a"
}

variable "phi_subnet_cidr" {
  description = "Подсеть изолированного контура медданных. Маршрута в интернет не имеет"
  type        = string
  default     = "10.10.100.0/24"
}

variable "trusted_ssh_cidrs" {
  description = "Доверенные сети, из которых разрешён вход на бастион и к порталу"
  type        = list(string)

  validation {
    condition     = !contains(var.trusted_ssh_cidrs, "0.0.0.0/0")
    error_message = "Открывать доступ всему интернету запрещено: укажите конкретные подсети."
  }
}

# --- Виртуальные машины -------------------------------------------------------

variable "vm_image_family" {
  description = "Семейство образов для виртуальных машин"
  type        = string
  default     = "ubuntu-2204-lts"
}

variable "vm_platform_id" {
  description = "Аппаратная платформа вычислительных ресурсов"
  type        = string
  default     = "standard-v3"
}

variable "ssh_public_key" {
  description = "Открытый SSH-ключ для доступа к узлам"
  type        = string
}

variable "bastion_preemptible" {
  description = "Делать бастион прерываемой ВМ. Дешевле, простой некритичен"
  type        = bool
  default     = true
}

variable "bastion_resources" {
  description = "Ресурсы бастиона"

  type = object({
    cores         = number
    memory        = number
    core_fraction = number
    disk_size     = number
  })

  default = {
    cores         = 2
    memory        = 2
    core_fraction = 20
    disk_size     = 20
  }
}

variable "platform_nodes" {
  description = <<-EOT
    Узлы платформы данных. Ключ карты становится именем хоста.
    Добавление узла — это одна строка в terraform.tfvars, а не копирование ресурса.
  EOT

  type = map(object({
    zone           = string
    cores          = number
    memory         = number
    core_fraction  = number
    boot_disk_size = number
    data_disk_size = number
    data_disk_type = string
  }))

  validation {
    condition     = alltrue([for n in var.platform_nodes : n.memory >= 4])
    error_message = "Узлам платформы нужно не менее 4 ГБ памяти."
  }

  validation {
    condition     = alltrue([for n in var.platform_nodes : contains([5, 20, 50, 100], n.core_fraction)])
    error_message = "Гарантированная доля vCPU должна быть 5, 20, 50 или 100."
  }
}

variable "phi_node" {
  description = "Узел изолированного контура медданных"

  type = object({
    cores          = number
    memory         = number
    core_fraction  = number
    boot_disk_size = number
  })

  default = {
    cores          = 4
    memory         = 16
    core_fraction  = 100
    boot_disk_size = 100
  }
}

# --- Объектное хранилище -------------------------------------------------------

variable "lakehouse_bucket_name" {
  description = "Имя бакета Lakehouse. Должно быть уникальным глобально"
  type        = string

  validation {
    condition     = can(regex("^[a-z0-9][a-z0-9.-]{2,62}$", var.lakehouse_bucket_name))
    error_message = "Имя бакета: строчные латинские буквы, цифры, точка и дефис, от 3 до 63 символов."
  }
}

variable "lakehouse_cold_transition_days" {
  description = "Через сколько дней данные переводятся в холодный класс хранения"
  type        = number
  default     = 90

  validation {
    condition     = var.lakehouse_cold_transition_days >= 30
    error_message = "Перевод в холодное хранилище раньше 30 дней экономически не оправдан."
  }
}

variable "enable_managed_postgres" {
  description = "Разворачивать управляемый кластер PostgreSQL. Самая дорогая позиция конфигурации: для учебного прогона можно отключить"
  type        = bool
  default     = true
}

variable "postgres_version" {
  description = "Версия PostgreSQL для кластера метаданных"
  type        = string
  default     = "16"
}

variable "postgres_zones" {
  description = "Зоны размещения хостов PostgreSQL. Две и более дают отказоустойчивость"
  type        = list(string)
  default     = ["ru-central1-a", "ru-central1-b"]
}

variable "postgres_resources" {
  description = "Ресурсы кластера метаданных"

  type = object({
    preset    = string
    disk_type = string
    disk_size = number
  })

  default = {
    preset    = "s3-c2-m8"
    disk_type = "network-ssd"
    disk_size = 50
  }
}

variable "postgres_user" {
  description = "Пользователь БД метаданных"
  type        = string
  default     = "platform"
}

variable "postgres_password" {
  description = "Пароль пользователя БД метаданных. Передаётся через переменную окружения TF_VAR_postgres_password. Не нужен, если enable_managed_postgres = false"
  type        = string
  sensitive   = true
  default     = ""

  validation {
    condition     = var.postgres_password == "" || length(var.postgres_password) >= 12
    error_message = "Пароль должен быть не короче 12 символов."
  }
}
