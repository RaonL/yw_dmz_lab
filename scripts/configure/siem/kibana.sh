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



log_info "Waiting for Kibana to become available..."
for _ in {1..60}; do
	if sudo docker logs "${SIEM_KIBANA_CONTAINER}" 2>&1 | tail -n 200 | grep -q "Kibana is now available"; then
		log_ok "Kibana is available"
		break
	fi
	sleep 2
done

log_ok "Kibana configured"
# Create Kibana Data Views
log_info "Creating Kibana Data Views..."
KIBANA_URL="http://${SIEM_KIBANA_ETH2_IP%/*}:5601"
SIEM_PC_CONTAINER="clab-${LAB_NAME}-siem_pc"

for i in 1 2 3 4 5; do
  if sudo docker exec ${SIEM_PC_CONTAINER} curl -sf "${KIBANA_URL}/api/status" >/dev/null 2>&1; then
    break
  fi
  sleep 10
done

# firewall_logs
sudo docker exec ${SIEM_PC_CONTAINER} curl -sf -X POST "${KIBANA_URL}/api/data_views/data_view" \
  -H "kbn-xsrf: true" -H "Content-Type: application/json" \
  -d '{"data_view":{"title":"filebeat-*","name":"firewall_logs","timeFieldName":"@timestamp"}}' >/dev/null 2>&1 || true

# waf_logs  
sudo docker exec ${SIEM_PC_CONTAINER} curl -sf -X POST "${KIBANA_URL}/api/data_views/data_view" \
  -H "kbn-xsrf: true" -H "Content-Type: application/json" \
  -d '{"data_view":{"title":"waf-*","name":"waf_logs","timeFieldName":"@timestamp"}}' >/dev/null 2>&1 || true

# ids_alerts
sudo docker exec ${SIEM_PC_CONTAINER} curl -sf -X POST "${KIBANA_URL}/api/data_views/data_view" \
  -H "kbn-xsrf: true" -H "Content-Type: application/json" \
  -d '{"data_view":{"title":"ids-*","name":"ids_alerts","timeFieldName":"@timestamp"}}' >/dev/null 2>&1 || true

log_ok "Kibana Data Views created"
