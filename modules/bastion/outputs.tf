output "id" {
  description = "Bastion instance ID"
  value       = yandex_compute_instance.bastion.id
}

output "public_ip" {
  description = "Bastion host public IP address"
  value       = yandex_vpc_address.bastion_ip.external_ipv4_address[0].address
}

output "internal_ip" {
  description = "Bastion host internal IP address"
  value       = yandex_compute_instance.bastion.network_interface[0].ip_address
}

output "instance_name" {
  description = "Bastion instance name"
  value       = yandex_compute_instance.bastion.name
}

output "hostname" {
  description = "Bastion host hostname"
  value       = yandex_compute_instance.bastion.hostname
}

output "fqdn" {
  description = "Bastion host FQDN"
  value       = yandex_compute_instance.bastion.fqdn
}
