#!/bin/bash
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
REPO_DIR="$(cd "${SCRIPT_DIR}/.." && pwd)"
TARGET_SCRIPT="${REPO_DIR}/scripts/configure/network/attacker.sh"

if [ ! -f "${TARGET_SCRIPT}" ]; then
  echo "[ERROR] Missing script: ${TARGET_SCRIPT}" >&2
  echo "        Run this from the repository clone (yw_dmz_lab) and ensure scripts/configure/network/attacker.sh exists." >&2
  exit 1
fi

exec bash "${TARGET_SCRIPT}"
