# Terraform/OpenTofu — use bash for compatibility
SHELL := /bin/bash
.SHELLFLAGS := -c

# Common SSH options (suppress "Permanently added" warning, avoid known_hosts)
SSH_OPTS := -o StrictHostKeyChecking=no -o UserKnownHostsFile=/dev/null -o LogLevel=ERROR

.PHONY: help init plan apply destroy ssh ssh-bastion ssh-registry ssh-master ssh-upgrade fmt validate \
	tunnel-harbor urls logs-deckhouse check-deckhouse refresh dockercfg resize-disk \
	output-bastion output-registry output-master output-network \
	get-image-id vm-list vm-stop vm-start \
	serial-bastion serial-registry serial-master export export-yc export-prefix \
	show-vars git-hooks import-state generate-ssh-key

# Note: prefix is configured in terraform.tfvars
# To export all environment variables at once:
#   eval $(make export)
# Or individually:
#   eval $(make export-prefix)  # TF_VAR_prefix only
#   eval $(make export-yc)      # YC credentials only

# Shell function to format elapsed time (seconds to human readable)
# Usage in recipes: $$(format_time $$ELAPSED)
define FORMAT_TIME_FUNC
format_time() { \
	local ELAPSED=$$1; \
	local HOURS=$$((ELAPSED / 3600)); \
	local MINUTES=$$((ELAPSED % 3600 / 60)); \
	local SECONDS=$$((ELAPSED % 60)); \
	if [ $$HOURS -gt 0 ]; then \
		printf "%dh %dm %ds" $$HOURS $$MINUTES $$SECONDS; \
	elif [ $$MINUTES -gt 0 ]; then \
		printf "%dm %ds" $$MINUTES $$SECONDS; \
	else \
		printf "%ds" $$SECONDS; \
	fi; \
}
endef

# --- Help ---

help: ## Show this help message
	@printf "[INFO] Available commands:\n"
	@grep -E '^[a-zA-Z_-]+:.*?## .*$$' $(MAKEFILE_LIST) | sort | awk 'BEGIN {FS = ":.*?## "}; {printf "  %-15s %s\n", $$1, $$2}'

# --- Terraform ---

generate-ssh-key: ## Generate SSH key pair in .ssh/ directory (if not exists)
	@printf "[INFO] Checking SSH key...\n"
	@mkdir -p .ssh
	@if [ ! -f .ssh/id_ed25519 ]; then \
		printf "[INFO] Generating new SSH key pair...\n"; \
		ssh-keygen -t ed25519 -f .ssh/id_ed25519 -N "" -C "yc-d8-airgapped-$$(date +%Y%m%d)"; \
		printf "[INFO] SSH key generated: .ssh/id_ed25519\n"; \
	else \
		printf "[INFO] SSH key already exists: .ssh/id_ed25519\n"; \
	fi

init: generate-ssh-key ## Initialize Terraform/OpenTofu (auto-generates SSH key if needed)
	@printf "[INFO] Initializing Terraform...\n"
	tofu init

plan: ## Show plan of changes
	@printf "[INFO] Creating plan of changes...\n"
	tofu plan

apply: ## Apply configuration
	@printf "[INFO] Applying configuration...\n"
	@$(FORMAT_TIME_FUNC); \
	START_TIME=$$(date +%s); \
	tofu apply -auto-approve; \
	EXIT_CODE=$$?; \
	END_TIME=$$(date +%s); \
	ELAPSED=$$((END_TIME - START_TIME)); \
	echo ""; \
	if [ $$EXIT_CODE -eq 0 ]; then \
		printf "[INFO] Configuration applied successfully in %s\n" "$$(format_time $$ELAPSED)"; \
	else \
		printf "[ERROR] Operation completed with errors in %s\n" "$$(format_time $$ELAPSED)"; \
		exit $$EXIT_CODE; \
	fi

destroy: ## Destroy all infrastructure
	@printf "[INFO] Destroying infrastructure...\n"
	@$(FORMAT_TIME_FUNC); \
	START_TIME=$$(date +%s); \
	tofu destroy; \
	EXIT_CODE=$$?; \
	END_TIME=$$(date +%s); \
	ELAPSED=$$((END_TIME - START_TIME)); \
	echo ""; \
	if [ $$EXIT_CODE -eq 0 ]; then \
		printf "[INFO] Infrastructure destroyed successfully in %s\n" "$$(format_time $$ELAPSED)"; \
	else \
		printf "[ERROR] Operation completed with errors in %s\n" "$$(format_time $$ELAPSED)"; \
		exit $$EXIT_CODE; \
	fi

# --- SSH & utils ---

