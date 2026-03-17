variable "name_prefix" {
  description = "Prefix for resource names"
  type        = string
}

variable "zone" {
  description = "Availability zone"
  type        = string
}

variable "platform_id" {
  description = "Platform ID"
  type        = string
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
}

variable "preemptible" {
  description = "Preemptible VM (can be stopped at any time)"
  type        = bool
  default     = false
}

variable "disk_size" {
  description = "Boot disk size in GB"
  type        = number
}

variable "disk_type" {
  description = "Disk type"
  type        = string
}

variable "image_id" {
  description = "Ubuntu image ID"
  type        = string
}

variable "subnet_id" {
  description = "Subnet ID"
  type        = string
}

variable "ssh_public_key" {
  description = "SSH public key"
  type        = string
}

variable "ssh_username" {
  description = "SSH username"
  type        = string
}

variable "proxy_port" {
  description = "Port for Tinyproxy"
  type        = number
}

variable "cloud_init_template_path" {
  description = "Path to cloud-init template"
  type        = string
}

variable "vpc_cidr" {
  description = "VPC CIDR block for NTP server configuration"
  type        = string
}

variable "security_group_ids" {
  description = "List of security group IDs for bastion host"
  type        = list(string)
  default     = []
}

variable "master_hostname" {
  description = "Master node hostname for nginx reverse proxy"
  type        = string
}

variable "registry_hostname" {
  description = "Registry (Harbor) internal hostname (FQDN)"
  type        = string
}

variable "wildcard_dns_service" {
  description = "Wildcard DNS service for public access (sslip.io or nip.io)"
  type        = string
  default     = "sslip.io"
}
