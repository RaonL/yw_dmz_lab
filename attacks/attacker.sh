#!/bin/bash
set -euo pipefail

BASE_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/../../.." && pwd)"
SCRIPTS_DIR="${BASE_DIR}/scripts"
CONFIG_DIR="${BASE_DIR}/config"

source "${SCRIPTS_DIR}/lib/logging.sh"
source "${CONFIG_DIR}/variables.sh"

log_info "Configuring Attacker network"

ATTACKER_CONTAINER="clab-${LAB_NAME}-Attacker"

sudo docker exec -i \
  -e INTERNET_ATTACKER_ETH1_IP="${INTERNET_ATTACKER_ETH1_IP}" \
  -e ROUTER_INTERNET_ETH1_IP="${ROUTER_INTERNET_ETH1_IP}" \
  -e EXT_FW_NAT_IP="${EXT_FW_NAT_IP}" \
  "${ATTACKER_CONTAINER}" bash <<'ATTACKER_EOF'
set -e

ip addr add "${INTERNET_ATTACKER_ETH1_IP}" dev eth1 2>/dev/null || true
ip link set eth1 up

# 기본 경로를 인터넷 라우터로 설정
ip route replace default via "${ROUTER_INTERNET_ETH1_IP%/*}" dev eth1

# NAT VIP로 가는 경로를 명시적으로 고정(디버깅/안정성)
ip route replace "${EXT_FW_NAT_IP}" via "${ROUTER_INTERNET_ETH1_IP%/*}" dev eth1

cat > /etc/resolv.conf <<EOF_DNS
nameserver 8.8.8.8
nameserver 1.1.1.1
EOF_DNS
ATTACKER_EOF

log_ok "Attacker network configured"