ssh: ## Show SSH connection commands
	@printf "[INFO] SSH Connection Commands:\n"
	@printf "\n"
	@SSH_CONFIG=$$(tofu output -json ssh_config 2>/dev/null); \
	if [ -z "$$SSH_CONFIG" ]; then \
		printf "[ERROR] No infrastructure deployed\n"; \
		exit 1; \
	fi; \
	SSH_KEY=$$(echo "$$SSH_CONFIG" | jq -r '.private_key_path // "~/.ssh/id_ed25519"'); \
	SSH_USER=$$(echo "$$SSH_CONFIG" | jq -r '.username // "ubuntu"'); \
	BASTION_IP=$$(tofu output -json bastion 2>/dev/null | jq -r '.public_ip // empty'); \
	REGISTRY_IP=$$(tofu output -json registry 2>/dev/null | jq -r '.internal_ip // empty'); \
	MASTER_IP=$$(tofu output -json master 2>/dev/null | jq -r '.internal_ip // empty'); \
	printf "bastion:\n"; \
	echo "  ssh -i $$SSH_KEY $(SSH_OPTS) $$SSH_USER@$$BASTION_IP"; \
	echo ""; \
	printf "registry:\n"; \
	echo "  ssh -i $$SSH_KEY $(SSH_OPTS) \\"; \
	echo "    -o ProxyCommand=\"ssh -i $$SSH_KEY $(SSH_OPTS) -W %h:%p $$SSH_USER@$$BASTION_IP\" \\"; \
	echo "    $$SSH_USER@$$REGISTRY_IP"; \
	echo ""; \
	printf "master:\n"; \
	echo "  ssh -i $$SSH_KEY $(SSH_OPTS) \\"; \
	echo "    -o ProxyCommand=\"ssh -i $$SSH_KEY $(SSH_OPTS) -W %h:%p $$SSH_USER@$$BASTION_IP\" \\"; \
	echo "    $$SSH_USER@$$MASTER_IP"; \
	echo ""; \
	printf "[INFO] Quick connect: make ssh-bastion | make ssh-registry | make ssh-master\n"

ssh-bastion: ## Connect to bastion via SSH
	@SSH_CONFIG=$$(tofu output -json ssh_config 2>/dev/null); \
	SSH_KEY=$$(echo "$$SSH_CONFIG" | jq -r '.private_key_path // "~/.ssh/id_ed25519"'); \
	SSH_USER=$$(echo "$$SSH_CONFIG" | jq -r '.username // "ubuntu"'); \
	BASTION_IP=$$(tofu output -json bastion 2>/dev/null | jq -r '.public_ip'); \
	printf "[INFO] Connecting to bastion ($$BASTION_IP)...\n"; \
	ssh -i $$SSH_KEY $(SSH_OPTS) $$SSH_USER@$$BASTION_IP

ssh-registry: ## Connect to registry via SSH (through bastion)
	@SSH_CONFIG=$$(tofu output -json ssh_config 2>/dev/null); \
	SSH_KEY=$$(echo "$$SSH_CONFIG" | jq -r '.private_key_path // "~/.ssh/id_ed25519"'); \
	SSH_USER=$$(echo "$$SSH_CONFIG" | jq -r '.username // "ubuntu"'); \
	BASTION_IP=$$(tofu output -json bastion 2>/dev/null | jq -r '.public_ip'); \
	REGISTRY_IP=$$(tofu output -json registry 2>/dev/null | jq -r '.internal_ip'); \
	printf "[INFO] Connecting to registry ($$REGISTRY_IP) via bastion...\n"; \
	ssh -i $$SSH_KEY $(SSH_OPTS) \
		-o ProxyCommand="ssh -i $$SSH_KEY $(SSH_OPTS) -W %h:%p $$SSH_USER@$$BASTION_IP" \
		$$SSH_USER@$$REGISTRY_IP

ssh-master: ## Connect to master via SSH (through bastion)
	@SSH_CONFIG=$$(tofu output -json ssh_config 2>/dev/null); \
	SSH_KEY=$$(echo "$$SSH_CONFIG" | jq -r '.private_key_path // "~/.ssh/id_ed25519"'); \
	SSH_USER=$$(echo "$$SSH_CONFIG" | jq -r '.username // "ubuntu"'); \
	BASTION_IP=$$(tofu output -json bastion 2>/dev/null | jq -r '.public_ip'); \
	MASTER_IP=$$(tofu output -json master 2>/dev/null | jq -r '.internal_ip'); \
	printf "[INFO] Connecting to master ($$MASTER_IP) via bastion...\n"; \
	ssh -i $$SSH_KEY $(SSH_OPTS) \
		-o ProxyCommand="ssh -i $$SSH_KEY $(SSH_OPTS) -W %h:%p $$SSH_USER@$$BASTION_IP" \
		$$SSH_USER@$$MASTER_IP

ssh-upgrade: ## Upgrade packages on all hosts (apt update && apt dist-upgrade)
	@printf "[INFO] Upgrading packages on all hosts...\n"
	@SSH_CONFIG=$$(tofu output -json ssh_config 2>/dev/null); \
	SSH_KEY=$$(echo "$$SSH_CONFIG" | jq -r '.private_key_path // "~/.ssh/id_ed25519"'); \
	SSH_USER=$$(echo "$$SSH_CONFIG" | jq -r '.username // "ubuntu"'); \
	BASTION_IP=$$(tofu output -json bastion | jq -r '.public_ip'); \
	REGISTRY_IP=$$(tofu output -json registry | jq -r '.internal_ip'); \
	MASTER_IP=$$(tofu output -json master | jq -r '.internal_ip'); \
	printf "[INFO] Upgrading bastion ($$BASTION_IP)...\n"; \
	ssh -i $$SSH_KEY $(SSH_OPTS) $$SSH_USER@$$BASTION_IP 'sudo apt-get update && sudo DEBIAN_FRONTEND=noninteractive apt-get dist-upgrade -y'; \
	printf "[INFO] Upgrading registry ($$REGISTRY_IP)...\n"; \
	ssh -i $$SSH_KEY $(SSH_OPTS) -o ProxyCommand="ssh -i $$SSH_KEY $(SSH_OPTS) -W %h:%p $$SSH_USER@$$BASTION_IP" $$SSH_USER@$$REGISTRY_IP 'sudo apt-get update && sudo DEBIAN_FRONTEND=noninteractive apt-get dist-upgrade -y'; \
	printf "[INFO] Upgrading master ($$MASTER_IP)...\n"; \
	ssh -i $$SSH_KEY $(SSH_OPTS) -o ProxyCommand="ssh -i $$SSH_KEY $(SSH_OPTS) -W %h:%p $$SSH_USER@$$BASTION_IP" $$SSH_USER@$$MASTER_IP 'sudo apt-get update && sudo DEBIAN_FRONTEND=noninteractive apt-get dist-upgrade -y'; \
	printf "[INFO] All hosts upgraded\n"

