#!/bin/bash
set -euo pipefail

BASE_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
source "${BASE_DIR}/config/variables.sh"

ATTACKER_CONTAINER="clab-${LAB_NAME}-Attacker"
TARGET_URL="http://${EXT_FW_NAT_IP}:8080/"
LOGSTASH_TCP_HOST="${SIEM_LOGSTASH_ETH1_IP%/*}"
LOGSTASH_TCP_PORT="5000"

echo "=== XSS Test against WAF (from Attacker container) ==="
echo "Target: ${TARGET_URL}"
echo "Logstash TCP: ${LOGSTASH_TCP_HOST}:${LOGSTASH_TCP_PORT}"

if ! docker ps --format '{{.Names}}' | grep -qx "${ATTACKER_CONTAINER}"; then
  echo "[ERROR] Attacker container not running: ${ATTACKER_CONTAINER}"
  exit 1
fi

prepare_attacker() {
  docker exec -i \
    -e INTERNET_ATTACKER_ETH1_IP="${INTERNET_ATTACKER_ETH1_IP}" \
    -e ROUTER_INTERNET_ETH1_IP="${ROUTER_INTERNET_ETH1_IP}" \
    -e EXT_FW_NAT_IP="${EXT_FW_NAT_IP}" \
    "${ATTACKER_CONTAINER}" sh -lc '
      set -e
      if ! command -v ip >/dev/null 2>&1; then
        if command -v apt-get >/dev/null 2>&1; then
          apt-get update -qq >/dev/null 2>&1 || true
          apt-get install -y iproute2 curl netcat-openbsd >/dev/null 2>&1 || true
        elif command -v apk >/dev/null 2>&1; then
          apk add --no-cache iproute2 curl netcat-openbsd >/dev/null 2>&1 || true
        fi
      fi

      if command -v ip >/dev/null 2>&1; then
        ip addr add "${INTERNET_ATTACKER_ETH1_IP}" dev eth1 2>/dev/null || true
        ip link set eth1 up || true
        ip route replace default via "${ROUTER_INTERNET_ETH1_IP%/*}" dev eth1 || true
        ip route replace "${EXT_FW_NAT_IP}" via "${ROUTER_INTERNET_ETH1_IP%/*}" dev eth1 || true
      fi
    ' >/dev/null 2>&1 || true
}

send_attack_log() {
  local attack_type="$1"
  local http_code="$2"
  local logstash_container="clab-${LAB_NAME}-logstash"
  local msg
  msg=$(printf '{"log_type":"attack","attack_type":"%s","http_code":"%s","source":"attacker"}\n' \
        "$attack_type" "$http_code")
  # Logstash 컨테이너 내부에서 직접 TCP 입력으로 전송 (방화벽 우회)
  timeout 5 docker exec -i "${logstash_container}" \
    bash -c "exec 3<>/dev/tcp/127.0.0.1/5000 && printf '%s' '$msg' >&3" \
    >/dev/null 2>&1 || true
}


prepare_attacker

for payload in "<script>alert(1)</script>" "<img src=x onerror=alert(1)>" "<svg/onload=alert(1)>"; do
  echo -n "Payload: $payload → "
  CODE=$(docker exec \
    -e ATTACK_URL="${TARGET_URL}" \
    -e ATTACK_PAYLOAD="${payload}" \
    "${ATTACKER_CONTAINER}" sh -lc '
      result=$(curl -s -o /dev/null -w "%{http_code}" --connect-timeout 5 --max-time 10 -X POST "$ATTACK_URL" --data-urlencode "username=$ATTACK_PAYLOAD" --data-urlencode "password=test" 2>/dev/null) || true
      echo "${result:-000}"
    ' 2>/dev/null)
  CODE=${CODE:-000}
  echo "HTTP $CODE"
  send_attack_log "xss" "$CODE"
  sleep 1
done

echo "=== Done ==="
