# Terraform & provider

terraform {
  required_providers {
    yandex = {
      source  = "yandex-cloud/yandex"
      version = "~> 0.127"
    }
  }
  required_version = ">= 0.13"
}

provider "yandex" {
  zone = var.zone
}

# Network

module "network" {
  source = "./modules/network"

  name_prefix = local.name_prefix
  zone        = var.zone
  vpc_cidr    = var.vpc_cidr
  proxy_port  = var.proxy_port
}

# Bastion

module "bastion" {
  source = "./modules/bastion"

  name_prefix              = local.name_prefix
  zone                     = var.zone
  platform_id              = var.platform_id
  cores                    = var.bastion.cores
  memory                   = var.bastion.memory
  core_fraction            = var.bastion.core_fraction
  preemptible              = var.bastion.preemptible
  disk_size                = var.bastion.disk_size
  disk_type                = var.disk_type
  image_id                 = var.image_id
  subnet_id                = module.network.subnet_id
  ssh_public_key           = file(var.ssh_public_key_path)
  ssh_username             = local.ssh_config.username
  proxy_port               = var.proxy_port
  vpc_cidr                 = var.vpc_cidr
  master_hostname          = "${local.name_prefix}-master.${local.region}.internal"
  registry_hostname        = "${local.name_prefix}-registry.${local.region}.internal"
  wildcard_dns_service     = var.wildcard_dns_service
  cloud_init_template_path = "${path.module}/templates/cloud-init-bastion.yaml"
  security_group_ids       = [module.network.bastion_security_group_id]
  installer_nginx_password = var.installer_nginx_password
}

# Registry host

# Create root disk for registry
resource "yandex_compute_disk" "registry_root" {
  name     = "${local.name_prefix}-registry-root"
  type     = var.disk_type
  zone     = var.zone
  size     = var.registry.disk_size
  image_id = var.image_id
}

# Additional disk for registry for NFS storage (optional)
resource "yandex_compute_disk" "registry_data" {
  count = var.registry.data_disk_size != null ? 1 : 0

  name = "${local.name_prefix}-registry-data"
  type = "network-hdd"
  zone = var.zone
  size = var.registry.data_disk_size
}

# Registry host using compute module
module "registry" {
  source = "./modules/compute"

  name          = "${local.name_prefix}-registry"
  hostname      = "${local.name_prefix}-registry"
  zone          = var.zone
  platform_id   = var.platform_id
  cores         = var.registry.cores
  memory        = var.registry.memory
  core_fraction = var.registry.core_fraction
  preemptible   = var.registry.preemptible
  disk_id       = yandex_compute_disk.registry_root.id
  disk_type     = var.disk_type
  subnet_id     = module.network.subnet_id
  nat           = false

  security_group_ids = [module.network.internal_security_group_id]

  secondary_disks = var.registry.data_disk_size != null ? [
    {
      disk_id     = yandex_compute_disk.registry_data[0].id
      device_name = "data"
    }
  ] : []

