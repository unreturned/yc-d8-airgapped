#!/usr/bin/env bash
# Deckhouse installation from registry host (runs via cloud-init, uses Docker + dhctl)

set -euo pipefail

exec 1> >(tee -a /var/log/deckhouse-bootstrap.log)
exec 2>&1

echo "=========================================="
echo "[$(date)] Deckhouse bootstrap started"
echo "=========================================="

# Logging (aligned with Makefile: [INFO], [WARN], [ERROR])
log_info()  { echo "[$(date)] [INFO] $*"; }
log_warn()  { echo "[$(date)] [WARN] $*"; }
log_error() { echo "[$(date)] [ERROR] $*"; }

log_info "Checking prerequisites..."

# Wait for Docker (30 * 5s)
wait_docker() {
    for _ in $(seq 1 30); do
        docker info >/dev/null 2>&1 && return 0
        log_info "Docker daemon: waiting..."
        sleep 5
    done
    return 1
}
wait_docker || { log_error "Docker daemon: failed after 30 attempts"; exit 1; }
log_info "Docker daemon: ok"

# Wait for Harbor (60 * 10s)
wait_harbor() {
    for _ in $(seq 1 60); do
        curl -k -s "https://${registry_fqdn}/api/v2.0/health" 2>/dev/null | grep -q healthy && return 0
        log_info "Harbor: waiting..."
        sleep 10
    done
    return 1
}
wait_harbor || { log_error "Harbor: failed after 60 attempts"; exit 1; }
log_info "Harbor: ok"

# Wait for Master SSH (60 * 10s)
wait_master_ssh() {
    for _ in $(seq 1 60); do
        ssh -i "${ssh_key}" -o StrictHostKeyChecking=no -o UserKnownHostsFile=/dev/null -o LogLevel=ERROR -o ConnectTimeout=5 "${ssh_username}@${master_ip}" "echo ok" >/dev/null 2>&1 && return 0
        log_info "Master SSH: waiting..."
        sleep 10
    done
    return 1
}
wait_master_ssh || { log_error "Master SSH: failed after 60 attempts"; exit 1; }
log_info "Master SSH: ok"

if ! curl -s --proxy "${proxy_url}" --max-time 10 http://google.com >/dev/null 2>&1; then
    log_error "Proxy not reachable: ${proxy_url}"
    exit 1
fi
log_info "Proxy: ok"

# Prepare environment
log_info "Preparing environment..."
mkdir -p /root/dhctl-tmp

[ ! -f /root/config.yml ] && { log_error "Config not found: /root/config.yml"; exit 1; }
[ ! -f "${ssh_key}" ]    && { log_error "SSH key not found: ${ssh_key}"; exit 1; }

# Deckhouse registry login (EE/SE)
if [ -n "${deckhouse_registry_docker_cfg}" ] && [ "${deckhouse_registry_docker_cfg}" != "eyJhdXRocyI6eyJyZWdpc3RyeS5kZWNraG91c2UucnUiOnt9fX0K" ]; then
    log_info "Logging in to Deckhouse registry: ${deckhouse_registry_host}"
    if ! DOCKER_CONFIG_JSON=$(echo "${deckhouse_registry_docker_cfg}" | base64 -d 2>/dev/null); then
        log_error "Failed to decode dockerconfigjson"
        exit 1
    fi
    REGISTRY_USER=$(echo "$DOCKER_CONFIG_JSON" | jq -r ".auths.\"${deckhouse_registry_host}\".username // empty" 2>/dev/null)
    REGISTRY_PASSWORD=$(echo "$DOCKER_CONFIG_JSON" | jq -r ".auths.\"${deckhouse_registry_host}\".password // empty" 2>/dev/null)
    if [ -n "$REGISTRY_USER" ] && [ -n "$REGISTRY_PASSWORD" ] && [ "$REGISTRY_USER" != "null" ] && [ "$REGISTRY_PASSWORD" != "null" ]; then
        if ! echo "$REGISTRY_PASSWORD" | HTTP_PROXY="${proxy_url}" HTTPS_PROXY="${proxy_url}" docker login "${deckhouse_registry_host}" -u "$REGISTRY_USER" --password-stdin; then
            log_error "Docker login to Deckhouse registry failed"
            exit 1
        fi
        log_info "Docker login: ok"
    else
        log_warn "No credentials in dockerconfigjson, continuing without login"
    fi
else
    log_info "No Deckhouse registry auth (CE)"
fi

# Pull Deckhouse image
log_info "Pulling Deckhouse image: ${deckhouse_image}"
if ! HTTP_PROXY="${proxy_url}" HTTPS_PROXY="${proxy_url}" docker pull "${deckhouse_image}"; then
    log_error "Failed to pull Deckhouse image"
    exit 1
fi

# dhctl bootstrap
log_info "Starting dhctl bootstrap (config=/root/config.yml, state=/root/dhctl-tmp, ~15-25 min)..."
log_info "Bastion=${bastion_ip} Master=${master_ip} Proxy=${proxy_url}"

docker run \
    --rm \
    --pull=always \
    --interactive \
    --network host \
    --volume /root/config.yml:/config.yml:ro \
    --volume "${ssh_key}:/tmp/.ssh/id_ed25519:ro" \
    --volume /root/dhctl-tmp:/tmp/dhctl \
    --env "HTTP_PROXY=${proxy_url}" \
    --env "HTTPS_PROXY=${proxy_url}" \
    --env "NO_PROXY=${no_proxy}" \
    --env "DHCTL_CLI_SSH_HOSTS=${master_ip}" \
    --env "DHCTL_CLI_SSH_USER=${ssh_username}" \
    "${deckhouse_image}" \
    dhctl bootstrap \
        --ssh-agent-private-keys=/tmp/.ssh/id_ed25519 \
        --config=/config.yml

EXIT_CODE=$?

echo ""
if [ "$EXIT_CODE" -eq 0 ]; then
    echo "[$(date)] Deckhouse cluster created successfully" > /dev/ttyS0
    log_info "Deckhouse bootstrap completed"
    touch /var/lib/deckhouse-bootstrap-complete
    date > /var/lib/deckhouse-bootstrap-timestamp
    log_info "State: /root/dhctl-tmp"
    log_info "Console: https://console.${sslip_domain} (admin@deckhouse.io / 7md03yxgzt)"
    log_info "Harbor: https://harbor.${sslip_domain} (admin / ${harbor_password})"
    log_info "Next: make ssh-master, sudo -i d8 k get nodes"
else
    log_error "Deckhouse bootstrap failed"
    echo "[$(date)] Deckhouse cluster was not created" > /dev/ttyS0
    log_info "Logs: /var/log/deckhouse-bootstrap.log"
    log_info "State: /root/dhctl-tmp"
fi
echo ""

exit "$EXIT_CODE"
