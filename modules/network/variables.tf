variable "name_prefix" {
  description = "Prefix for network resource names"
  type        = string
}

variable "zone" {
  description = "Availability zone"
  type        = string
}

variable "vpc_cidr" {
  description = "CIDR block for subnet"
  type        = string
}

variable "proxy_port" {
  description = "Proxy port for security group rules"
  type        = number
  default     = 8888
}
