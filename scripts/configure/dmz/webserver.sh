#!/bin/bash
set -euo pipefail

BASE_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/../../.." && pwd)"
SCRIPTS_DIR="${BASE_DIR}/scripts"
CONFIG_DIR="${BASE_DIR}/config"

source "${SCRIPTS_DIR}/lib/logging.sh"
source "${CONFIG_DIR}/variables.sh"

log_info "Configuring Flask Webserver"

DMZ_WEB_CONTAINER="clab-${LAB_NAME}-Flask_Webserver"

sudo docker exec -i --user root "${DMZ_WEB_CONTAINER}" mkdir -p /app
sudo docker cp "${CONFIG_DIR}/webserver-details/app.py" "${DMZ_WEB_CONTAINER}:/app/app.py"

sudo docker exec -i --user root \
  -e DMZ_WEB_ETH1_IP="${DMZ_WEB_ETH1_IP}" \
  -e DMZ_WEB_ETH2_IP="${DMZ_WEB_ETH2_IP}" \
  -e DMZ_WAF_ETH2_IP="${DMZ_WAF_ETH2_IP}" \
  -e DMZ_DB_ETH1_IP="${DMZ_DB_ETH1_IP}" \
  -e DB_HOST="${DMZ_DB_ETH1_IP%/*}" \
  -e DB_NAME="webapp" \
  -e DB_USER="postgres" \
  -e DB_PASSWORD="admin123" \
  -e DB_PORT="5432" \
  "${DMZ_WEB_CONTAINER}" sh <<'EOF_INNER'
set -eu

echo "[1/3] Installing dependencies..."
apt-get update && \
apt-get install -y --no-install-recommends \
  iproute2 iputils-ping python3 python3-flask python3-psycopg2 \
  libpq-dev build-essential openssl \
  2>&1 | tail -10
echo "[OK] Dependencies installed"

ip addr add "${DMZ_WEB_ETH1_IP}" dev eth1 || true
ip addr add "${DMZ_WEB_ETH2_IP}" dev eth2 || true
ip link set eth1 up
ip link set eth2 up
ip route replace default via "${DMZ_WAF_ETH2_IP%/*}" || true
ip route replace "${DMZ_DB_ETH1_IP%/*}/32" dev eth2 || true

echo "[2/3] Starting Flask app..."
pkill -f "python3 app.py" 2>/dev/null || true
cd /app && nohup python3 app.py > /var/log/flask.log 2>&1 </dev/null &
sleep 2

echo "[3/3] Verifying Flask process..."
if pgrep -f "python3 app.py" >/dev/null 2>&1; then
  echo "[OK] Flask started"
else
  echo "[ERROR] Flask failed to start"
  tail -n 30 /var/log/flask.log 2>/dev/null || true
  exit 1
fi
EOF_INNER

log_ok "DMZ configured"
