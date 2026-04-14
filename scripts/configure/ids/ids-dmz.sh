#!/bin/bash
set -euo pipefail

BASE_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/../../.." && pwd)"
SCRIPTS_DIR="${BASE_DIR}/scripts"
CONFIG_DIR="${BASE_DIR}/config"

source "${SCRIPTS_DIR}/lib/logging.sh"
source "${CONFIG_DIR}/variables.sh"

log_info "Configuring DMZ IDS"

DMZ_IDS_CONTAINER="clab-${LAB_NAME}-DMZ_IDS"

# 1. 컨테이너 실행 대기
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

# 2. 인터페이스 대기
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

# 3. Suricata 설정 생성 — vars 섹션 포함이 핵심
log_info "Generating Suricata configuration..."
sudo docker exec -i "${DMZ_IDS_CONTAINER}" bash << 'INNER_CONF'
mkdir -p /etc/suricata /var/log/suricata

cat > /etc/suricata/suricata.yaml << 'YAML'
%YAML 1.1
---
vars:
  address-groups:
    HOME_NET: "[10.0.2.0/24,10.0.3.0/24]"
    EXTERNAL_NET: "!$HOME_NET"
    HTTP_SERVERS: "$HOME_NET"
    SQL_SERVERS: "$HOME_NET"
    DNS_SERVERS: "$HOME_NET"
    TELNET_SERVERS: "$HOME_NET"
    AIM_SERVERS: "$EXTERNAL_NET"
    DC_SERVERS: "$HOME_NET"
    DNP3_SERVER: "$HOME_NET"
    DNP3_CLIENT: "$HOME_NET"
    MODBUS_CLIENT: "$HOME_NET"
    MODBUS_SERVER: "$HOME_NET"
    ENIP_CLIENT: "$HOME_NET"
    ENIP_SERVER: "$HOME_NET"
  port-groups:
    HTTP_PORTS: "[80,8080,8443,5000]"
    SHELLCODE_PORTS: "!80"
    ORACLE_PORTS: 1521
    SSH_PORTS: 22
    DNP3_PORTS: 20000
    MODBUS_PORTS: 502
    FILE_DATA_PORTS: "[$HTTP_PORTS,110,143]"
    FTP_PORTS: 21
    GENEVE_PORTS: 6081
    VXLAN_PORTS: 4789
    TEREDO_PORTS: 3544

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
        - http
        - dns
        - tls
        - flow

default-log-dir: /var/log/suricata/
rule-files:
  - local.rules
default-rule-path: /etc/suricata/rules

app-layer:
  protocols:
    http:
      enabled: yes
    tls:
      enabled: yes
    dns:
      tcp:
        enabled: yes
      udp:
        enabled: yes

logging:
  default-log-level: notice
  outputs:
    - file:
        enabled: yes
        filename: /var/log/suricata/suricata.log
YAML

echo "[OK] Suricata config written"
INNER_CONF

# 4. Suricata 구문 검증 후 실행
log_info "Validating Suricata config..."
if sudo docker exec "${DMZ_IDS_CONTAINER}" suricata -T -c /etc/suricata/suricata.yaml 2>&1 | tail -10; then
    log_ok "Suricata config OK"
else
    log_warn "Suricata config validation had warnings (see above)"
fi

log_info "Starting Suricata..."
sudo docker exec "${DMZ_IDS_CONTAINER}" pkill -x suricata 2>/dev/null || true
sleep 1
sudo docker exec -d "${DMZ_IDS_CONTAINER}" bash -c '
  suricata -c /etc/suricata/suricata.yaml -i eth1 --runmode=autofp -D \
    > /var/log/suricata/startup.log 2>&1
'

sleep 5
if sudo docker exec "${DMZ_IDS_CONTAINER}" pgrep -x suricata &>/dev/null; then
    log_ok "Suricata started successfully"
else
    log_error "Suricata failed to start. startup.log:"
    sudo docker exec "${DMZ_IDS_CONTAINER}" tail -n 30 /var/log/suricata/startup.log 2>/dev/null || true
    log_error "suricata.log:"
    sudo docker exec "${DMZ_IDS_CONTAINER}" tail -n 30 /var/log/suricata/suricata.log 2>/dev/null || true
fi

# 5. Filebeat 설치 및 eve.json을 Logstash로 전송 (port 5045)
log_info "Installing & configuring Filebeat in DMZ_IDS..."
sudo docker exec -i \
    -e SIEM_LOGSTASH_ETH1_IP="${SIEM_LOGSTASH_ETH1_IP}" \
    "${DMZ_IDS_CONTAINER}" bash << 'FB_INSTALL'
set -e
if ! command -v filebeat >/dev/null 2>&1; then
    if command -v apt-get >/dev/null 2>&1; then
        export DEBIAN_FRONTEND=noninteractive
        apt-get update -qq >/dev/null 2>&1 || true
        apt-get install -y --no-install-recommends curl gnupg ca-certificates >/dev/null 2>&1 || true
        curl -fsSL https://artifacts.elastic.co/GPG-KEY-elasticsearch \
            | gpg --dearmor -o /usr/share/keyrings/elastic.gpg 2>/dev/null || true
        echo "deb [signed-by=/usr/share/keyrings/elastic.gpg] https://artifacts.elastic.co/packages/9.x/apt stable main" \
            > /etc/apt/sources.list.d/elastic-9.x.list
        apt-get update -qq >/dev/null 2>&1 || true
        apt-get install -y filebeat >/dev/null 2>&1 || true
    fi
fi

LS_HOST="${SIEM_LOGSTASH_ETH1_IP%/*}"

mkdir -p /etc/filebeat /var/lib/filebeat /var/log
cat > /etc/filebeat/filebeat.yml << FB_CONF
filebeat.inputs:
  - type: filestream
    id: suricata-eve
    enabled: true
    paths:
      - /var/log/suricata/eve.json
    parsers:
      - ndjson:
          target: ""
    fields:
      log_type: ids
    fields_under_root: true

output.logstash:
  hosts: ["${LS_HOST}:5045"]

path.data: /var/lib/filebeat
logging.level: info
logging.to_files: true
logging.files:
  path: /var/log
  name: filebeat
  keepfiles: 3
FB_CONF

pkill -x filebeat 2>/dev/null || true
sleep 1
FILEBEAT_BIN="$(command -v filebeat || true)"
if [ -z "${FILEBEAT_BIN}" ] && [ -x /usr/share/filebeat/bin/filebeat ]; then
    FILEBEAT_BIN="/usr/share/filebeat/bin/filebeat"
fi
if [ -n "${FILEBEAT_BIN}" ]; then
    nohup "${FILEBEAT_BIN}" -e -c /etc/filebeat/filebeat.yml \
      > /var/log/filebeat.log 2>&1 &
    sleep 2
    if pgrep -x filebeat >/dev/null 2>&1; then
        echo "[OK] Filebeat started (shipping eve.json → ${LS_HOST}:5045)"
    else
        echo "[WARN] Filebeat not running — see /var/log/filebeat.log"
    fi
else
    echo "[WARN] Filebeat binary not found"
fi
FB_INSTALL

log_ok "DMZ IDS configured"
