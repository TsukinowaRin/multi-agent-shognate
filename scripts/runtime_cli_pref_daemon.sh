#!/usr/bin/env bash
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
cd "$SCRIPT_DIR"

INTERVAL="${MAS_RUNTIME_PREF_SYNC_INTERVAL:-1}"
SYNC_PYTHON="${MAS_RUNTIME_PREF_SYNC_PYTHON:-python3}"
SYNC_SCRIPT="${MAS_RUNTIME_PREF_SYNC_SCRIPT:-$SCRIPT_DIR/scripts/sync_runtime_cli_preferences.py}"
ONCE=false
if [[ "${1:-}" == "--once" ]]; then
  ONCE=true
fi

run_sync() {
  if [[ -f "$SYNC_SCRIPT" ]]; then
    "$SYNC_PYTHON" "$SYNC_SCRIPT" >/tmp/mas_runtime_cli_sync_daemon.log 2>&1 || true
  fi
}

if [[ "$ONCE" == true ]]; then
  run_sync
  exit 0
fi

while true; do
  run_sync
  sleep "$INTERVAL"
done
