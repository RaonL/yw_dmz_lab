#!/bin/bash
set -euo pipefail

BASE_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/../../.." && pwd)"
SCRIPTS_DIR="${BASE_DIR}/scripts"
CONFIG_DIR="${BASE_DIR}/config"

source "${SCRIPTS_DIR}/lib/logging.sh"
source "${CONFIG_DIR}/variables.sh"

log_info "Configuring Attacker node"

ATTACKER_CONTAINER="clab-${LAB_NAME}-Attacker"

if ! sudo docker ps --format '{{.Names}}' | grep -qx "${ATTACKER_CONTAINER}"; then
  log_warn "Attacker container not running: ${ATTACKER_CONTAINER}"
  exit 0
fi

sudo docker exec -i \
  -e INTERNET_ATTACKER_ETH1_IP="${INTERNET_ATTACKER_ETH1_IP}" \
  -e ROUTER_INTERNET_ETH1_IP="${ROUTER_INTERNET_ETH1_IP}" \
  -e SUBNET_INTERNET="${SUBNET_INTERNET}" \
  "${ATTACKER_CONTAINER}" sh <<'EOF_INNER'
set -u

if command -v apt-get >/dev/null 2>&1; then
  apt-get update >/dev/null 2>&1 || true
  apt-get install -y iproute2 iputils-ping curl >/dev/null 2>&1 || true
elif command -v apk >/dev/null 2>&1; then
  apk add --no-cache iproute2 iputils curl >/dev/null 2>&1 || true
fi

for _ in 1 2 3 4 5; do
  ip link show eth1 >/dev/null 2>&1 && break
  sleep 1
done

ip addr add "${INTERNET_ATTACKER_ETH1_IP}" dev eth1 2>/dev/null || true
ip link set eth1 up || true
ip route replace default via "${ROUTER_INTERNET_ETH1_IP%/*}" dev eth1 || true
ip route replace "${SUBNET_INTERNET}" dev eth1 || true
EOF_INNER

log_ok "attacker configured"
