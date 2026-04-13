#!/bin/bash
set -euo pipefail

# Convenience wrapper: can be executed from ./attacks to configure attacker network.
BASE_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
exec bash "${BASE_DIR}/scripts/configure/network/attacker.sh"
