#!/usr/bin/env bash
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
cd "$SCRIPT_DIR"

INTERVAL="${MAS_SHOGUN_TO_KARO_BRIDGE_INTERVAL:-2}"
PYTHON_BIN="${MAS_SHOGUN_TO_KARO_BRIDGE_PYTHON:-python3}"
BRIDGE_SCRIPT="${MAS_SHOGUN_TO_KARO_BRIDGE_SCRIPT:-$SCRIPT_DIR/scripts/shogun_to_karo_bridge.py}"

while true; do
    "$PYTHON_BIN" "$BRIDGE_SCRIPT" || true
    sleep "$INTERVAL"
done
