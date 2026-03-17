variable "name" {
  description = "Compute instance name"
  type        = string
}

variable "hostname" {
  description = "Hostname for instance"
  type        = string
}

variable "zone" {
  description = "Availability zone"
  type        = string
}

variable "platform_id" {
  description = "Platform ID"
  type        = string
  default     = "standard-v3"
}

variable "cores" {
  description = "Number of CPU cores"
  type        = number
}

variable "memory" {
  description = "Memory size in GB"
  type        = number
}

variable "core_fraction" {
  description = "Guaranteed vCPU fraction"
  type        = number
  default     = 100
}

variable "preemptible" {
  description = "Preemptible VM (can be stopped at any time)"
  type        = bool
  default     = false
}

variable "disk_id" {
  description = "Existing disk ID for boot_disk (optional, if not using image_id)"
  type        = string
  default     = null
}

variable "image_id" {
  description = "Image ID for boot_disk (optional, if not using disk_id)"
  type        = string
  default     = null
}

variable "boot_disk_size" {
  description = "Boot disk size in GB (used only if image_id is specified)"
  type        = number
  default     = 20
}

variable "disk_type" {
  description = "Disk type"
  type        = string
  default     = "network-ssd"
}

variable "subnet_id" {
  description = "Subnet ID for network interface"
  type        = string
}

variable "nat" {
  description = "Enable NAT for public IP"
  type        = bool
  default     = false
}

variable "nat_ip_address" {
  description = "Reserved public IP address for NAT (optional)"
  type        = string
  default     = null
}

variable "user_data" {
  description = "Cloud-init user data for metadata"
  type        = string
}

variable "secondary_disks" {
  description = "List of additional disks to attach"
  type = list(object({
    disk_id     = string
    device_name = string
  }))
  default = []
}

variable "security_group_ids" {
  description = "List of security group IDs for compute instance"
  type        = list(string)
  default     = []
}
