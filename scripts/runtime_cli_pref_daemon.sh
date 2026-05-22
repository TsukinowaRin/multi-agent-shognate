#!/usr/bin/env bash
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
cd "$SCRIPT_DIR"

INTERVAL="${MAS_RUNTIME_PREF_SYNC_INTERVAL:-1}"
SYNC_PYTHON="${MAS_RUNTIME_PREF_SYNC_PYTHON:-python3}"
SYNC_SCRIPT="${MAS_RUNTIME_PREF_SYNC_SCRIPT:-$SCRIPT_DIR/scripts/sync_runtime_cli_preferences.py}"
SYNC_LOG="${MAS_RUNTIME_PREF_SYNC_LOG:-}"
ONCE=false
if [[ "${1:-}" == "--once" ]]; then
  ONCE=true
fi

run_sync() {
  if [[ -f "$SYNC_SCRIPT" ]]; then
    if [[ -n "$SYNC_LOG" ]]; then
      mkdir -p "$(dirname "$SYNC_LOG")"
      "$SYNC_PYTHON" "$SYNC_SCRIPT" >>"$SYNC_LOG" 2>&1 || true
    else
      "$SYNC_PYTHON" "$SYNC_SCRIPT" || true
    fi
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