  user_data = templatefile("${path.module}/templates/cloud-init-registry.yaml", {
    username              = local.ssh_config.username
    ssh_public_key        = file(var.ssh_public_key_path)
    ssh_private_key       = file(local.ssh_config.private_key_path)
    proxy_url             = local.proxy_config.proxy_url
    no_proxy              = local.proxy_config.no_proxy
    ntp_server            = local.bastion_fqdn
    registry_fqdn         = local.registry_fqdn
    harbor_admin_password = var.harbor_admin_password
    bastion_public_ip     = module.bastion.public_ip
    nfs_subnet_cidr       = var.vpc_cidr
    has_data_disk         = var.registry.data_disk_size != null
    data_disk_mountpoint  = var.registry.data_disk_mountpoint
    wait_for_proxy_script = templatefile("${path.module}/templates/wait-for-proxy.sh", {
      proxy_host   = local.proxy_config.proxy_host
      proxy_port   = local.proxy_config.proxy_port
      max_attempts = local.proxy_config.wait_max_attempts
      interval     = local.proxy_config.wait_interval
      timeout      = local.proxy_config.wait_timeout
    })
    harbor_install_script = templatefile("${path.module}/templates/install-harbor.sh", {
      harbor_version        = var.harbor_version
      harbor_hostname       = local.registry_fqdn
      harbor_admin_password = var.harbor_admin_password
      proxy_url             = local.proxy_config.proxy_url
      no_proxy              = local.proxy_config.no_proxy
    })
    # NEW: Deckhouse configuration and installation script
    deckhouse_config = templatefile("${path.module}/templates/deckhouse-config.yaml", {
      proxy_url                     = local.proxy_config.proxy_url
      subnet_cidr                   = var.vpc_cidr
      bastion_fqdn                  = local.bastion_fqdn
      sslip_domain                  = local.sslip_domain
      master_ip                     = module.master.internal_ip
      registry_fqdn                 = local.registry_fqdn
      registry_nfs_path             = var.registry.data_disk_mountpoint
      release_channel               = local.deckhouse_release_channel_formatted
      deckhouse_images_repo         = local.deckhouse_images_repo
      deckhouse_registry_docker_cfg = local.deckhouse_registry_docker_cfg
    })
    install_deckhouse_script = templatefile("${path.module}/templates/bootstrap-deckhouse.sh", {
      ssh_key                       = "/root/.ssh/id_ed25519"
      ssh_username                  = local.ssh_config.username
      bastion_ip                    = module.bastion.public_ip
      master_ip                     = module.master.internal_ip
      registry_fqdn                 = local.registry_fqdn
      proxy_url                     = local.proxy_config.proxy_url
      no_proxy                      = local.proxy_config.no_proxy
      deckhouse_image               = "${local.deckhouse_images_repo}/install:${var.deckhouse_release_channel}"
      deckhouse_registry_host       = var.deckhouse_registry_host
      deckhouse_registry_docker_cfg = local.deckhouse_registry_docker_cfg
      nfs_path                      = var.registry.data_disk_mountpoint
      sslip_domain                  = local.sslip_domain
      harbor_password               = var.harbor_admin_password
    })
  })
}

# Master host

# Root disk for master
resource "yandex_compute_disk" "master_root" {
  name     = "${local.name_prefix}-master-root"
  type     = var.disk_type
  zone     = var.zone
  size     = var.master.root_disk_size
  image_id = var.image_id
}

# Additional disk for master for etcd data (optional)
resource "yandex_compute_disk" "master_data" {
  count = var.master.data_disk_size != null ? 1 : 0

  name = "${local.name_prefix}-master-data"
  type = "network-ssd"
  zone = var.zone
  size = var.master.data_disk_size
}

# Master host using compute module
module "master" {
  source = "./modules/compute"

  name          = "${local.name_prefix}-master"
  hostname      = "${local.name_prefix}-master"
  zone          = var.zone
  platform_id   = var.platform_id
  cores         = var.master.cores
  memory        = var.master.memory
  core_fraction = var.master.core_fraction
  preemptible   = var.master.preemptible
  disk_id       = yandex_compute_disk.master_root.id
  disk_type     = var.disk_type
  subnet_id     = module.network.subnet_id
  nat           = false

  security_group_ids = [module.network.internal_security_group_id]

  secondary_disks = var.master.data_disk_size != null ? [
    {
      disk_id     = yandex_compute_disk.master_data[0].id
      device_name = "data"
    }
  ] : []

  user_data = templatefile("${path.module}/templates/cloud-init-master.yaml", {
    username             = local.ssh_config.username
    ssh_public_key       = file(var.ssh_public_key_path)
    proxy_url            = local.proxy_config.proxy_url
    no_proxy             = local.proxy_config.no_proxy
    ntp_server           = local.bastion_fqdn
    registry_fqdn        = local.registry_fqdn
    has_data_disk        = var.master.data_disk_size != null
    data_disk_mountpoint = var.master.data_disk_mountpoint
    wait_for_proxy_script = templatefile("${path.module}/templates/wait-for-proxy.sh", {
      proxy_host   = local.proxy_config.proxy_host
      proxy_port   = local.proxy_config.proxy_port
      max_attempts = local.proxy_config.wait_max_attempts
      interval     = local.proxy_config.wait_interval
      timeout      = local.proxy_config.wait_timeout
    })
    copy_harbor_cert_script = templatefile("${path.module}/templates/copy-harbor-cert.sh", {
      registry_fqdn = local.registry_fqdn
    })
  })
}
