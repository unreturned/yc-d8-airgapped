# VPC

resource "yandex_vpc_network" "vpc" {
  name = "${var.name_prefix}-isolated-vpc"
}

# Subnet

resource "yandex_vpc_subnet" "private" {
  name           = "${var.name_prefix}-private-subnet"
  zone           = var.zone
  network_id     = yandex_vpc_network.vpc.id
  v4_cidr_blocks = [var.vpc_cidr]
}

# Security groups

# Security group for bastion host
resource "yandex_vpc_security_group" "bastion" {
  name        = "${var.name_prefix}-bastion-sg"
  description = "Security group for bastion host with SSH, HTTP/HTTPS access from internet"
  network_id  = yandex_vpc_network.vpc.id

  # Incoming SSH from internet
  ingress {
    protocol       = "TCP"
    description    = "SSH from internet"
    v4_cidr_blocks = ["0.0.0.0/0"]
    port           = 22
  }

  # Incoming HTTPS from internet (Nginx reverse proxy to Deckhouse)
  ingress {
    protocol       = "TCP"
    description    = "HTTPS from internet"
    v4_cidr_blocks = ["0.0.0.0/0"]
    port           = 443
  }

  # Incoming HTTP from internet (redirect to HTTPS)
  ingress {
    protocol       = "TCP"
    description    = "HTTP from internet"
    v4_cidr_blocks = ["0.0.0.0/0"]
    port           = 80
  }

  # Incoming traffic from internal network (for proxy)
  ingress {
    protocol       = "TCP"
    description    = "Proxy from internal network"
    v4_cidr_blocks = [var.vpc_cidr]
    port           = var.proxy_port
  }

  # Incoming NTP from internal network
  ingress {
    protocol       = "UDP"
    description    = "NTP from internal network"
    v4_cidr_blocks = [var.vpc_cidr]
    port           = 123
  }

  # Outbound traffic to internet (any)
  egress {
    protocol       = "ANY"
    description    = "Allow all outbound traffic"
    v4_cidr_blocks = ["0.0.0.0/0"]
  }
}

# Security group for internal hosts (registry, master)
resource "yandex_vpc_security_group" "internal" {
  name        = "${var.name_prefix}-internal-sg"
  description = "Security group for internal hosts without direct internet access"
  network_id  = yandex_vpc_network.vpc.id

  # Incoming SSH only from internal network (from bastion)
  ingress {
    protocol       = "TCP"
    description    = "SSH from internal network"
    v4_cidr_blocks = [var.vpc_cidr]
    port           = 22
  }

  # Incoming HTTP for Harbor UI (only from internal network)
  ingress {
    protocol       = "TCP"
    description    = "HTTP from internal network"
    v4_cidr_blocks = [var.vpc_cidr]
    port           = 80
  }

  # Incoming HTTPS for Harbor (only from internal network)
  ingress {
    protocol       = "TCP"
    description    = "HTTPS from internal network"
    v4_cidr_blocks = [var.vpc_cidr]
    port           = 443
  }

  # Incoming Kubernetes API (only from internal network)
  ingress {
    protocol       = "TCP"
    description    = "Kubernetes API from internal network"
    v4_cidr_blocks = [var.vpc_cidr]
    port           = 6443
  }

  # Incoming traffic for internal communication (any TCP/UDP)
  ingress {
    protocol       = "ANY"
    description    = "Internal network communication"
    v4_cidr_blocks = [var.vpc_cidr]
  }

  # Outbound traffic to internet via proxy (any)
  egress {
    protocol       = "ANY"
    description    = "Allow all outbound traffic"
    v4_cidr_blocks = ["0.0.0.0/0"]
  }
}
