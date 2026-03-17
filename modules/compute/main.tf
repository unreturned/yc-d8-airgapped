# Compute instance

resource "yandex_compute_instance" "instance" {
  name        = var.name
  hostname    = var.hostname
  platform_id = var.platform_id
  zone        = var.zone

  allow_stopping_for_update = true

  resources {
    cores         = var.cores
    memory        = var.memory
    core_fraction = var.core_fraction
  }

  scheduling_policy {
    preemptible = var.preemptible
  }

  boot_disk {
    # If disk_id is provided, use existing disk
    dynamic "initialize_params" {
      for_each = var.disk_id == null ? [1] : []
      content {
        image_id = var.image_id
        size     = var.boot_disk_size
        type     = var.disk_type
      }
    }

    # If disk_id is provided, mount it
    disk_id = var.disk_id
  }

  # Additional disks (optional)
  dynamic "secondary_disk" {
    for_each = var.secondary_disks
    content {
      disk_id     = secondary_disk.value.disk_id
      device_name = secondary_disk.value.device_name
    }
  }

  network_interface {
    subnet_id          = var.subnet_id
    nat                = var.nat
    ipv4               = true
    nat_ip_address     = var.nat_ip_address
    security_group_ids = var.security_group_ids
  }

  metadata = {
    user-data = var.user_data
  }
}
