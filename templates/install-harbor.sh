#!/usr/bin/env bash
# Installs Harbor on registry host
# This is a Terraform template - variables will be substituted (disable=SC2154)

set -euo pipefail

# shellcheck disable=SC2154
HARBOR_VERSION="${harbor_version}"
HARBOR_INSTALL_DIR="/opt/harbor"
HARBOR_DATA_DIR="/var/lib/harbor"
HARBOR_CERTS_DIR="/opt/harbor/certs"
# shellcheck disable=SC2154
HARBOR_HOSTNAME="${harbor_hostname}"
# shellcheck disable=SC2154
HARBOR_ADMIN_PASSWORD="${harbor_admin_password}"

log() {
    echo "[$(date +'%Y-%m-%d %H:%M:%S')] $*"
}

log "Starting Harbor installation..."

log "Creating directories..."
mkdir -p "$HARBOR_INSTALL_DIR"
mkdir -p "$HARBOR_DATA_DIR"
mkdir -p "$HARBOR_CERTS_DIR"

log "Downloading Harbor v$HARBOR_VERSION..."
cd /tmp
curl -L "https://github.com/goharbor/harbor/releases/download/v$HARBOR_VERSION/harbor-offline-installer-v$HARBOR_VERSION.tgz" -o harbor.tgz

log "Extracting Harbor..."
tar xzf harbor.tgz -C "$HARBOR_INSTALL_DIR" --strip-components=1
rm -f harbor.tgz

log "Generating self-signed certificate..."
# Extract short hostname from FQDN (e.g., kovalkov-registry from kovalkov-registry.ru-central1.internal)
HARBOR_SHORT_HOSTNAME=$(echo "$HARBOR_HOSTNAME" | cut -d'.' -f1)
# Get internal IP address
HARBOR_IP=$(hostname -I | awk '{print $1}')

log "Certificate will include:"
log "  FQDN: $HARBOR_HOSTNAME"
log "  Short hostname: $HARBOR_SHORT_HOSTNAME"
log "  IP: $HARBOR_IP"

# Generate self-signed certificate with SAN (Subject Alternative Names)
openssl req -x509 -newkey rsa:4096 -keyout "$HARBOR_CERTS_DIR/harbor.key" -out "$HARBOR_CERTS_DIR/harbor.crt" \
    -sha256 -days 3650 -nodes \
    -subj "/C=RU/ST=Moscow/L=Moscow/O=Yandex Cloud/OU=Harbor/CN=$HARBOR_HOSTNAME" \
    -addext "subjectAltName=DNS:$HARBOR_HOSTNAME,DNS:$HARBOR_SHORT_HOSTNAME,DNS:localhost,IP:$HARBOR_IP,IP:127.0.0.1"

log "Certificate generated successfully"

log "Creating Harbor configuration..."
cd "$HARBOR_INSTALL_DIR"

# Copy configuration template
cp harbor.yml.tmpl harbor.yml

# Configure main parameters
sed -i "s/^hostname: .*/hostname: $HARBOR_HOSTNAME/" harbor.yml
sed -i "s/^harbor_admin_password: .*/harbor_admin_password: $HARBOR_ADMIN_PASSWORD/" harbor.yml
sed -i "s|^data_volume: .*|data_volume: $HARBOR_DATA_DIR|" harbor.yml

# Configure HTTPS section
log "Configuring HTTPS..."
# Set certificate paths (https section is already uncommented in harbor.yml.tmpl)
sed -i "s|certificate: /your/certificate/path|certificate: $HARBOR_CERTS_DIR/harbor.crt|" harbor.yml
sed -i "s|private_key: /your/private/key/path|private_key: $HARBOR_CERTS_DIR/harbor.key|" harbor.yml

# Fill existing proxy section in harbor.yml
log "Configuring proxy settings..."
# shellcheck disable=SC2154
sed -i "s|^  http_proxy:.*|  http_proxy: ${proxy_url}|" harbor.yml
# shellcheck disable=SC2154
sed -i "s|^  https_proxy:.*|  https_proxy: ${proxy_url}|" harbor.yml
# shellcheck disable=SC2154
sed -i "s|^  no_proxy:.*|  no_proxy: ${no_proxy}|" harbor.yml

log "Proxy configuration applied:"
log "  HTTP_PROXY: ${proxy_url}"
log "  HTTPS_PROXY: ${proxy_url}"
log "  NO_PROXY: ${no_proxy}"

# Run installation
log "Running Harbor installer..."
./install.sh

log "Harbor installation completed!"
log "Access Harbor at:"
log "  HTTPS: https://$HARBOR_HOSTNAME"
log "  HTTP:  http://$HARBOR_HOSTNAME"
log ""
log "Default credentials: admin / $HARBOR_ADMIN_PASSWORD"
log ""
log "Certificate details:"
log "  Certificate: $HARBOR_CERTS_DIR/harbor.crt"
log "  Private key: $HARBOR_CERTS_DIR/harbor.key"
log "  SANs: $HARBOR_HOSTNAME, $HARBOR_SHORT_HOSTNAME, $HARBOR_IP"
