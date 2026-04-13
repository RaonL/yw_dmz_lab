#!/bin/bash
set -euo pipefail

# Get script directory and set up paths
BASE_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/../../.." && pwd)"
SCRIPTS_DIR="${BASE_DIR}/scripts"
CONFIG_DIR="${BASE_DIR}/config"

# Load dependencies
source "${SCRIPTS_DIR}/lib/logging.sh"
source "${CONFIG_DIR}/variables.sh"

log_info "Configuring Attacker node"

ATTACKER_CONTAINER="clab-${LAB_NAME}-Attacker"

sudo docker exec -i \
    -e INTERNET_ATTACKER_ETH1_IP="${INTERNET_ATTACKER_ETH1_IP}" \
    -e ROUTER_INTERNET_ETH1_IP="${ROUTER_INTERNET_ETH1_IP}" \
    -e SUBNET_INTERNET="${SUBNET_INTERNET}" \
    "${ATTACKER_CONTAINER}" sh << 'EOF_INNER'
set -e

# Tooling (best effort)
if command -v apt >/dev/null 2>&1; then
  apt update >/dev/null 2>&1 || true
  apt install -y iproute2 iputils-ping curl >/dev/null 2>&1 || true
fi

ip addr add "${INTERNET_ATTACKER_ETH1_IP}" dev eth1 2>/dev/null || true
ip link set eth1 up

# Default route to Internet router
ip route replace default via "${ROUTER_INTERNET_ETH1_IP%/*}" dev eth1
ip route replace "${SUBNET_INTERNET}" dev eth1
EOF_INNER

log_ok "attacker configured"
