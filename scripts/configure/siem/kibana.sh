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


# FIX: 로그 tail 파싱 대신 HTTP /api/status 엔드포인트로 Kibana 준비 상태 확인
# (tail -n 200은 로그가 200줄 넘으면 감지 실패)
log_info "Waiting for Kibana to become available (HTTP health check)..."
KIBANA_READY=false
for i in $(seq 1 90); do
  if sudo docker exec "${SIEM_KIBANA_CONTAINER}" \
      curl -sf "http://localhost:5601/api/status" >/dev/null 2>&1; then
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

# Create Kibana Data Views
log_info "Creating Kibana Data Views..."
KIBANA_URL="http://${SIEM_KIBANA_ETH2_IP%/*}:5601"
SIEM_PC_CONTAINER="clab-${LAB_NAME}-siem_pc"

# siem_pc에서 Kibana 접근 가능할 때까지 대기
for i in $(seq 1 10); do
 if sudo docker exec ${SIEM_PC_CONTAINER} \
     wget -qO- "${KIBANA_URL}/api/status" >/dev/null 2>&1 || \
    sudo docker exec ${SIEM_PC_CONTAINER} \
     wget -qO- "${KIBANA_URL}/api/status" 2>/dev/null | grep -q "version"; then
   break
 fi
 sleep 5
done

# FIX: curl 응답 확인 추가 (실패시 경고 출력)
create_data_view() {
  local name="$1"
  local payload="$2"
  local result
  result=$(sudo docker exec ${SIEM_PC_CONTAINER} \
    wget -qO- --header="kbn-xsrf: true" \
    --header="Content-Type: application/json" \
    --post-data="${payload}" \
    "${KIBANA_URL}/api/data_views/data_view" 2>&1 || true)
  if echo "$result" | grep -q '"id"'; then
    log_ok "  Data View created: ${name}"
  else
    log_warn "  Data View '${name}' may have failed (already exists or Kibana not ready)"
  fi
}

create_data_view "firewall_logs" \
  '{"data_view":{"title":"filebeat-*","name":"firewall_logs","timeFieldName":"@timestamp"}}'

create_data_view "waf_logs" \
  '{"data_view":{"title":"waf-*","name":"waf_logs","timeFieldName":"@timestamp"}}'

create_data_view "ids_alerts" \
  '{"data_view":{"title":"ids-*","name":"ids_alerts","timeFieldName":"@timestamp"}}'

log_ok "Kibana Data Views created"
