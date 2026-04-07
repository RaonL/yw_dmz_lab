#!/bin/bash
set -euo pipefail
BASE_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
source "${BASE_DIR}/scripts/lib/logging.sh"
source "${BASE_DIR}/config/variables.sh"

log_info "=== DMZ Lab Deployment Start ==="

# 1. Network
log_info "[1/7] Configuring Network..."
bash "${BASE_DIR}/scripts/configure/network/router-edge.sh"
bash "${BASE_DIR}/scripts/configure/network/router-internet.sh"

# 2. Firewalls
log_info "[2/7] Configuring Firewalls..."
bash "${BASE_DIR}/scripts/configure/firewalls/external-fw.sh"
bash "${BASE_DIR}/scripts/configure/firewalls/siem-fw.sh"

# 3. DMZ services
log_info "[3/7] Configuring DMZ..."
bash "${BASE_DIR}/scripts/configure/dmz/database.sh"
bash "${BASE_DIR}/scripts/configure/dmz/webserver.sh"
bash "${BASE_DIR}/scripts/configure/dmz/proxy.sh"

# 4. SIEM (순서 중요: ES → Logstash → Kibana)
log_info "[4/7] Configuring Elasticsearch..."
bash "${BASE_DIR}/scripts/configure/siem/elasticsearch.sh"

log_info "[5/7] Configuring Logstash (90s startup wait)..."
bash "${BASE_DIR}/scripts/configure/siem/logstash.sh"

log_info "[6/7] Configuring Kibana..."
bash "${BASE_DIR}/scripts/configure/siem/kibana.sh"

# 5. Optional
log_info "[7/7] Configuring remaining services..."
bash "${BASE_DIR}/scripts/configure/siem/siem-pc.sh" 2>/dev/null || true
for f in "${BASE_DIR}/scripts/configure/ids/"*.sh; do [ -f "$f" ] && bash "$f" 2>/dev/null || true; done
for f in "${BASE_DIR}/scripts/configure/clients/"*.sh; do [ -f "$f" ] && bash "$f" 2>/dev/null || true; done

log_ok "=== DMZ Lab Deployment Complete ==="
