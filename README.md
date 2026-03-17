# Yandex Cloud Isolated Environment with Deckhouse Kubernetes

> Terraform/OpenTofu configuration for deploying isolated infrastructure in Yandex Cloud with HTTP proxy for Kubernetes.

[![License: MIT](https://img.shields.io/badge/License-MIT-blue.svg)](LICENSE)

## What is this?

This project provisions a ready-to-use infrastructure for **single-node Deckhouse Kubernetes Platform** in an isolated Yandex Cloud environment with **automatic Deckhouse installation**:

- **Bastion** — public host with HTTP proxy (Tinyproxy), Nginx reverse proxy with Let's Encrypt, and NTP server
- **Registry** — private host with Harbor Container Registry, NFS server, and **Deckhouse installer**
- **Master** — Kubernetes master node with a separate disk for etcd

> **Key feature:** Deckhouse is installed **automatically** during `terraform apply` via cloud-init on the registry host.

## Architecture

```
Internet
   │
   └─► Bastion (Public IP, Proxy, Nginx+Let's Encrypt, Jump)
           │          ▲
           │          │ *.IP.sslip.io
           │          │
           └─► Private Subnet
                   ├─► Installer + Harbor
                   └─► DKP AIO
```

Preemptible VMs by default for cost savings.

## Quick start

### 1. Preparation

```bash
# Configure Yandex Cloud CLI (if not already)
yc init

# Set environment variables
eval $(make export)
```

**Note:** `YC_TOKEN` is valid for 12 hours only. Re-run `eval $(make export)` when it expires.

**Requirements:** Terraform/OpenTofu >= 1.0, Yandex Cloud CLI, jq, ssh-keygen (for SSH key generation)

### 2. Full automated deployment

```bash
# Initialize (first time)
# Automatically generates SSH key in .ssh/ if missing
make init

# Full deployment: infrastructure + automatic Deckhouse installation
make apply
```

**Duration:** ~30–40 min (infrastructure 5 min + cloud-init 5–10 min + Deckhouse 15–25 min).

**What happens:** SSH key generation (if missing) → VMs and network creation → cloud-init (proxy, Harbor, NFS) → Deckhouse installation on master from registry (Docker + dhctl). SSH key from `.ssh/` is passed to the registry and is not committed to git.

> **VPN note:** `make init` downloads OpenTofu providers from registry.opentofu.org. In some regions (e.g. Russia) **VPN may be required for `make init`** to succeed. After initialization you can disconnect VPN — subsequent commands work without it.
> https://github.com/opentofu/registry/pull/824

### 3. Monitoring Deckhouse installation

While installation runs, you can follow progress:

```bash
# Stream installation logs
make logs-deckhouse

# Check installation status
make check-deckhouse
```

Logs are also available on the registry host: `/var/log/deckhouse-bootstrap.log`

### 4. Accessing services

After installation completes (reported by `make check-deckhouse`):

```bash
# Get all access URLs
make urls
```

**Deckhouse Console:**
- URL: `https://console.<bastion-ip>.sslip.io`
- Email: `admin@deckhouse.io`
- Password: `7md03yxgzt`

**Harbor Registry:**
- URL: `https://harbor.<bastion-ip>.sslip.io`
- Login: `admin`
- Password: `Harbor12345`

## Main commands

```bash
make help  # List all available commands
```

**Infrastructure:**
- `make init` — Initialize Terraform (generates SSH key if needed)
- `make apply` — Create infrastructure + automatic Deckhouse installation
- `make destroy` — Destroy infrastructure
- `make generate-ssh-key` — Manually generate SSH key in `.ssh/`

**Deckhouse (automatic installation):**
- `make logs-deckhouse` — Stream installation logs
- `make check-deckhouse` — Check installation status

**SSH and access:**
- `make ssh` — Show SSH connection commands
- `make ssh-bastion` — SSH to bastion
- `make ssh-registry` — SSH to registry (via bastion)
- `make ssh-master` — SSH to master (via bastion)
- `make urls` — Show URLs for all services

**Monitoring:**
- `make vm-list` — List VMs
- `make serial-bastion` / `serial-registry` / `serial-master` — Serial console output

**Utilities:**
- `make tunnel-harbor` — SSH tunnel to Harbor (https://localhost:8443)

## Customization

Create `terraform.tfvars` to override defaults:

```bash
# General
prefix = "myproject"              # Resource prefix
zone = "ru-central1-a"            # Availability zone
wildcard_dns_service = "sslip.io" # Wildcard DNS: "sslip.io" (default) or "nip.io"

# VM sizes
bastion = {
  cores         = 2
  memory        = 2
  disk_size     = 20
  core_fraction = 20
  preemptible   = true
}

# Deckhouse
deckhouse_registry_host = "registry.deckhouse.ru"  # Registry host (for CSE: registry-cse.deckhouse.ru)
deckhouse_repo_path = "deckhouse"                  # Repo path
deckhouse_edition = "ce"                           # ce, be, se, se-plus, ee, cse
deckhouse_release_channel = "alpha"                # alpha, beta, early-access, stable, rock-solid, lts
```

**Full example:** see `terraform.tfvars.example`

## Cost

Default configuration uses **preemptible VMs** and reduced guaranteed vCPU share.

| Component | Spec | core_fraction | preemptible |
|-----------|------|---------------|-------------|
| **Bastion** | 2c, 2GB, 20GB SSD + Public IP | 20% | yes |
| **Registry** | 2c, 4GB, 100GB SSD | 20% | yes |
| **Master** | 8c, 16GB, 60GB SSD + 100GB HDD | 100% | yes |

**Approximate cost:** ~₽8.60/hr | ~₽6,250/mo | ~₽75,000/yr

**Pricing:** https://yandex.cloud/en/prices

**Saving:** Stopped VMs (`make vm-stop`) save on CPU and RAM; disks and IP are always billed.

## Troubleshooting

### Deckhouse does not install automatically

**Problem:** After `make apply`, Deckhouse does not start installing.

**Checks:**
```bash
# 1. Check status
make check-deckhouse

# 2. View logs
make logs-deckhouse

# 3. Check cloud-init on registry
make ssh-registry
tail -f /var/log/cloud-init-output.log
tail -f /var/log/deckhouse-bootstrap.log
```

**Common causes:**
- SSH to master not ready yet (wait 2–5 minutes)
- Harbor not up yet (wait 5–10 minutes)
- Proxy not working (on bastion: `ssh bastion 'systemctl status tinyproxy'`)

**Solution:** The installer waits for all dependencies automatically. Wait and follow the logs.

### Deckhouse installation stuck

**Symptoms:** Logs do not update for more than 10 minutes.

**Diagnostics:**
```bash
# SSH to registry
make ssh-registry

# Check installer process
ps aux | grep install-deckhouse

# Last 50 lines of logs
tail -50 /var/log/deckhouse-bootstrap.log

# Check dhctl state
ls -la /root/dhctl-tmp/
```

**Solution:**
```bash
# Restart installation manually
sudo pkill -f install-deckhouse
sudo /usr/local/bin/install-deckhouse.sh
```

### Resizing disk

To increase disk size (e.g. on registry for more images or IOPS):

```bash
# 1. Update terraform.tfvars
registry = {
  cores         = 2
  memory        = 4
  disk_size     = 200  # Was 100, now 200 GB
  core_fraction = 20
  preemptible   = true
}

# 2. Apply changes
make plan   # Review plan
make apply  # Apply (disk extended without recreating VM)

# 3. Optional: view disk info
make resize-disk HOST=registry  # Shows df -h for /dev/vd*

# 4. Expand filesystem on host
make resize-disk HOST=registry DEVICE=/dev/vda  # Resize /dev/vda2 (root)
make resize-disk HOST=master DEVICE=/dev/vdb    # Resize /dev/vdb (data disk)
```

### Error: Failed to configure (token expired)

**Problem:** YC_TOKEN expired (valid 12 hours).

**Solution:**
```bash
eval $(make export)
```

### Main logs

```bash
# Serial console (always available, even without SSH)
make serial-bastion   # Bastion serial console
make serial-registry  # Registry serial console
make serial-master    # Master serial console

# On hosts (via SSH)
/var/log/cloud-init-output.log   # Cloud-init (all hosts)
/var/log/harbor-install.log       # Harbor (registry)
/var/log/deckhouse-bootstrap.log  # Deckhouse installation (registry)
/root/dhctl-tmp/                  # dhctl state (registry)
```

### Monitoring Deckhouse installation

See section “Monitoring Deckhouse installation” above (`make logs-deckhouse`, `make check-deckhouse`). On registry: `tail -f /var/log/deckhouse-bootstrap.log`; completion marker: `test -f /var/lib/deckhouse-bootstrap-complete`.

## Links

- [Deckhouse Documentation](https://deckhouse.io/documentation/)
- [Yandex Cloud Provider](https://registry.terraform.io/providers/yandex-cloud/yandex/latest/docs)
- [OpenTofu Documentation](https://opentofu.org/docs/)
- [Harbor Documentation](https://goharbor.io/docs/)
- [Yandex Cloud Pricing](https://yandex.cloud/en/prices)

---

## For developers

### Project structure

```
.
├── main.tf, variables.tf, outputs.tf  # Terraform config
├── Makefile                           # Commands
├── modules/                           # Terraform modules
│   ├── network/                       # VPC and Security Groups
│   ├── bastion/                       # Bastion host
│   └── compute/                       # Generic VM module
├── templates/                         # Cloud-init templates
└── scripts/                           # Helper scripts
```
