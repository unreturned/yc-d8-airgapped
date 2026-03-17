output "vpc_id" {
  description = "ID of created VPC"
  value       = yandex_vpc_network.vpc.id
}

output "subnet_id" {
  description = "ID of private subnet"
  value       = yandex_vpc_subnet.private.id
}

output "vpc_name" {
  description = "VPC name"
  value       = yandex_vpc_network.vpc.name
}

output "subnet_name" {
  description = "Subnet name"
  value       = yandex_vpc_subnet.private.name
}

output "subnet_cidr" {
  description = "Subnet CIDR block"
  value       = yandex_vpc_subnet.private.v4_cidr_blocks[0]
}

output "subnet_zone" {
  description = "Subnet availability zone"
  value       = yandex_vpc_subnet.private.zone
}

output "bastion_security_group_id" {
  description = "Security group ID for bastion host"
  value       = yandex_vpc_security_group.bastion.id
}

output "internal_security_group_id" {
  description = "Security group ID for internal hosts"
  value       = yandex_vpc_security_group.internal.id
}