fmt: ## Format .tf files
	@printf "[INFO] Formatting code...\n"
	tofu fmt -recursive

validate: ## Validate configuration
	@printf "[INFO] Validating configuration...\n"
	tofu validate

# --- Tunnel ---

tunnel-harbor: ## Create SSH tunnel to Harbor UI (localhost:8443 - HTTPS)
	@printf "[INFO] Creating SSH tunnel to Harbor...\n"
	@SSH_CONFIG=$$(tofu output -json ssh_config 2>/dev/null); \
	SSH_KEY=$$(echo "$$SSH_CONFIG" | jq -r '.private_key_path // "~/.ssh/id_ed25519"'); \
	SSH_USER=$$(echo "$$SSH_CONFIG" | jq -r '.username // "ubuntu"'); \
	BASTION_IP=$$(tofu output -json bastion 2>/dev/null | jq -r '.public_ip // empty'); \
	REGISTRY_IP=$$(tofu output -json registry 2>/dev/null | jq -r '.internal_ip // empty'); \
	HARBOR_PASSWORD=$$(tofu output -json registry 2>/dev/null | jq -r '.harbor_admin_password // "Harbor12345"' || echo "Harbor12345"); \
	if [ -z "$$BASTION_IP" ] || [ -z "$$REGISTRY_IP" ]; then \
		printf "[WARN] Failed to get IP addresses. Is infrastructure deployed?\n"; \
		exit 1; \
	fi; \
	printf "[INFO] Tunnel parameters ready\n"; \
	echo ""; \
	printf "[INFO] Open in browser: https://localhost:8443\n"; \
	printf "[INFO] Note: Accept self-signed certificate warning in browser\n"; \
	echo ""; \
	printf "[INFO] Login: admin\n"; \
	printf "[INFO] Password: $$HARBOR_PASSWORD\n"; \
	echo ""; \
	printf "[INFO] Press Ctrl+C to stop\n"; \
	echo ""; \
	ssh -i $$SSH_KEY $(SSH_OPTS) -L 8443:$$REGISTRY_IP:443 -o ProxyCommand="ssh -i $$SSH_KEY $(SSH_OPTS) -W %h:%p $$SSH_USER@$$BASTION_IP" $$SSH_USER@$$REGISTRY_IP

urls: ## Show Deckhouse UI and Harbor access URLs (via sslip.io with Let's Encrypt)
	@printf "[INFO] Deckhouse UI & Harbor Access Information (sslip.io)\n"
	@printf "\n"
	@BASTION_IP=$$(tofu output -json bastion 2>/dev/null | jq -r '.public_ip // empty'); \
	if [ -z "$$BASTION_IP" ]; then \
		printf "[WARN] Infrastructure not deployed\n"; \
		printf "[WARN] Run 'make apply' first\n"; \
		exit 1; \
	fi; \
	SSLIP_IP=$$(echo $$BASTION_IP | tr '.' '-'); \
	printf "[INFO] Bastion IP: $$BASTION_IP\n"; \
	printf "[INFO] sslip.io domain: $$SSLIP_IP.sslip.io\n"; \
	echo ""; \
	printf "[INFO] Deckhouse URLs (with valid SSL after Deckhouse installation):\n"; \
	echo "  Console:         https://console.$$SSLIP_IP.sslip.io"; \
	echo ""; \
	printf "[INFO] Deckhouse Login credentials:\n"; \
	echo "  Email:    admin@deckhouse.io"; \
	echo "  Password: 7md03yxgzt"; \
	echo ""; \
	printf "[INFO] Harbor Registry:\n"; \
	echo "  URL:      https://harbor.$$SSLIP_IP.sslip.io"; \
	echo "  Login:    admin"; \
	echo "  Password: Harbor12345"; \
	echo ""

# --- Deckhouse ---

