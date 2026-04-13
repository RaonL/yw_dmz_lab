#!/bin/bash
set -euo pipefail

BASE_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/../../.." && pwd)"
SCRIPTS_DIR="${BASE_DIR}/scripts"
CONFIG_DIR="${BASE_DIR}/config"

source "${SCRIPTS_DIR}/lib/logging.sh"
source "${CONFIG_DIR}/variables.sh"

log_info "Configuring DMZ Switch (bridge mode)"

DMZ_SWITCH_CONTAINER="clab-${LAB_NAME}-DMZ_Switch"

sudo docker exec -i "${DMZ_SWITCH_CONTAINER}" sh << 'EOF'
set -e

# Create bridge combining all DMZ-facing interfaces
ip link add br0 type bridge 2>/dev/null || true
ip link set br0 up

for iface in eth1 eth2 eth3; do
    if ip link show "$iface" >/dev/null 2>&1; then
        ip link set "$iface" master br0 2>/dev/null || true
        ip link set "$iface" up
    fi
done

echo 1 > /proc/sys/net/ipv4/ip_forward 2>/dev/null || true

echo "[OK] DMZ Switch bridge configured (eth1+eth2+eth3 -> br0)"
EOF

log_ok "DMZ Switch configured"
