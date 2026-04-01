#!/usr/bin/env bash
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
cd "$SCRIPT_DIR"

INTERVAL="${MAS_SHOGUN_TO_KARO_BRIDGE_INTERVAL:-2}"
PYTHON_BIN="${MAS_SHOGUN_TO_KARO_BRIDGE_PYTHON:-python3}"
BRIDGE_SCRIPT="${MAS_SHOGUN_TO_KARO_BRIDGE_SCRIPT:-$SCRIPT_DIR/scripts/shogun_to_karo_bridge.py}"
VERBOSE_NOOP="${MAS_BRIDGE_VERBOSE_NOOP:-0}"

run_bridge_once() {
    local output=""
    local status=0
    local first_line=""

    [ -f "$BRIDGE_SCRIPT" ] || return 0

    if ! output="$("$PYTHON_BIN" "$BRIDGE_SCRIPT" 2>&1)"; then
        status=$?
        [ -n "$output" ] && printf '%s\n' "$output" >&2
        return "$status"
    fi

    [ -n "$output" ] || return 0
    first_line="${output%%$'\n'*}"
    if [ "$VERBOSE_NOOP" = "1" ] || [[ "$first_line" != noop$'\t'* ]]; then
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
