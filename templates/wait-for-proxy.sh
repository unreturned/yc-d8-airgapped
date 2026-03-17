#!/usr/bin/env bash
# Script to wait for proxy availability
# This is a Terraform template - variables will be substituted (disable=SC2154)

set -euo pipefail

# shellcheck disable=SC2154
echo "Waiting for proxy at ${proxy_host}:${proxy_port}..."
# shellcheck disable=SC2154
export http_proxy=http://${proxy_host}:${proxy_port}/
# shellcheck disable=SC2154
export https_proxy=http://${proxy_host}:${proxy_port}/

# shellcheck disable=SC2154
for i in $(seq 1 "${max_attempts}"); do
  # Check if proxy returns HTTP 200 (not 403 or connection refused)
  # shellcheck disable=SC2154
  HTTP_CODE=$(curl --proxy "http://${proxy_host}:${proxy_port}/" \
                   --connect-timeout 5 \
                   --max-time 10 \
                   --silent \
                   --output /dev/null \
                   --write-out '%%{http_code}' \
                   http://ifconfig.me/ 2>/dev/null || true)

  if [ "$HTTP_CODE" = "200" ]; then
    echo "Proxy is ready! (HTTP $HTTP_CODE)"
    exit 0
  elif [ -n "$HTTP_CODE" ] && [ "$HTTP_CODE" != "000" ]; then
    # shellcheck disable=SC2154
    echo "Attempt $i/${max_attempts}: Proxy responded with HTTP $HTTP_CODE (waiting for 200), retrying in ${interval} seconds..."
  else
    # shellcheck disable=SC2154
    echo "Attempt $i/${max_attempts}: Proxy not reachable, retrying in ${interval} seconds..."
  fi

  # shellcheck disable=SC2154
  sleep "${interval}"
done

# shellcheck disable=SC2154
echo "Proxy failed to become ready after ${timeout} seconds"
echo "Last HTTP code: $HTTP_CODE"
exit 1
