#!/bin/bash
set -euo pipefail

BASE_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/../../.." && pwd)"
SCRIPTS_DIR="${BASE_DIR}/scripts"
CONFIG_DIR="${BASE_DIR}/config"

source "${SCRIPTS_DIR}/lib/logging.sh"
source "${CONFIG_DIR}/variables.sh"

log_info "Configuring DMZ IDS"

DMZ_IDS_CONTAINER="clab-${LAB_NAME}-DMZ_IDS"

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

# -----------------------------------------------------------------------------
# DMZ_IDS eth2 — SIEM link. Needed for Filebeat -> Logstash:5045
# -----------------------------------------------------------------------------
log_info "Configuring DMZ_IDS eth2 (SIEM link) + route..."
sudo docker exec -i \
    -e DMZ_IDS_ETH2_IP="${DMZ_IDS_ETH2_IP}" \
    -e SIEM_FW_ETH7_IP="${SIEM_FW_ETH7_IP}" \
    -e SIEM_SUBNET="${SIEM_SUBNET}" \
    "${DMZ_IDS_CONTAINER}" sh << 'EOF'
set -e

if ! command -v ip >/dev/null 2>&1; then
  if command -v apt-get >/dev/null 2>&1; then
    export DEBIAN_FRONTEND=noninteractive
    apt-get update -qq >/dev/null 2>&1 || true
    apt-get install -y --no-install-recommends iproute2 iputils-ping netcat-openbsd >/dev/null 2>&1 || true
  elif command -v apk >/dev/null 2>&1; then
    apk add --no-cache iproute2 iputils busybox-extras >/dev/null 2>&1 || true
  fi
fi

ip addr add "${DMZ_IDS_ETH2_IP}" dev eth2 2>/dev/null || true
ip link set eth2 up 2>/dev/null || true

# Route SIEM subnet via SIEM_FW eth7 gateway
ip route replace "${SIEM_SUBNET}" via "${SIEM_FW_ETH7_IP%/*}" dev eth2 2>/dev/null || true

echo "--- eth2 addr ---"
ip -4 addr show eth2 || true
echo "--- routes ---"
ip -4 route || true
EOF
log_ok "DMZ_IDS eth2 + route configured"

log_info "Generating Suricata configuration..."
sudo docker exec -i "${DMZ_IDS_CONTAINER}" bash << 'INNER_CONF'
mkdir -p /etc/suricata /var/log/suricata /etc/suricata/rules

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

touch /etc/suricata/rules/local.rules

echo "[OK] Suricata config written"
INNER_CONF

log_info "Validating Suricata config..."
sudo docker exec "${DMZ_IDS_CONTAINER}" suricata -T -c /etc/suricata/suricata.yaml 2>&1 | tail -5 || true

log_info "Starting Suricata..."
sudo docker exec "${DMZ_IDS_CONTAINER}" pkill -x suricata 2>/dev/null || true
sleep 2
sudo docker exec -d "${DMZ_IDS_CONTAINER}" bash -c '
  mkdir -p /var/log/suricata
  : > /var/log/suricata/eve.json
  suricata -c /etc/suricata/suricata.yaml -i eth1 --runmode=autofp -D \
    > /var/log/suricata/startup.log 2>&1
'

log_info "Waiting up to 20s for Suricata engine to come up..."
ENGINE_UP=0
for i in $(seq 1 20); do
    if sudo docker exec "${DMZ_IDS_CONTAINER}" \
         grep -q "Engine started" /var/log/suricata/suricata.log 2>/dev/null; then
        ENGINE_UP=1
        break
    fi
    sleep 1
done

if [ "$ENGINE_UP" -eq 1 ]; then
    log_ok "Suricata engine started"
else
    log_warn "Suricata engine not confirmed. Tail of suricata.log:"
    sudo docker exec "${DMZ_IDS_CONTAINER}" tail -n 20 /var/log/suricata/suricata.log 2>/dev/null || true
fi

# -----------------------------------------------------------------------------
# Filebeat — apt는 신뢰도 낮아서 tarball 직접 설치
# -----------------------------------------------------------------------------
log_info "Installing Filebeat via tarball (bypassing apt)..."
sudo docker exec -i \
    -e SIEM_LOGSTASH_ETH1_IP="${SIEM_LOGSTASH_ETH1_IP}" \
    "${DMZ_IDS_CONTAINER}" bash << 'FB_INSTALL'
set -e
LS_HOST="${SIEM_LOGSTASH_ETH1_IP%/*}"
FB_VER="9.2.1"
FB_DIR="/opt/filebeat-${FB_VER}-linux-x86_64"
FB_BIN="${FB_DIR}/filebeat"

if [ ! -x "${FB_BIN}" ]; then
    if ! command -v curl >/dev/null 2>&1; then
        if command -v apt-get >/dev/null 2>&1; then
            export DEBIAN_FRONTEND=noninteractive
            apt-get update -qq >/dev/null 2>&1 || true
            apt-get install -y --no-install-recommends curl ca-certificates >/dev/null 2>&1 || true
        fi
    fi
    mkdir -p /opt
    cd /opt
    if curl -fsSL -o filebeat.tar.gz \
         "https://artifacts.elastic.co/downloads/beats/filebeat/filebeat-${FB_VER}-linux-x86_64.tar.gz"; then
        tar xzf filebeat.tar.gz
        rm -f filebeat.tar.gz
        ln -sf "${FB_BIN}" /usr/local/bin/filebeat
        echo "[OK] Filebeat tarball installed: $(ls -la ${FB_BIN})"
    else
        echo "[ERROR] Failed to download Filebeat tarball"
        exit 0
    fi
fi

mkdir -p /etc/filebeat /var/lib/filebeat
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
if [ -x "${FB_BIN}" ] || command -v filebeat >/dev/null 2>&1; then
    FB_CMD="${FB_BIN}"
    [ -x "$FB_CMD" ] || FB_CMD="$(command -v filebeat)"
    nohup "$FB_CMD" -e -c /etc/filebeat/filebeat.yml \
      > /var/log/filebeat.log 2>&1 &
    sleep 2
    if pgrep -f "filebeat.*filebeat.yml" >/dev/null 2>&1; then
        echo "[OK] Filebeat started (shipping eve.json -> ${LS_HOST}:5045)"
    else
        echo "[WARN] Filebeat not running — tail /var/log/filebeat.log:"
        tail -n 20 /var/log/filebeat.log 2>/dev/null || true
    fi
else
    echo "[WARN] Filebeat binary still missing — IDS logs will not ship"
fi
FB_INSTALL

log_ok "DMZ IDS configured"
