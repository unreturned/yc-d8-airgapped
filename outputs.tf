# Outputs (user-facing)

output "ssh_connections" {
  description = "SSH: bastion (direct), master/registry (via bastion)"
  value = {
    bastion  = "ssh -i ${local.ssh_config.private_key_path} -o StrictHostKeyChecking=no -o UserKnownHostsFile=/dev/null ${local.ssh_config.username}@${module.bastion.public_ip}"
    registry = "ssh -i ${local.ssh_config.private_key_path} -o StrictHostKeyChecking=no -o UserKnownHostsFile=/dev/null -o ProxyCommand=\"ssh -i ${local.ssh_config.private_key_path} -o StrictHostKeyChecking=no -o UserKnownHostsFile=/dev/null -W %h:%p ${local.ssh_config.username}@${module.bastion.public_ip}\" ${local.ssh_config.username}@${module.registry.internal_ip}"
    master   = "ssh -i ${local.ssh_config.private_key_path} -o StrictHostKeyChecking=no -o UserKnownHostsFile=/dev/null -o ProxyCommand=\"ssh -i ${local.ssh_config.private_key_path} -o StrictHostKeyChecking=no -o UserKnownHostsFile=/dev/null -W %h:%p ${local.ssh_config.username}@${module.bastion.public_ip}\" ${local.ssh_config.username}@${module.master.internal_ip}"
  }
}

output "console" {
  description = "Deckhouse Console single entry point"
  value = {
    url  = "https://console.${replace(module.bastion.public_ip, ".", "-")}.${var.wildcard_dns_service}"
    user = "admin@deckhouse.io"
    pass = "7md03yxgzt"
  }
  sensitive = true
}

# Outputs for Makefile

output "bastion" {
  description = "Bastion (for make: ssh-bastion, serial-bastion, vm-list, resize-disk, …)"
  value = {
    id          = module.bastion.id
    name        = module.bastion.hostname
    internal_ip = module.bastion.internal_ip
    public_ip   = module.bastion.public_ip
  }
}

output "registry" {
  description = "Registry (for make: ssh-registry, tunnel-harbor, dockercfg, logs-deckhouse, …)"
  value = {
    id                    = module.registry.id
    name                  = module.registry.name
    internal_ip           = module.registry.internal_ip
    fqdn                  = module.registry.fqdn
    harbor_admin_user     = "admin"
    harbor_admin_password = var.harbor_admin_password
  }
  sensitive = false
}

output "master" {
  description = "Master (for make: ssh-master, check-deckhouse, serial-master, vm-list, …)"
  value = {
    id          = module.master.id
    name        = module.master.name
    internal_ip = module.master.internal_ip
  }
}

output "ssh_config" {
  description = "SSH (for make: ssh, ssh-bastion, tunnel-harbor, logs-deckhouse, …)"
  value = {
    username         = local.ssh_config.username
    private_key_path = local.ssh_config.private_key_path
  }
}

output "network" {
  description = "Network (for make output-network)"
  value = {
    vpc_id      = module.network.vpc_id
    vpc_name    = module.network.vpc_name
    subnet_id   = module.network.subnet_id
    subnet_name = module.network.subnet_name
    subnet_cidr = module.network.subnet_cidr
    subnet_zone = module.network.subnet_zone
  }
}