dockercfg: ## Generate base64-encoded dockerconfigjson for Harbor registry (optional: REGISTRY=... USER=... PASSWORD=...)
	@printf "[INFO] Generating dockerconfigjson for Harbor registry...\n"
	@if [ -n "$(REGISTRY)" ] && [ -n "$(USER)" ] && [ -n "$(PASSWORD)" ]; then \
		REGISTRY_FQDN="$(REGISTRY)"; \
		REGISTRY_USER="$(USER)"; \
		REGISTRY_PASSWORD="$(PASSWORD)"; \
		printf "[INFO] Using manually provided credentials\n"; \
		printf "[INFO] Registry: $$REGISTRY_FQDN\n"; \
		printf "[INFO] Username: $$REGISTRY_USER\n"; \
		echo ""; \
		AUTH_BASE64=$$(printf "%s" "$$REGISTRY_USER:$$REGISTRY_PASSWORD" | base64 | tr -d '\n'); \
		DOCKER_CONFIG_JSON=$$(jq -n \
			--arg registry "$$REGISTRY_FQDN" \
			--arg username "$$REGISTRY_USER" \
			--arg password "$$REGISTRY_PASSWORD" \
			--arg auth "$$AUTH_BASE64" \
			'{auths: {($$registry): {username: $$username, password: $$password, auth: $$auth}}}' | base64 | tr -d '\n'); \
	else \
		REGISTRY_FQDN=$$(tofu output -json registry 2>/dev/null | jq -r '.fqdn // empty'); \
		REGISTRY_USER=$$(tofu output -json registry 2>/dev/null | jq -r '.harbor_admin_user // empty'); \
		REGISTRY_PASSWORD=$$(tofu output -json registry 2>/dev/null | jq -r '.harbor_admin_password // empty'); \
		BASTION_IP=$$(tofu output -json bastion 2>/dev/null | jq -r '.public_ip // empty'); \
		if [ -z "$$REGISTRY_FQDN" ] || [ -z "$$REGISTRY_USER" ] || [ -z "$$REGISTRY_PASSWORD" ] || [ -z "$$BASTION_IP" ]; then \
			printf "[WARN] Failed to get registry data from terraform. Is infrastructure deployed?\n"; \
			printf "[WARN] Or provide credentials manually:\n"; \
			printf "[WARN]   make dockercfg REGISTRY=harbor.51-250-68-57.sslip.io USER=admin PASSWORD=Harbor12345\n"; \
			exit 1; \
		fi; \
		SSLIP_DOMAIN=$$(echo "$$BASTION_IP" | tr '.' '-'); \
		REGISTRY_EXTERNAL="harbor.$$SSLIP_DOMAIN.sslip.io"; \
		printf "[INFO] Using credentials from Terraform outputs\n"; \
		printf "[INFO] Registry (internal): $$REGISTRY_FQDN\n"; \
		printf "[INFO] Registry (external): $$REGISTRY_EXTERNAL\n"; \
		printf "[INFO] Username: $$REGISTRY_USER\n"; \
		echo ""; \
		AUTH_BASE64=$$(printf "%s" "$$REGISTRY_USER:$$REGISTRY_PASSWORD" | base64 | tr -d '\n'); \
		DOCKER_CONFIG_JSON=$$(jq -n \
			--arg registry_internal "$$REGISTRY_FQDN" \
			--arg registry_external "$$REGISTRY_EXTERNAL" \
			--arg username "$$REGISTRY_USER" \
			--arg password "$$REGISTRY_PASSWORD" \
			--arg auth "$$AUTH_BASE64" \
			'{auths: {($$registry_internal): {username: $$username, password: $$password, auth: $$auth}, ($$registry_external): {username: $$username, password: $$password, auth: $$auth}}}' | base64 | tr -d '\n'); \
	fi; \
	printf "[INFO] Base64-encoded dockerconfigjson:\n"; \
	echo "$$DOCKER_CONFIG_JSON"; \
	echo ""; \
	printf "[INFO] Usage in Kubernetes Secret:\n"; \
	echo "  kubectl create secret docker-registry harbor-registry \\"; \
	echo "    --from-file=.dockerconfigjson=<(echo \"$$DOCKER_CONFIG_JSON\" | base64 -d) \\"; \
	echo "    --type=kubernetes.io/dockerconfigjson"

logs-deckhouse: ## Show Deckhouse installation logs (from registry host)
	@printf "[INFO] Showing Deckhouse installation logs...\n"
	@SSH_CONFIG=$$(tofu output -json ssh_config 2>/dev/null); \
	SSH_KEY=$$(echo "$$SSH_CONFIG" | jq -r '.private_key_path // "~/.ssh/id_ed25519"'); \
	SSH_USER=$$(echo "$$SSH_CONFIG" | jq -r '.username // "ubuntu"'); \
	BASTION_IP=$$(tofu output -json bastion 2>/dev/null | jq -r '.public_ip // empty'); \
	REGISTRY_IP=$$(tofu output -json registry 2>/dev/null | jq -r '.internal_ip // empty'); \
	if [ -z "$$BASTION_IP" ] || [ -z "$$REGISTRY_IP" ]; then \
		printf "[WARN] Infrastructure not deployed\n"; \
		exit 1; \
	fi; \
	printf "[INFO] Press Ctrl+C to stop following logs\n"; \
	echo ""; \
	ssh -i $$SSH_KEY $(SSH_OPTS) \
		-o ProxyCommand="ssh -i $$SSH_KEY $(SSH_OPTS) -W %h:%p $$SSH_USER@$$BASTION_IP" \
		$$SSH_USER@$$REGISTRY_IP "tail -f /var/log/deckhouse-bootstrap.log"

