#!/usr/bin/env bash
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
cd "$SCRIPT_DIR"

INTERVAL="${MAS_KARO_DONE_TO_SHOGUN_INTERVAL:-2}"
BRIDGE_PYTHON="${MAS_KARO_DONE_TO_SHOGUN_PYTHON:-python3}"
BRIDGE_SCRIPT="${MAS_KARO_DONE_TO_SHOGUN_SCRIPT:-$SCRIPT_DIR/scripts/karo_done_to_shogun_bridge.py}"

while true; do
  if [[ -f "$BRIDGE_SCRIPT" ]]; then
    "$BRIDGE_PYTHON" "$BRIDGE_SCRIPT" || true
  fi
  sleep "$INTERVAL"
done
