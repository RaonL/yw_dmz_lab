#!/bin/bash

set -euo pipefail

BASE_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
export SCRIPTS_DIR="${BASE_DIR}/scripts"
export CONFIG_DIR="${BASE_DIR}/config"

source "${SCRIPTS_DIR}/lib/logging.sh"
source "${CONFIG_DIR}/variables.sh"

usage() {
cat << EOF
Usage: $0 [OPTIONS]

DEPLOYMENT:
 --full Full deployment (default)
 --topology-only Deploy topology only
 --skip-cleanup Skip cleanup phase

CLEANUP:
 --destroy Stop and remove containers
 --purge Destroy + remove Docker images

 --help, -h Show this help
EOF
exit 0
}

TOPOLOGY_ONLY=false; SKIP_CLEANUP=false; FULL_DEPLOY=true
DESTROY_MODE=false; PURGE_MODE=false

while [[ $# -gt 0 ]]; do
 case $1 in
 --topology-only) TOPOLOGY_ONLY=true; FULL_DEPLOY=false; shift ;;
 --full) FULL_DEPLOY=true; shift ;;
 --skip-cleanup) SKIP_CLEANUP=true; shift ;;
 --destroy) DESTROY_MODE=true; shift ;;
 --purge) PURGE_MODE=true; shift ;;
 --help|-h) usage ;;
 *) log_error "Unknown: $1"; usage ;;
 esac
done

# === Destroy/Purge ===
if [ "$DESTROY_MODE" = true ] || [ "$PURGE_MODE" = true ]; then
 log_section "Destroying yw_dmz_lab"
 sudo containerlab destroy --topo topology/DMZ.yml --cleanup 2>/dev/null || true
 docker rm -f $(docker ps -aq --filter "name=clab-${LAB_NAME}") 2>/dev/null || true
 docker network prune -f 2>/dev/null || true
 if [ "$PURGE_MODE" = true ]; then
 log_info "Removing Docker images..."
 for img_var in "${IMAGE_VAR_NAMES[@]}"; do
 docker rmi "${!img_var}" 2>/dev/null || true
 done
 fi
 log_ok "Cleanup complete"
 exit 0
fi

# === Main Deployment ===
log_section "Starting yw_dmz_lab Deployment"

log_info "Pinned container images:"
for img_var in "${IMAGE_VAR_NAMES[@]}"; do
 log_info " ${img_var}=${!img_var}"
done

if [ "$SKIP_CLEANUP" = false ]; then
 log_info "Cleaning up previous environment..."
 sudo containerlab destroy --topo topology/DMZ.yml --cleanup 2>/dev/null || true
 docker rm -f $(docker ps -aq --filter "name=clab-${LAB_NAME}") 2>/dev/null || true
 docker network prune -f 2>/dev/null || true
fi

log_info "Setting vm.max_map_count..."
sudo sysctl -w vm.max_map_count=262144 2>/dev/null || true

log_info "Generating topology..."
bash topology/topology-generator.sh

log_info "Deploying topology..."
cd topology && sudo containerlab deploy --topo DMZ.yml && cd ..

log_info "Verifying containers..."
RUNNING=$(docker ps --filter "name=clab-${LAB_NAME}" --format "{{.Names}}" | wc -l)
log_info "Running containers: $RUNNING"
EXPECTED_CONTAINERS=14
if [ "$RUNNING" -ne "$EXPECTED_CONTAINERS" ]; then
 log_error "Container count check failed (${RUNNING}/${EXPECTED_CONTAINERS}). Deployment may be broken. Aborting."
 exit 1
fi

NON_RUNNING=$(docker ps -a \
 --filter "name=^clab-${LAB_NAME}-" \
 --filter "status=created" \
 --filter "status=restarting" \
 --filter "status=exited" \
 --filter "status=dead" \
 --format "{{.Names}} -> {{.Status}}")
if [ -n "$NON_RUNNING" ]; then
 log_error "Detected non-running lab containers:"
 while IFS= read -r line; do
   [ -n "$line" ] && log_error " ${line}"
 done <<< "$NON_RUNNING"
 exit 1
fi

if [ "$TOPOLOGY_ONLY" = true ]; then
 log_ok "Topology-only deployment complete!"
 exit 0
fi

# === Configuration Phase ===
log_section "Configuration Phase"

