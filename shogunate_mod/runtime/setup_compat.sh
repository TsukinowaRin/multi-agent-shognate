#!/usr/bin/env bash
# Compatibility setup entrypoint. Historical setup.sh now delegates here.

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)"
MOD_RUNTIME_LOADER="$SCRIPT_DIR/shogunate_mod/runtime/load.sh"

if [ ! -f "$MOD_RUNTIME_LOADER" ]; then
    echo "[ERROR] Shogunate runtime loader not found: $MOD_RUNTIME_LOADER" >&2
    exit 1
fi

# shellcheck source=/dev/null
. "$MOD_RUNTIME_LOADER"

run_shutsujin_departure "$@"
