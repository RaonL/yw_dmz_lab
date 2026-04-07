#!/bin/bash
set -euo pipefail

BASE_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/../../.." && pwd)"
SCRIPTS_DIR="${BASE_DIR}/scripts"
CONFIG_DIR="${BASE_DIR}/config"

source "${SCRIPTS_DIR}/lib/logging.sh"
source "${CONFIG_DIR}/variables.sh"

log_info "Configuring DMZ IDS"

DMZ_IDS_CONTAINER="clab-${LAB_NAME}-DMZ_IDS"

# ✅ 1. 컨테이너 실행 대기
log_info "Waiting for DMZ_IDS container to be running..."
WAIT=0
while [ "$WAIT" -lt 60 ]; do
    STATUS=$(sudo docker inspect "${DMZ_IDS_CONTAINER}" --format='{{.State.Status}}' 2>/dev/null || true)
    if [ "$STATUS" = "running" ]; then
        log_ok "Container is running"
        break
    fi
    WAIT=$((WAIT + 1))
    sleep 1
done
if [ "$WAIT" -ge 60 ]; then
    log_error "Timeout waiting for container"
    exit 1
fi

# ✅ 2. 인터페이스 대기
log_info "Waiting for eth1 & eth2 interfaces..."
WAIT=0
while [ "$WAIT" -lt 30 ]; do
    if sudo docker exec "${DMZ_IDS_CONTAINER}" ip link show eth1 &>/dev/null && \
       sudo docker exec "${DMZ_IDS_CONTAINER}" ip link show eth2 &>/dev/null; then
        log_ok "Interfaces eth1 & eth2 ready"
        break
    fi
    WAIT=$((WAIT + 1))
    sleep 1
done

# ✅ 3. Suricata 설 생성 (Read-only 마운트 대응)
log_info "Generating Suricata configuration..."
sudo docker exec -i "${DMZ_IDS_CONTAINER}" bash << 'INNER_CONF'
mkdir -p /etc/suricata /var/log/suricata

cat > /etc/suricata/suricata.yaml << 'YAML'
%YAML 1.1
---
af-packet:
  - interface: eth1
    cluster-id: 98
    cluster-type: cluster_flow
    defrag: yes
  - interface: eth2
    cluster-id: 99
    cluster-type: cluster_flow
    defrag: yes

outputs:
  - eve-log:
      enabled: yes
      filetype: regular
      filename: /var/log/suricata/eve.json
      types:
        - alert:
            payload: yes
            payload-printable: yes

default-log-dir: /var/log/suricata/
rule-files:
  - suricata.rules
default-rule-path: /var/lib/suricata/rules

logging:
  default-log-level: notice
YAML

echo "[OK] Suricata config written (rules dir managed by host :ro mount)"
INNER_CONF

# ✅ 4. Suricata 백그라운드 
log_info "Starting Suricata..."
sudo docker exec -d "${DMZ_IDS_CONTAINER}" bash -c '
sleep 3
suricata -c /etc/suricata/suricata.yaml -i eth1 --runmode=autofp -D 2>/var/log/suricata/startup.log || true
'

sleep 2
if sudo docker exec "${DMZ_IDS_CONTAINER}" pgrep -x suricata &>/dev/null; then
    log_ok "Suricata started successfully"
else
    log_warn "Suricata may not be running. Check: sudo docker logs ${DMZ_IDS_CONTAINER}"
fi

log_ok "DMZ IDS configured"