check-deckhouse: ## Check Deckhouse installation status and cluster health
	@printf "[INFO] Checking Deckhouse installation status...\n"
	@SSH_CONFIG=$$(tofu output -json ssh_config 2>/dev/null); \
	SSH_KEY=$$(echo "$$SSH_CONFIG" | jq -r '.private_key_path // "~/.ssh/id_ed25519"'); \
	SSH_USER=$$(echo "$$SSH_CONFIG" | jq -r '.username // "ubuntu"'); \
	BASTION_IP=$$(tofu output -json bastion 2>/dev/null | jq -r '.public_ip // empty'); \
	REGISTRY_IP=$$(tofu output -json registry 2>/dev/null | jq -r '.internal_ip // empty'); \
	MASTER_IP=$$(tofu output -json master 2>/dev/null | jq -r '.internal_ip // empty'); \
	if [ -z "$$BASTION_IP" ] || [ -z "$$REGISTRY_IP" ] || [ -z "$$MASTER_IP" ]; then \
		printf "[WARN] Infrastructure not deployed\n"; \
		exit 1; \
	fi; \
	echo ""; \
	printf "[INFO] Checking SSH connectivity to registry...\n"; \
	if ! ssh -i $$SSH_KEY $(SSH_OPTS) -o ConnectTimeout=10 \
		-o ProxyCommand="ssh -i $$SSH_KEY $(SSH_OPTS) -o ConnectTimeout=10 -W %h:%p $$SSH_USER@$$BASTION_IP" \
		$$SSH_USER@$$REGISTRY_IP "echo ok" >/dev/null 2>&1; then \
		printf "[WARN] Cannot connect to registry. Hosts may still be booting.\n"; \
		printf "[WARN] Wait a few minutes and try again: make check-deckhouse\n"; \
		exit 1; \
	fi; \
	printf "[INFO] SSH connection established\n"; \
	echo ""; \
	printf "[INFO] Checking installation completion marker...\n"; \
	if ssh -i $$SSH_KEY $(SSH_OPTS) -o ConnectTimeout=10 \
		-o ProxyCommand="ssh -i $$SSH_KEY $(SSH_OPTS) -o ConnectTimeout=10 -W %h:%p $$SSH_USER@$$BASTION_IP" \
		$$SSH_USER@$$REGISTRY_IP "test -f /var/lib/deckhouse-bootstrap-complete" 2>/dev/null; then \
		printf "[INFO] Deckhouse bootstrap completed\n"; \
		TIMESTAMP=$$(ssh -i $$SSH_KEY $(SSH_OPTS) \
			-o ProxyCommand="ssh -i $$SSH_KEY $(SSH_OPTS) -W %h:%p $$SSH_USER@$$BASTION_IP" \
			$$SSH_USER@$$REGISTRY_IP "cat /var/lib/deckhouse-bootstrap-timestamp 2>/dev/null || echo 'unknown'"); \
		printf "[INFO] Completed at: $$TIMESTAMP\n"; \
		echo ""; \
		printf "[INFO] Checking Kubernetes cluster on master...\n"; \
		ssh -i $$SSH_KEY $(SSH_OPTS) \
			-o ProxyCommand="ssh -i $$SSH_KEY $(SSH_OPTS) -W %h:%p $$SSH_USER@$$BASTION_IP" \
			$$SSH_USER@$$MASTER_IP "sudo -i d8 k get nodes 2>/dev/null || echo 'Kubernetes not ready yet'" || true; \
		echo ""; \
		printf "[INFO] Access Deckhouse Console:\n"; \
		SSLIP_IP=$$(echo $$BASTION_IP | tr '.' '-'); \
		echo "  URL:      https://console.$$SSLIP_IP.sslip.io"; \
		echo "  Email:    admin@deckhouse.io"; \
		echo "  Password: 7md03yxgzt"; \
		echo ""; \
		printf "[INFO] See all URLs: make urls\n"; \
	else \
		printf "[INFO] Deckhouse installation still in progress...\n"; \
		echo ""; \
		printf "[WARN] Monitor progress with: make logs-deckhouse - view live logs\n"; \
		echo ""; \
		printf "[INFO] Last 10 lines of log:\n"; \
		ssh -i $$SSH_KEY $(SSH_OPTS) \
			-o ProxyCommand="ssh -i $$SSH_KEY $(SSH_OPTS) -W %h:%p $$SSH_USER@$$BASTION_IP" \
			$$SSH_USER@$$REGISTRY_IP "tail -10 /var/log/deckhouse-bootstrap.log 2>/dev/null || echo 'Log file not available yet'"; \
	fi

# --- Composite ---

refresh: ## Refresh state and show outputs
	@printf "[INFO] Refreshing state...\n"
	tofu refresh
	@make ssh


# --- Outputs ---

output-bastion: ## Show bastion information
	@tofu output -json bastion | jq

output-registry: ## Show registry information
	@tofu output -json registry | jq

output-master: ## Show master information
	@tofu output -json master | jq

output-network: ## Show network information
	@printf "[INFO] NETWORK INFORMATION\n"
	@tofu output -json network | jq -r '"VPC Name:    " + .vpc_name'
	@tofu output -json network | jq -r '"VPC ID:      " + .vpc_id'
	@printf "\n"
	@tofu output -json network | jq -r '"Subnet Name: " + .subnet_name'
	@tofu output -json network | jq -r '"Subnet ID:   " + .subnet_id'
	@tofu output -json network | jq -r '"Subnet CIDR: " + .subnet_cidr'
	@tofu output -json network | jq -r '"Subnet Zone: " + .subnet_zone'

# --- Yandex Cloud ---

