#!/bin/bash
set -euo pipefail

# Get script directory and set up paths
BASE_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/../../.." && pwd)"
SCRIPTS_DIR="${BASE_DIR}/scripts"
CONFIG_DIR="${BASE_DIR}/config"

# Load dependencies
source "${SCRIPTS_DIR}/lib/logging.sh"
source "${CONFIG_DIR}/variables.sh"

Database_Container="clab-${LAB_NAME}-Database"

log_info "Configuring Database"
sudo docker exec -i \
    -e DMZ_DB_ETH1_IP="${DMZ_DB_ETH1_IP}" \
    -e INT_FW_ETH2_IP="${INT_FW_ETH2_IP}" \
    "${Database_Container}" sh << 'EOF'
    
set -e
if command -v apt >/dev/null 2>&1; then
  apt update >/dev/null 2>&1 || true
  apt install -y iproute2 iputils-ping >/dev/null 2>&1 || true
elif command -v apk >/dev/null 2>&1; then
  apk add --no-cache iproute2 iputils >/dev/null 2>&1 || true
fi

ip addr add ${DMZ_DB_ETH1_IP} dev eth1 || true
ip link set eth1 up
ip route replace default via ${INT_FW_ETH2_IP%/*} || true
EOF

log_info "Waiting for PostgreSQL to be ready..."
for i in $(seq 1 30); do
  if sudo docker exec "${Database_Container}" pg_isready -U postgres >/dev/null 2>&1; then
    log_ok "PostgreSQL is ready"
    break
  fi
  sleep 2
done

log_info "Initializing database tables..."
sudo docker exec -i "${Database_Container}" psql -U postgres -d webapp << 'SQL'
CREATE TABLE IF NOT EXISTS users (
    username VARCHAR(50) PRIMARY KEY,
    password VARCHAR(100) NOT NULL
);

CREATE TABLE IF NOT EXISTS reports (
    report_id SERIAL PRIMARY KEY,
    title VARCHAR(200) NOT NULL,
    details TEXT
);

CREATE TABLE IF NOT EXISTS user_report_access (
    username VARCHAR(50) REFERENCES users(username),
    report_id INTEGER REFERENCES reports(report_id),
    PRIMARY KEY (username, report_id)
);

INSERT INTO users (username, password) VALUES
    ('admin', 'admin123'),
    ('analyst', 'analyst123'),
    ('guest', 'guest123')
ON CONFLICT (username) DO NOTHING;

INSERT INTO reports (report_id, title, details) VALUES
    (1, 'Monthly Security Report', 'Summary of security incidents for the current month. 3 critical alerts detected.'),
    (2, 'Network Traffic Analysis', 'Unusual traffic patterns detected from external IPs. Further investigation required.'),
    (3, 'Vulnerability Scan Results', 'Scan completed: 2 high, 5 medium, 12 low vulnerabilities found across DMZ servers.')
ON CONFLICT (report_id) DO NOTHING;

INSERT INTO user_report_access (username, report_id) VALUES
    ('admin', 1), ('admin', 2), ('admin', 3),
    ('analyst', 1), ('analyst', 2),
    ('guest', 1)
ON CONFLICT DO NOTHING;
SQL

log_ok "Database initialized"
