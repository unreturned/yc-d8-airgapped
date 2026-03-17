output "id" {
  description = "Compute instance ID"
  value       = yandex_compute_instance.instance.id
}

output "name" {
  description = "Instance name"
  value       = yandex_compute_instance.instance.name
}

output "fqdn" {
  description = "Instance FQDN"
  value       = yandex_compute_instance.instance.fqdn
}

output "internal_ip" {
  description = "Internal IP address"
  value       = yandex_compute_instance.instance.network_interface[0].ip_address
}

output "external_ip" {
  description = "External IP address (if NAT is enabled)"
  value       = var.nat ? yandex_compute_instance.instance.network_interface[0].nat_ip_address : null
}