# FIX: Elasticsearch 대기 로직 강화 - yellow/green 상태 확인 + 타임아웃 60회(300초)
log_info "Waiting for Elasticsearch (yellow/green status)..."
ES_READY=false
for i in $(seq 1 60); do
 STATUS=$(sudo docker exec clab-${LAB_NAME}-elasticsearch \
   curl -s http://localhost:9200/_cluster/health 2>/dev/null \
   | grep -o '"status":"[^"]*"' | cut -d'"' -f4 || true)
 if [[ "$STATUS" == "green" || "$STATUS" == "yellow" ]]; then
   log_ok "Elasticsearch ready (status: $STATUS)"
   ES_READY=true
   break
 fi
 log_info "  Attempt $i/60 - status: '${STATUS:-not ready}', waiting 5s..."
 sleep 5
done
if [ "$ES_READY" = false ]; then
 log_warn "Elasticsearch did not reach healthy status after 300s, continuing anyway..."
fi

log_info "Configuring External Firewall..."
bash scripts/configure/firewalls/external-fw.sh 2>/dev/null || log_warn "external-fw.sh failed"

log_info "Configuring SIEM Firewall..."
bash scripts/configure/firewalls/siem-fw.sh 2>/dev/null || log_warn "siem-fw.sh failed"

log_info "Configuring DMZ IDS..."
bash scripts/configure/ids/ids-dmz.sh 2>/dev/null || log_warn "ids-dmz.sh failed"

log_info "Configuring network..."
bash scripts/configure/network/router-edge.sh 2>/dev/null || log_warn "router-edge.sh failed"
bash scripts/configure/network/router-internet.sh 2>/dev/null || log_warn "router-internet.sh failed"

log_info "Configuring DMZ services..."
bash scripts/configure/dmz/database.sh 2>/dev/null || log_warn "database.sh failed"
bash scripts/configure/dmz/webserver.sh 2>/dev/null || log_warn "webserver.sh failed"
bash scripts/configure/dmz/proxy.sh 2>/dev/null || log_warn "proxy.sh failed"

log_info "Configuring SIEM stack..."
bash scripts/configure/siem/logstash.sh
bash scripts/configure/siem/elasticsearch.sh 2>/dev/null || log_warn "elasticsearch.sh failed"
bash scripts/configure/siem/kibana.sh 2>/dev/null || log_warn "kibana.sh failed"

# === Post-deploy ===
log_info "Starting Filebeat..."
sudo docker exec clab-${LAB_NAME}-External_FW bash -c '
 set -e
 mkdir -p /var/lib/filebeat /var/log/filebeat
 if pgrep -x filebeat >/dev/null 2>&1; then
   echo "filebeat already running"
   exit 0
 fi
 FB_BIN="$(command -v filebeat || true)"
 if [ -z "$FB_BIN" ] && [ -x /usr/share/filebeat/bin/filebeat ]; then
   FB_BIN=/usr/share/filebeat/bin/filebeat
 fi
 if [ -z "$FB_BIN" ]; then
   echo "filebeat binary not found"
   exit 1
 fi
 nohup "$FB_BIN" -e -c /etc/filebeat/filebeat.yml \
   --path.data /var/lib/filebeat \
   --path.logs /var/log/filebeat > /var/log/filebeat/bootstrap.log 2>&1 &
' 2>/dev/null || log_warn "Filebeat start failed"

log_info "Starting nginx in WAF..."
sudo docker exec clab-${LAB_NAME}-Proxy_WAF sh -c 'nginx 2>/dev/null' || true

log_info "Adding SIEM_FW forwarding rules..."
sudo docker exec clab-${LAB_NAME}-SIEM_FW bash -c '
 iptables -I FORWARD 1 -p tcp --dport 5044 -j ACCEPT
 iptables -I FORWARD 2 -p tcp --dport 5045 -j ACCEPT
 iptables -I FORWARD 3 -p icmp -j ACCEPT
 iptables -I FORWARD 4 -m state --state ESTABLISHED,RELATED -j ACCEPT
' 2>/dev/null || true

# FIX: kibana.sh에서 이미 Data View 생성하므로 중복 제거
# (main.sh의 sleep 30 + curl 블록 삭제)

log_section "yw_dmz_lab Deployment Complete!"
log_ok "Services:"
log_info " Kibana: http://localhost:5601"
log_info " Elasticsearch: http://localhost:9200"
log_info " Web App (WAF): http://localhost:8080"
log_info " Destroy: sudo bash main.sh --destroy"
