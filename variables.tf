# General

variable "prefix" {
  description = "Prefix for all resource names in the cloud. Defaults to USER environment variable via TF_VAR_prefix."
  type        = string
  default     = ""

  validation {
    condition     = can(regex("^[a-z0-9-]*$", var.prefix))
    error_message = "Prefix must contain only lowercase letters, numbers, and hyphens."
  }
}

variable "zone" {
  description = "Availability zone for all resources"
  type        = string
  default     = "ru-central1-a"
}

variable "ssh_public_key_path" {
  description = "Path to public SSH key for hosts access (default: project .ssh/id_ed25519.pub)"
  type        = string
  default     = ".ssh/id_ed25519.pub"
}

variable "ssh_username" {
  description = "SSH username for connecting to hosts"
  type        = string
  default     = "ubuntu"
}

variable "wildcard_dns_service" {
  description = "Wildcard DNS service for public access (sslip.io or nip.io)"
  type        = string
  default     = "sslip.io"

  validation {
    condition     = contains(["sslip.io", "nip.io"], var.wildcard_dns_service)
    error_message = "Wildcard DNS service must be either 'sslip.io' or 'nip.io'."
  }
}

# Network

variable "vpc_cidr" {
  description = "CIDR block for private subnet"
  type        = string
  default     = "10.10.10.0/24"
}

# Proxy

variable "proxy_port" {
  description = "Port for Tinyproxy on bastion host"
  type        = number
  default     = 8888
}

variable "proxy_wait_timeout" {
  description = "Maximum wait time for proxy readiness in seconds"
  type        = number
  default     = 600
}

variable "proxy_wait_interval" {
  description = "Interval between proxy connection attempts in seconds"
  type        = number
  default     = 10
}

variable "no_proxy_ranges" {
  description = "List of IP ranges and domains that should not use proxy"
  type        = string
  default     = "localhost,127.0.0.1,10.0.0.0/8,172.16.0.0/12,192.168.0.0/16,.ru-central1.internal"
}

# Bastion

variable "bastion" {
  description = "Bastion host configuration"
  type = object({
    cores         = number
    memory        = number
    disk_size     = number
    core_fraction = optional(number, 20)
    preemptible   = optional(bool, true)
  })
  default = {
    cores     = 2
    memory    = 2
    disk_size = 20
  }
}

# Registry

variable "registry" {
  description = "registry host configuration"
  type = object({
    cores                = number
    memory               = number
    disk_size            = number
    data_disk_size       = optional(number, null)
    data_disk_mountpoint = optional(string, "/data")
    core_fraction        = optional(number, 20)
    preemptible          = optional(bool, true)
  })
  default = {
    cores                = 2
    memory               = 4
    disk_size            = 50
    data_disk_size       = 100
    data_disk_mountpoint = "/data"
  }
}

# Harbor

variable "harbor_version" {
  description = "Harbor version to install"
  type        = string
  default     = "2.15.0"
}

# Deckhouse

variable "deckhouse_registry_host" {
  description = "Deckhouse registry hostname (e.g., registry.deckhouse.ru, registry.deckhouse.io, registry-cse.deckhouse.ru)"
  type        = string
  default     = "registry.deckhouse.ru"
}

variable "deckhouse_repo_path" {
  description = "Deckhouse repository path in registry (e.g., deckhouse, proxy/dkp)"
  type        = string
  default     = "deckhouse"
}

variable "deckhouse_edition" {
  description = "Deckhouse edition (ce, be, se, se-plus, ee, cse)"
  type        = string
  default     = "ce"

  validation {
    condition     = contains(["ce", "be", "se", "se-plus", "ee", "cse"], var.deckhouse_edition)
    error_message = "Deckhouse edition must be one of: ce, be, se, se-plus, ee, cse"
  }
}

variable "deckhouse_release_channel" {
  description = "Deckhouse release channel (alpha, beta, early-access, stable, rock-solid, lts)"
  type        = string
  default     = "alpha"

  validation {
    condition     = contains(["alpha", "beta", "early-access", "stable", "rock-solid", "lts"], var.deckhouse_release_channel)
    error_message = "Deckhouse release channel must be one of: alpha, beta, early-access, stable, rock-solid, lts"
  }
}

variable "harbor_admin_password" {
  description = "Harbor admin password"
  type        = string
  default     = "Harbor12345"
  sensitive   = false
}

variable "deckhouse_registry_docker_cfg" {
  description = "base64-encoded dockerconfigjson for Deckhouse registry authentication"
  type        = string
  default     = ""
  sensitive   = false
}

# Master

variable "master" {
  description = "Master host configuration"
  type = object({
    cores                = number
    memory               = number
    root_disk_size       = number
    data_disk_size       = optional(number, null)
    data_disk_mountpoint = optional(string, "/var/lib/etcd")
    core_fraction        = optional(number, 100)
    preemptible          = optional(bool, true)
  })
  default = {
    cores                = 8
    memory               = 16
    root_disk_size       = 50
    data_disk_size       = 10
    data_disk_mountpoint = "/var/lib/etcd"
  }
}

# Compute defaults

variable "platform_id" {
  description = "Platform ID for compute instances"
  type        = string
  default     = "standard-v3"
}

variable "disk_type" {
  description = "Default disk type for all instances"
  type        = string
  default     = "network-ssd"
}

variable "image_id" {
  description = "OS image ID for VMs (use 'make get-image-id' to find latest)"
  type        = string
  default     = "fd80on0ma1ic60hees6n" # Ubuntu 24.04 LTS OS Login
}
