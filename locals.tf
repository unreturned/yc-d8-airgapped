# Locals

locals {
  # Prefix for resource names (if prefix is empty, return empty string)
  name_prefix = var.prefix

  # Extract region from zone (e.g., ru-central1-a -> ru-central1)
  region = substr(var.zone, 0, length(var.zone) - 2)

  # Bastion FQDN (internal DNS in Yandex Cloud)
  bastion_fqdn = "${local.name_prefix}-bastion.${local.region}.internal"

  # Registry FQDN (internal DNS in Yandex Cloud)
  registry_fqdn = "${local.name_prefix}-registry.${local.region}.internal"

  # Full proxy URL using FQDN
  proxy_url = "http://${local.bastion_fqdn}:${var.proxy_port}"

  # Common tags for all resources (optional, if needed)
  common_tags = {
    managed_by = "terraform"
    prefix     = var.prefix
  }

  # Proxy parameters for cloud-init templates
  proxy_config = {
    proxy_host        = local.bastion_fqdn
    proxy_port        = var.proxy_port
    proxy_url         = local.proxy_url
    no_proxy          = var.no_proxy_ranges
    wait_timeout      = var.proxy_wait_timeout
    wait_interval     = var.proxy_wait_interval
    wait_max_attempts = var.proxy_wait_timeout / var.proxy_wait_interval
  }

  # Common parameters for compute instances
  compute_defaults = {
    platform_id = var.platform_id
    zone        = var.zone
    disk_type   = var.disk_type
  }

  # SSH configuration
  ssh_config = {
    public_key_path  = var.ssh_public_key_path
    private_key_path = replace(var.ssh_public_key_path, ".pub", "")
    username         = var.ssh_username
  }

  # sslip.io domain for wildcard DNS
  sslip_domain = "${replace(module.bastion.public_ip, ".", "-")}.${var.wildcard_dns_service}"

  # Deckhouse configuration
  deckhouse_images_repo = "${var.deckhouse_registry_host}/${var.deckhouse_repo_path}/${var.deckhouse_edition}"

  # Deckhouse registry docker config (empty for CE, or provide base64 encoded dockerconfigjson for EE)
  deckhouse_registry_docker_cfg = var.deckhouse_edition == "ce" ? "eyJhdXRocyI6eyJyZWdpc3RyeS5kZWNraG91c2UucnUiOnt9fX0K" : var.deckhouse_registry_docker_cfg

  # Deckhouse release channel (convert to CamelCase for config.yml)
  deckhouse_release_channel_formatted = title(replace(var.deckhouse_release_channel, "-", ""))
}
