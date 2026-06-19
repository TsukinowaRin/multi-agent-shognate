#!/usr/bin/env bash
# Canonical Shogunate runtime entrypoint. Root launchers delegate here.

set -e

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)"
cd "$SCRIPT_DIR"

MOD_RUNTIME_LOADER="$SCRIPT_DIR/shogunate_mod/runtime/load.sh"
if [ ! -f "$MOD_RUNTIME_LOADER" ]; then
    echo "[ERROR] Shogunate runtime loader not found: $MOD_RUNTIME_LOADER" >&2
    exit 1
fi

# shellcheck source=/dev/null
. "$MOD_RUNTIME_LOADER"

run_shutsujin_departure "$@"