get-image-id: ## Get ID of latest OS image (default: ubuntu-2404-lts-oslogin, or FAMILY=ubuntu-2404-lts-oslogin/ubuntu-2404-lts/debian-12)
	@FAMILY=$${FAMILY:-ubuntu-2404-lts-oslogin}; \
	printf "[INFO] Getting ID of latest $$FAMILY image...\n"; \
	IMAGE_ID=$$(yc compute image list --folder-id standard-images --format json | jq -r "[.[] | select(.family == \"$$FAMILY\")] | sort_by(.created_at)[-1].id"); \
	if [ -z "$$IMAGE_ID" ]; then \
		printf "[ERROR] No image found for family: $$FAMILY\n"; \
		exit 1; \
	fi; \
	printf "[INFO] Image ID: $$IMAGE_ID\n"; \
	printf "[INFO] Add to terraform.tfvars:\n"; \
	printf "  image_id = \"$$IMAGE_ID\"\n"

vm-list: ## Show list of VMs in current infrastructure
	@BASTION_DATA=$$(tofu output -json bastion 2>/dev/null); \
	REGISTRY_DATA=$$(tofu output -json registry 2>/dev/null); \
	MASTER_DATA=$$(tofu output -json master 2>/dev/null); \
	if [ -z "$$BASTION_DATA" ]; then \
		printf "[WARN] No infrastructure deployed\n"; \
		printf "[WARN] Run 'make apply' first\n"; \
		exit 1; \
	fi; \
	echo "+----------------------+-------------------+---------------+---------+-----------------+-------------+"; \
	printf "| %-20s | %-17s | %-13s | %-7s | %-15s | %-11s |\n" "ID" "NAME" "ZONE ID" "STATUS" "EXTERNAL IP" "INTERNAL IP"; \
	echo "+----------------------+-------------------+---------------+---------+-----------------+-------------+"; \
	BASTION_ID=$$(echo "$$BASTION_DATA" | jq -r '.id'); \
	BASTION_NAME=$$(echo "$$BASTION_DATA" | jq -r '.name'); \
	BASTION_PUB=$$(echo "$$BASTION_DATA" | jq -r '.public_ip'); \
	BASTION_INT=$$(echo "$$BASTION_DATA" | jq -r '.internal_ip'); \
	BASTION_INFO=$$(yc compute instance get $$BASTION_ID --format json 2>/dev/null); \
	BASTION_STATUS=$$(echo "$$BASTION_INFO" | jq -r '.status // "UNKNOWN"'); \
	BASTION_ZONE=$$(echo "$$BASTION_INFO" | jq -r '.zone_id // "unknown"'); \
	printf "| %-20s | %-17s | %-13s | %-7s | %-15s | %-11s |\n" "$$BASTION_ID" "$$BASTION_NAME" "$$BASTION_ZONE" "$$BASTION_STATUS" "$$BASTION_PUB" "$$BASTION_INT"; \
	REGISTRY_ID=$$(echo "$$REGISTRY_DATA" | jq -r '.id'); \
	REGISTRY_NAME=$$(echo "$$REGISTRY_DATA" | jq -r '.name'); \
	REGISTRY_INT=$$(echo "$$REGISTRY_DATA" | jq -r '.internal_ip'); \
	REGISTRY_INFO=$$(yc compute instance get $$REGISTRY_ID --format json 2>/dev/null); \
	REGISTRY_STATUS=$$(echo "$$REGISTRY_INFO" | jq -r '.status // "UNKNOWN"'); \
	REGISTRY_ZONE=$$(echo "$$REGISTRY_INFO" | jq -r '.zone_id // "unknown"'); \
	printf "| %-20s | %-17s | %-13s | %-7s | %-15s | %-11s |\n" "$$REGISTRY_ID" "$$REGISTRY_NAME" "$$REGISTRY_ZONE" "$$REGISTRY_STATUS" "" "$$REGISTRY_INT"; \
	MASTER_ID=$$(echo "$$MASTER_DATA" | jq -r '.id'); \
	MASTER_NAME=$$(echo "$$MASTER_DATA" | jq -r '.name'); \
	MASTER_INT=$$(echo "$$MASTER_DATA" | jq -r '.internal_ip'); \
	MASTER_INFO=$$(yc compute instance get $$MASTER_ID --format json 2>/dev/null); \
	MASTER_STATUS=$$(echo "$$MASTER_INFO" | jq -r '.status // "UNKNOWN"'); \
	MASTER_ZONE=$$(echo "$$MASTER_INFO" | jq -r '.zone_id // "unknown"'); \
	printf "| %-20s | %-17s | %-13s | %-7s | %-15s | %-11s |\n" "$$MASTER_ID" "$$MASTER_NAME" "$$MASTER_ZONE" "$$MASTER_STATUS" "" "$$MASTER_INT"; \
	echo "+----------------------+-------------------+---------------+---------+-----------------+-------------+"

vm-stop: ## Stop all VMs in current infrastructure
	@printf "[INFO] Stopping all VMs in current infrastructure...\n"; \
	BASTION_ID=$$(tofu output -json bastion 2>/dev/null | jq -r '.id // empty'); \
	REGISTRY_ID=$$(tofu output -json registry 2>/dev/null | jq -r '.id // empty'); \
	MASTER_ID=$$(tofu output -json master 2>/dev/null | jq -r '.id // empty'); \
	if [ -z "$$BASTION_ID" ]; then \
		printf "[WARN] No infrastructure deployed\n"; \
		printf "[WARN] Run 'make apply' first\n"; \
		exit 1; \
	fi; \
	for INSTANCE_ID in $$BASTION_ID $$REGISTRY_ID $$MASTER_ID; do \
		INSTANCE_NAME=$$(yc compute instance get $$INSTANCE_ID --format json 2>/dev/null | jq -r '.name // "unknown"'); \
		INSTANCE_STATUS=$$(yc compute instance get $$INSTANCE_ID --format json 2>/dev/null | jq -r '.status // "UNKNOWN"'); \
		if [ "$$INSTANCE_STATUS" = "RUNNING" ]; then \
			printf "[INFO] Stopping $$INSTANCE_NAME...\n"; \
			yc compute instance stop $$INSTANCE_ID --async; \
		else \
			printf "[INFO] $$INSTANCE_NAME already stopped (status: $$INSTANCE_STATUS)\n"; \
		fi; \
	done; \
	printf "[INFO] Stop commands sent\n"

