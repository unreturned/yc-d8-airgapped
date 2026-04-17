#!/usr/bin/env bash
# Get Harbor certificate from registry and add to trusted CAs
# This is a Terraform template - variables will be substituted (disable=SC2154)

set -euo pipefail

# shellcheck disable=SC2154
REGISTRY_HOST="${registry_fqdn}"
MAX_ATTEMPTS=120

echo "Waiting for Harbor certificate from $REGISTRY_HOST..."

for i in $(seq 1 "$MAX_ATTEMPTS"); do
    if echo -n | timeout 10 openssl s_client -connect "$REGISTRY_HOST":443 -servername "$REGISTRY_HOST" 2>/dev/null | \
        openssl x509 -outform PEM > /tmp/harbor.crt 2>/dev/null; then

        if [ -s /tmp/harbor.crt ]; then
            if openssl x509 -in /tmp/harbor.crt -noout -subject 2>/dev/null; then
                mv /tmp/harbor.crt /usr/local/share/ca-certificates/registry-harbor-ca.crt
                chmod 644 /usr/local/share/ca-certificates/registry-harbor-ca.crt
                update-ca-certificates
                echo "Harbor certificate successfully added to trusted CAs"
                echo "Certificate path: /usr/local/share/ca-certificates/registry-harbor-ca.crt"
                echo "Registry hostname: $REGISTRY_HOST"
                exit 0
            fi
        fi
    fi

    echo "Attempt $i/$MAX_ATTEMPTS: Waiting for Harbor to be ready..."
    sleep 10
done

echo "ERROR: Failed to get Harbor certificate after $MAX_ATTEMPTS attempts"
echo "Harbor may not be running yet or network connectivity issues"
exit 1
