#!/bin/bash

set -euo pipefail

# Get script directory and set up paths
BASE_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/../../.." && pwd)"
SCRIPTS_DIR="${BASE_DIR}/scripts"
CONFIG_DIR="${BASE_DIR}/config"

# Load dependencies
source "${SCRIPTS_DIR}/lib/logging.sh"
source "${CONFIG_DIR}/variables.sh"

log_info "Configuring Flask Webserver"

DMZ_WEB_CONTAINER="clab-${LAB_NAME}-Flask_Webserver"


log_info "Configuring Flask Webserver"
sudo docker exec -i --user root ${DMZ_WEB_CONTAINER} mkdir -p /app
sudo docker cp ${CONFIG_DIR}/webserver-details/app.py ${DMZ_WEB_CONTAINER}:/app/app.py

# FIX: DB 환경변수 추가 (-e DB_HOST, DB_NAME, DB_USER, DB_PASSWORD)
# DB_HOST는 CIDR(/24) 제거 후 순수 IP만 전달
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
 "${DMZ_WEB_CONTAINER}" sh << 'EOF'
set -e

#install dependencies
echo "[1/2] Installing dependencies..."
apt-get update && \
apt-get install -y --no-install-recommends \
 iproute2 \
 iputils-ping \
 python3 \
 python3-flask \
 python3-psycopg2 \
 libpq-dev \
 build-essential \
 openssl \
 2>&1 | tail -10

echo "[OK] Dependencies installed"

# FIX: 네트워크 설정을 먼저 완료한 뒤 Flask 시작
ip addr add "${DMZ_WEB_ETH1_IP}" dev eth1 || true
ip addr add "${DMZ_WEB_ETH2_IP}" dev eth2 || true
ip link set eth1 up
ip link set eth2 up

ip route replace default via "${DMZ_WAF_ETH2_IP%/*}" || true
ip route add "${DMZ_DB_ETH1_IP%/*}" via "${DMZ_WEB_ETH2_IP%/*}" dev eth2 || true

# FIX: nohup + disown으로 docker exec 종료 후에도 Flask 프로세스 유지
echo "[2/2] Starting Flask app..."
cd /app && nohup python3 app.py > /var/log/flask.log 2>&1 &
disown $!
echo "[OK] Flask started (PID $!, log: /var/log/flask.log)"

EOF
echo "[OK] Flask Webserver configured"
echo ""

log_ok "DMZ configured"