vm-start: ## Start all VMs in current infrastructure
	@printf "[INFO] Starting all VMs in current infrastructure...\n"; \
	BASTION_ID=$$(tofu output -json bastion 2>/dev/null | jq -r '.id // empty'); \
	REGISTRY_ID=$$(tofu output -json registry 2>/dev/null | jq -r '.id // empty'); \
	MASTER_ID=$$(tofu output -json master 2>/dev/null | jq -r '.id // empty'); \
	if [ -z "$$BASTION_ID" ]; then \
		printf "[WARN] No infrastructure deployed\n"; \
		printf "[WARN] Run 'make apply' first\n"; \
		exit 1; \
	fi; \
	for INSTANCE_ID in $$BASTION_ID $$REGISTRY_ID $$MASTER_ID; do \
		INSTANCE_NAME=$$(yc compute instance get $$INSTANCE_ID --format json 2>/dev/null | jq -r '.name // "unknown"'); \
		INSTANCE_STATUS=$$(yc compute instance get $$INSTANCE_ID --format json 2>/dev/null | jq -r '.status // "UNKNOWN"'); \
		if [ "$$INSTANCE_STATUS" = "STOPPED" ]; then \
			printf "[INFO] Starting $$INSTANCE_NAME...\n"; \
			yc compute instance start $$INSTANCE_ID --async; \
		else \
			printf "[INFO] $$INSTANCE_NAME already running (status: $$INSTANCE_STATUS)\n"; \
		fi; \
	done; \
	printf "[INFO] Start commands sent\n"

resize-disk: ## Resize disk filesystem on a host (usage: make resize-disk HOST=registry [DEVICE=/dev/vda] [PARTITION=2])
	@if [ -z "$(HOST)" ]; then \
		printf "[WARN] HOST parameter is required\n"; \
		printf "[INFO] Usage examples:\n"; \
		printf "  make resize-disk HOST=registry                    # Show disk info\n"; \
		printf "  make resize-disk HOST=registry DEVICE=/dev/vda    # Resize /dev/vda2 (root partition)\n"; \
		printf "  make resize-disk HOST=master DEVICE=/dev/vdb     # Resize /dev/vdb (whole disk, no partition)\n"; \
		printf "  make resize-disk HOST=master DEVICE=/dev/vda PARTITION=1  # Resize /dev/vda1\n"; \
		exit 1; \
	fi
	@SSH_CONFIG=$$(tofu output -json ssh_config 2>/dev/null); \
	SSH_KEY=$$(echo "$$SSH_CONFIG" | jq -r '.private_key_path // "~/.ssh/id_ed25519"'); \
	SSH_USER=$$(echo "$$SSH_CONFIG" | jq -r '.username // "ubuntu"'); \
	BASTION_IP=$$(tofu output -json bastion 2>/dev/null | jq -r '.public_ip // empty'); \
	TARGET_IP=$$(tofu output -json $(HOST) 2>/dev/null | jq -r '.internal_ip // empty'); \
	if [ -z "$$BASTION_IP" ] || [ -z "$$TARGET_IP" ]; then \
		printf "[WARN] Failed to get IP addresses. Is infrastructure deployed?\n"; \
		exit 1; \
	fi; \
	if [ -z "$(DEVICE)" ]; then \
		printf "[INFO] Disk information for $(HOST)...\n"; \
		printf "[INFO] Target: $$TARGET_IP\n"; \
		echo ""; \
		ssh -i $$SSH_KEY $(SSH_OPTS) \
			-o ProxyCommand="ssh -i $$SSH_KEY $(SSH_OPTS) -W %h:%p $$SSH_USER@$$BASTION_IP" \
			$$SSH_USER@$$TARGET_IP \
			"df -h | grep '/dev/vd'"; \
	else \
		DEVICE=$(DEVICE); \
		PARTITION=$${PARTITION}; \
		if [ -z "$$PARTITION" ]; then \
			if [ "$$DEVICE" = "/dev/vda" ]; then \
				PARTITION=2; \
			fi; \
		fi; \
		if [ -z "$$PARTITION" ]; then \
			FULL_DEVICE="$$DEVICE"; \
			printf "[INFO] Resizing disk on $(HOST) (whole disk)...\n"; \
			printf "[INFO] Target: $$TARGET_IP\n"; \
			printf "[INFO] Device: $$FULL_DEVICE\n"; \
			echo ""; \
			ssh -i $$SSH_KEY $(SSH_OPTS) \
				-o ProxyCommand="ssh -i $$SSH_KEY $(SSH_OPTS) -W %h:%p $$SSH_USER@$$BASTION_IP" \
				$$SSH_USER@$$TARGET_IP \
				"echo '=== Before resize ===' && df -h | grep '/dev/vd' && echo '' && echo '=== Resizing filesystem (no partition table) ===' && sudo resize2fs $$FULL_DEVICE && echo '' && echo '=== After resize ===' && df -h | grep '/dev/vd'"; \
		else \
			FULL_DEVICE="$$DEVICE$$PARTITION"; \
			printf "[INFO] Resizing disk on $(HOST) (with partition)...\n"; \
			printf "[INFO] Target: $$TARGET_IP\n"; \
			printf "[INFO] Device: $$FULL_DEVICE\n"; \
			echo ""; \
			ssh -i $$SSH_KEY $(SSH_OPTS) \
				-o ProxyCommand="ssh -i $$SSH_KEY $(SSH_OPTS) -W %h:%p $$SSH_USER@$$BASTION_IP" \
				$$SSH_USER@$$TARGET_IP \
				"echo '=== Before resize ===' && df -h | grep '/dev/vd' && echo '' && echo '=== Growing partition ===' && sudo growpart $$DEVICE $$PARTITION && echo '' && echo '=== Resizing filesystem ===' && sudo resize2fs $$FULL_DEVICE && echo '' && echo '=== After resize ===' && df -h | grep '/dev/vd'"; \
		fi; \
	fi

