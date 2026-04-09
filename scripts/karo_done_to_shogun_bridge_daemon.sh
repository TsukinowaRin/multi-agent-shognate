#!/usr/bin/env bash
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
cd "$SCRIPT_DIR"

INTERVAL="${MAS_KARO_DONE_TO_SHOGUN_INTERVAL:-2}"
BRIDGE_PYTHON="${MAS_KARO_DONE_TO_SHOGUN_PYTHON:-python3}"
BRIDGE_SCRIPT="${MAS_KARO_DONE_TO_SHOGUN_SCRIPT:-$SCRIPT_DIR/scripts/karo_done_to_shogun_bridge.py}"
VERBOSE_NOOP="${MAS_BRIDGE_VERBOSE_NOOP:-0}"

run_bridge_once() {
  local output=""
  local status=0
  local first_line=""

  [ -f "$BRIDGE_SCRIPT" ] || return 0

  if ! output="$("$BRIDGE_PYTHON" "$BRIDGE_SCRIPT" 2>&1)"; then
    status=$?
    [ -n "$output" ] && printf '%s\n' "$output" >&2
    return "$status"
  fi

  [ -n "$output" ] || return 0
  first_line="${output%%$'\n'*}"
  if [ "$VERBOSE_NOOP" = "1" ] || ([[ "$first_line" != noop$'\t'* ]] && [[ "$first_line" != primed$'\t'* ]]); then
    printf '%s\n' "$output"
  fi
}

if [ "${1:-}" = "--once" ]; then
  run_bridge_once
  exit 0
fi

while true; do
  run_bridge_once || true
  sleep "$INTERVAL"
done
