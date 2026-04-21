# Bastion public IP

resource "yandex_vpc_address" "bastion_ip" {
  name = "${var.name_prefix}-bastion-public-ip"
  external_ipv4_address {
    zone_id = var.zone
  }
}

# Bastion host

resource "yandex_compute_instance" "bastion" {
  name        = "${var.name_prefix}-bastion"
  hostname    = "${var.name_prefix}-bastion"
  platform_id = var.platform_id
  zone        = var.zone

  resources {
    cores         = var.cores
    memory        = var.memory
    core_fraction = var.core_fraction
  }

  scheduling_policy {
    preemptible = var.preemptible
  }

  boot_disk {
    initialize_params {
      image_id = var.image_id
      size     = var.disk_size
      type     = var.disk_type
    }
  }

  network_interface {
    subnet_id          = var.subnet_id
    nat                = true
    ipv4               = true
    nat_ip_address     = yandex_vpc_address.bastion_ip.external_ipv4_address[0].address
    security_group_ids = var.security_group_ids
  }

  metadata = {
    user-data = templatefile(var.cloud_init_template_path, {
      username                 = var.ssh_username
      ssh_public_key           = var.ssh_public_key
      proxy_port               = var.proxy_port
      vpc_cidr                 = var.vpc_cidr
      master_hostname          = var.master_hostname
      registry_hostname        = var.registry_hostname
      wildcard_dns_service     = var.wildcard_dns_service
      installer_nginx_password = var.installer_nginx_password
    })
  }
}