# --- Serial console ---

serial-bastion: ## Get serial console output of bastion
	@printf "[INFO] Getting serial console output of bastion...\n"
	@BASTION_ID=$$(tofu output -json bastion 2>/dev/null | jq -r '.id // empty'); \
	if [ -z "$$BASTION_ID" ]; then \
		printf "[WARN] Failed to get bastion ID. Is infrastructure deployed?\n"; \
		exit 1; \
	fi; \
	yc compute instance get-serial-port-output $$BASTION_ID

serial-registry: ## Get serial console output of registry
	@printf "[INFO] Getting serial console output of registry...\n"
	@REGISTRY_ID=$$(tofu output -json registry 2>/dev/null | jq -r '.id // empty'); \
	if [ -z "$$REGISTRY_ID" ]; then \
		printf "[WARN] Failed to get registry ID. Is infrastructure deployed?\n"; \
		exit 1; \
	fi; \
	yc compute instance get-serial-port-output $$REGISTRY_ID

serial-master: ## Get serial console output of master
	@printf "[INFO] Getting serial console output of master...\n"
	@MASTER_ID=$$(tofu output -json master 2>/dev/null | jq -r '.id // empty'); \
	if [ -z "$$MASTER_ID" ]; then \
		printf "[WARN] Failed to get master ID. Is infrastructure deployed?\n"; \
		exit 1; \
	fi; \
	yc compute instance get-serial-port-output $$MASTER_ID

export-yc: ## Export Yandex Cloud credentials: eval $(make export-yc)
	@echo "export YC_TOKEN=$$(yc iam create-token)"
	@echo "export YC_CLOUD_ID=$$(yc config get cloud-id)"
	@echo "export YC_FOLDER_ID=$$(yc config get folder-id)"

export-prefix: ## Export TF_VAR_prefix (from tfvars or USER): eval $(make export-prefix)
	@PREFIX=""; \
	if [ -f terraform.tfvars ]; then \
		PREFIX=$$(grep -E '^prefix[[:space:]]*=' terraform.tfvars | sed -E 's/.*=[[:space:]]*"([^"]+)".*/\1/' | head -1); \
	fi; \
	if [ -z "$$PREFIX" ]; then \
		PREFIX=$${USER}; \
		echo "# Using username as prefix (not found in terraform.tfvars)" >&2; \
	fi; \
	echo "export TF_VAR_prefix=$$PREFIX"

export: ## Export all environment variables (YC + prefix): eval $(make export)
	@$(MAKE) -s export-prefix
	@$(MAKE) -s export-yc

# --- Config ---

show-vars: ## Show current variable values
	@printf "[INFO] Current variables:\n"
	@if [ -f terraform.tfvars ]; then \
		PREFIX=$$(grep -E '^prefix[[:space:]]*=' terraform.tfvars | sed -E 's/.*=[[:space:]]*"([^"]+)".*/\1/' | head -1); \
		if [ -n "$$PREFIX" ]; then \
			echo "  Current prefix: $$PREFIX"; \
		else \
			echo "  Current prefix: (not set in terraform.tfvars)"; \
		fi; \
		echo ""; \
		printf "[INFO] Contents of terraform.tfvars:\n"; \
		cat terraform.tfvars; \
	else \
		printf "[WARN] File terraform.tfvars not found\n"; \
	fi

git-hooks: ## Install Git pre-commit hooks
	@printf "[INFO] Installing Git hooks...\n"
	@if [ -f scripts/install-hooks.sh ]; then \
		chmod +x scripts/install-hooks.sh; \
		./scripts/install-hooks.sh; \
		printf "[INFO] Git hooks installed\n"; \
	else \
		printf "[ERROR] File scripts/install-hooks.sh not found\n"; \
		exit 1; \
	fi

import-state: ## Import existing infrastructure to Terraform state
	@printf "[INFO] Importing existing infrastructure...\n"
	@if [ -f scripts/import-state.sh ]; then \
		chmod +x scripts/import-state.sh; \
		./scripts/import-state.sh; \
	else \
		printf "[ERROR] File scripts/import-state.sh not found\n"; \
		exit 1; \
	fi

