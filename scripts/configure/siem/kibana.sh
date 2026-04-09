#!/bin/bash
set -euo pipefail

# Get script directory and set up paths
BASE_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/../../.." && pwd)"
SCRIPTS_DIR="${BASE_DIR}/scripts"
CONFIG_DIR="${BASE_DIR}/config"

# Load dependencies
source "${SCRIPTS_DIR}/lib/logging.sh"
source "${CONFIG_DIR}/variables.sh"

log_info "Configuring Siem Kibana"

SIEM_KIBANA_CONTAINER="clab-${LAB_NAME}-kibana"

log_info "Configuring Kibana network via nsenter..."

KIBANA_PID=$(sudo docker inspect -f '{{.State.Pid}}' ${SIEM_KIBANA_CONTAINER})
sudo nsenter -t $KIBANA_PID -n ip addr add ${SIEM_KIBANA_ETH1_IP} dev eth1 || true
sudo nsenter -t $KIBANA_PID -n ip addr add ${SIEM_KIBANA_ETH2_IP} dev eth2 || true
sudo nsenter -t $KIBANA_PID -n ip link set eth1 up
sudo nsenter -t $KIBANA_PID -n ip link set eth2 up
sudo nsenter -t $KIBANA_PID -n ip route replace default via ${SIEM_FW_ETH5_IP%/*} dev eth2 || true
sudo nsenter -t $KIBANA_PID -n ip route add ${SIEM_ELASTIC_ETH1_IP} via ${SIEM_ELASTIC_ETH2_IP%/*} dev eth1 || true

echo "=== Kibana Network Configuration ==="
sudo nsenter -t $KIBANA_PID -n ip addr show | grep "inet " || true
sudo nsenter -t $KIBANA_PID -n ip route show || true

# Kibana 컨테이너 내부 localhost:5601로 헬스체크 (네트워크 우회, 가장 확실)
log_info "Waiting for Kibana to become available (HTTP health check)..."
KIBANA_READY=false
for i in $(seq 1 90); do
  if sudo docker exec "${SIEM_KIBANA_CONTAINER}" \
      curl -sf --max-time 3 "http://localhost:5601/api/status" >/dev/null 2>&1; then
    log_ok "Kibana is available (attempt $i)"
    KIBANA_READY=true
    break
  fi
  if [ $i -eq 90 ]; then
    log_warn "Kibana did not respond after 180s, attempting Data View creation anyway..."
  fi
  sleep 2
done

log_ok "Kibana configured"

# FIX: siem_pc(Alpine) wget 대신 Kibana 컨테이너 내부 curl 사용
# Alpine BusyBox wget은 --header, --post-data 미지원 → 무한 대기 버그
log_info "Creating Kibana Data Views..."

create_data_view() {
  local name="$1"
  local payload="$2"
  local result
  result=$(sudo docker exec "${SIEM_KIBANA_CONTAINER}" \
    curl -sf --max-time 10 \
    -X POST "http://localhost:5601/api/data_views/data_view" \
    -H "kbn-xsrf: true" \
    -H "Content-Type: application/json" \
    -d "${payload}" 2>&1 || true)

  if echo "$result" | grep -q '"id"'; then
    log_ok "  Data View created: ${name}"
  else
    log_warn "  Data View '${name}' skipped (already exists or error)"
  fi
}

create_data_view "firewall_logs" \
  '{"data_view":{"title":"filebeat-*","name":"firewall_logs","timeFieldName":"@timestamp"}}'

create_data_view "waf_logs" \
  '{"data_view":{"title":"waf-*","name":"waf_logs","timeFieldName":"@timestamp"}}'

create_data_view "ids_alerts" \
  '{"data_view":{"title":"ids-*","name":"ids_alerts","timeFieldName":"@timestamp"}}'

log_ok "Kibana Data Views created"
