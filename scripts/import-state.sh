#!/usr/bin/env bash
set -euo pipefail

echo "🔄 Restoring Terraform state from existing resources..."
echo ""

# Prefix (get from environment variable or use USER)
PREFIX=${TF_VAR_prefix:-${USER}}

echo "Prefix: $PREFIX"
echo ""

# Initialize Terraform
echo "1️⃣  Initializing Terraform..."
tofu init -upgrade
echo ""

# Get resource IDs from Yandex Cloud
echo "2️⃣  Getting resource IDs from cloud..."

# VPC Network
VPC_ID=$(yc vpc network list --format json | jq -r ".[] | select(.name == \"${PREFIX}-isolated-vpc\") | .id")
echo "VPC ID: $VPC_ID"

# Subnet
SUBNET_ID=$(yc vpc subnet list --format json | jq -r ".[] | select(.name == \"${PREFIX}-private-subnet\") | .id")
echo "Subnet ID: $SUBNET_ID"

# Security Groups
BASTION_SG_ID=$(yc vpc security-group list --format json | jq -r ".[] | select(.name == \"${PREFIX}-bastion-sg\") | .id")
echo "Bastion SG ID: $BASTION_SG_ID"

INTERNAL_SG_ID=$(yc vpc security-group list --format json | jq -r ".[] | select(.name == \"${PREFIX}-internal-sg\") | .id")
echo "Internal SG ID: $INTERNAL_SG_ID"

# Bastion IP
BASTION_IP_ID=$(yc vpc address list --format json | jq -r ".[] | select(.name == \"${PREFIX}-bastion-public-ip\") | .id")
echo "Bastion IP ID: $BASTION_IP_ID"

# Instances
BASTION_ID=$(yc compute instance list --format json | jq -r ".[] | select(.name == \"${PREFIX}-bastion\") | .id")
echo "Bastion ID: $BASTION_ID"

REGISTRY_ID=$(yc compute instance list --format json | jq -r ".[] | select(.name == \"${PREFIX}-registry\") | .id")
echo "Registry ID: $REGISTRY_ID"

MASTER_ID=$(yc compute instance list --format json | jq -r ".[] | select(.name == \"${PREFIX}-master\") | .id")
echo "Master ID: $MASTER_ID"

# Disks
REGISTRY_DISK_ID=$(yc compute disk list --format json | jq -r ".[] | select(.name == \"${PREFIX}-registry-root\") | .id")
echo "Registry disk ID: $REGISTRY_DISK_ID"

MASTER_ROOT_DISK_ID=$(yc compute disk list --format json | jq -r ".[] | select(.name == \"${PREFIX}-master-root\") | .id")
echo "Master root disk ID: $MASTER_ROOT_DISK_ID"

MASTER_DATA_DISK_ID=$(yc compute disk list --format json | jq -r ".[] | select(.name == \"${PREFIX}-master-data\") | .id")
echo "Master data disk ID: $MASTER_DATA_DISK_ID"

echo ""
echo "3️⃣  Importing resources to Terraform state..."

# Import network module
echo "   Importing network resources..."
tofu import module.network.yandex_vpc_network.vpc "$VPC_ID" || echo "⚠️  Network already imported or error"
tofu import module.network.yandex_vpc_subnet.private "$SUBNET_ID" || echo "⚠️  Subnet already imported or error"

# Import security groups
echo "   Importing security groups..."
tofu import module.network.yandex_vpc_security_group.bastion "$BASTION_SG_ID" || echo "⚠️  Bastion SG already imported or error"
tofu import module.network.yandex_vpc_security_group.internal "$INTERNAL_SG_ID" || echo "⚠️  Internal SG already imported or error"

# Import bastion module
echo "   Importing bastion resources..."
tofu import module.bastion.yandex_vpc_address.bastion_ip "$BASTION_IP_ID" || echo "⚠️  Bastion IP already imported or error"
tofu import module.bastion.yandex_compute_instance.bastion "$BASTION_ID" || echo "⚠️  Bastion instance already imported or error"

# Import disks
echo "   Importing disks..."
tofu import yandex_compute_disk.registry_root "$REGISTRY_DISK_ID" || echo "⚠️  Registry disk already imported or error"
tofu import yandex_compute_disk.master_root "$MASTER_ROOT_DISK_ID" || echo "⚠️  Master root disk already imported or error"
tofu import yandex_compute_disk.master_data "$MASTER_DATA_DISK_ID" || echo "⚠️  Master data disk already imported or error"

# Import registry module
echo "   Importing registry resources..."
tofu import module.registry.yandex_compute_instance.instance "$REGISTRY_ID" || echo "⚠️  Registry instance already imported or error"

# Import master module
echo "   Importing master resources..."
tofu import module.master.yandex_compute_instance.instance "$MASTER_ID" || echo "⚠️  Master instance already imported or error"

echo ""
echo "✅ Import completed!"
echo ""
echo "Check state with command: tofu state list"
echo "If there are discrepancies, run: tofu plan"
