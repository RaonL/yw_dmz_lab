#!/bin/bash
set -euo pipefail

BASE_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
source "${BASE_DIR}/config/variables.sh"

ATTACKER_CONTAINER="clab-${LAB_NAME}-Attacker"
TARGET_URL="http://${EXT_FW_NAT_IP}:8080/"
LOGSTASH_TCP_HOST="${SIEM_LOGSTASH_ETH1_IP%/*}"
LOGSTASH_TCP_PORT="5000"

echo "=== SQL Injection Test against WAF (from Attacker container) ==="
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
  timeout 5 docker exec \
    -e LS_HOST="${LOGSTASH_TCP_HOST}" \
    -e LS_PORT="${LOGSTASH_TCP_PORT}" \
    -e ATTACK_TYPE="${attack_type}" \
    -e HTTP_CODE="${http_code}" \
    "${ATTACKER_CONTAINER}" sh -lc '
      MSG=$(printf "{\"log_type\":\"attack\",\"attack_type\":\"%s\",\"http_code\":\"%s\",\"source\":\"attacker\"}\n" "$ATTACK_TYPE" "$HTTP_CODE")
      timeout 2 sh -c "printf %s \"$MSG\" | nc -w 1 \"$LS_HOST\" \"$LS_PORT\"" >/dev/null 2>&1 || true
    ' >/dev/null 2>&1 || true
}

prepare_attacker

for payload in "' OR '1'='1" "' OR 1=1--" "admin'--" "' UNION SELECT * FROM users--"; do
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
  send_attack_log "sql_injection" "$CODE"
  sleep 1
done

echo "=== Done ==="
