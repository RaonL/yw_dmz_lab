#!/bin/bash
set -euo pipefail

BASE_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/../../.." && pwd)"
source "${BASE_DIR}/scripts/lib/logging.sh"
source "${BASE_DIR}/config/variables.sh"

log_info "Configuring Logstash"

LOGSTASH_CONTAINER="clab-${LAB_NAME}-logstash"
SIEMFW_CONTAINER="clab-${LAB_NAME}-SIEM_FW"
ES_CONTAINER="clab-${LAB_NAME}-elasticsearch"

LOGSTASH_PID=$(sudo docker inspect -f '{{.State.Pid}}' ${LOGSTASH_CONTAINER})
SIEMFW_PID=$(sudo docker inspect -f '{{.State.Pid}}' ${SIEMFW_CONTAINER})

# --- Step 1: Network interface ---
log_info "Checking Logstash network interfaces..."
if ! sudo nsenter -t $LOGSTASH_PID -n ip link show eth1 &>/dev/null; then
    log_info "eth1 not found — creating veth pair..."
    sudo ip link add veth-ls-fw type veth peer name veth-fw-ls 2>/dev/null || true
    sudo ip link set veth-ls-fw netns $LOGSTASH_PID
    sudo nsenter -t $LOGSTASH_PID -n ip link set veth-ls-fw name eth1
    if ! sudo nsenter -t $SIEMFW_PID -n ip link show eth3 &>/dev/null; then
        sudo ip link set veth-fw-ls netns $SIEMFW_PID
        sudo nsenter -t $SIEMFW_PID -n ip link set veth-fw-ls name eth3
        sudo nsenter -t $SIEMFW_PID -n ip addr add ${SIEM_FW_ETH3_IP} dev eth3 2>/dev/null || true
        sudo nsenter -t $SIEMFW_PID -n ip link set eth3 up
    else
        sudo ip link delete veth-fw-ls 2>/dev/null || true
    fi
    log_ok "veth pair created"
else
    log_info "eth1 already exists"
fi

sudo nsenter -t $LOGSTASH_PID -n ip addr add ${SIEM_LOGSTASH_ETH1_IP} dev eth1 2>/dev/null || true
sudo nsenter -t $LOGSTASH_PID -n ip link set eth1 up
sudo nsenter -t $LOGSTASH_PID -n ip route add 10.0.3.0/24 via ${SIEM_FW_ETH3_IP%/*} dev eth1 2>/dev/null || true

# --- Step 2: Register ES hostname ---
log_info "Registering Elasticsearch hostname..."
ES_IP=$(sudo docker inspect -f '{{range .NetworkSettings.Networks}}{{.IPAddress}}{{end}}' ${ES_CONTAINER})
sudo nsenter -t $LOGSTASH_PID -m -- bash -c "grep -q elasticsearch /etc/hosts || echo '$ES_IP elasticsearch' >> /etc/hosts"
log_ok "Elasticsearch registered as $ES_IP"

# --- Step 3: Directories ---
sudo docker exec -u 0 ${LOGSTASH_CONTAINER} bash -c '
    mkdir -p /usr/share/logstash/data /usr/share/logstash/logs
    chown -R logstash:logstash /usr/share/logstash/data /usr/share/logstash/logs
    : > /usr/share/logstash/logs/startup.log
    chown logstash:logstash /usr/share/logstash/logs/startup.log
' 2>/dev/null || true

# --- Step 4: Validate pipeline config (syntax check) ---
log_info "Validating Logstash pipeline config..."
if ! sudo docker exec -u logstash ${LOGSTASH_CONTAINER} \
      /usr/share/logstash/bin/logstash \
      --path.settings /usr/share/logstash/config \
      -t 2>&1 | tail -20; then
    log_warn "Pipeline validation reported issues (see above)"
fi

# --- Step 5: Start Logstash ---
log_info "Starting Logstash..."
if sudo docker exec ${LOGSTASH_CONTAINER} ps aux 2>/dev/null | grep -q "[j]ava.*logstash"; then
    log_info "Logstash already running -> restarting to apply latest pipeline..."
    sudo docker exec ${LOGSTASH_CONTAINER} pkill -f "/usr/share/logstash/bin/logstash" 2>/dev/null || true
    for _ in $(seq 1 20); do
        if ! sudo docker exec ${LOGSTASH_CONTAINER} ps aux 2>/dev/null | grep -q "[j]ava.*logstash"; then
            break
        fi
        sleep 1
    done
fi

# 표준 출력/에러를 startup.log에 캡쳐 (진단 핵심)
sudo docker exec -d -u logstash ${LOGSTASH_CONTAINER} bash -c '
  /usr/share/logstash/bin/logstash \
    --path.config /usr/share/logstash/pipeline \
    --path.settings /usr/share/logstash/config \
    --path.data /usr/share/logstash/data \
    --path.logs /usr/share/logstash/logs \
    > /usr/share/logstash/logs/startup.log 2>&1
'

log_info "Waiting for Logstash API (max 120s)..."
READY=0
for i in $(seq 1 24); do
    if sudo docker exec ${LOGSTASH_CONTAINER} \
         bash -c 'exec 3<>/dev/tcp/127.0.0.1/9600 && echo -e "GET / HTTP/1.0\r\n\r\n" >&3 && cat <&3 | head -1' \
         2>/dev/null | grep -q "200 OK"; then
        READY=1
        break
    fi
    sleep 5
done

if [ "$READY" -eq 1 ]; then
    log_ok "Logstash API is up (http://localhost:9600)"
elif sudo docker exec ${LOGSTASH_CONTAINER} ps aux 2>/dev/null | grep -q "[j]ava.*logstash"; then
    log_warn "Logstash process up but API not responding yet — check logs/startup.log"
else
    log_error "Logstash failed to start. Last 40 lines of startup.log:"
    sudo docker exec ${LOGSTASH_CONTAINER} tail -n 40 /usr/share/logstash/logs/startup.log 2>/dev/null || true
fi

log_ok "Logstash configured"
