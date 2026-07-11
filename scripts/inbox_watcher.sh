#!/bin/bash
# Compatibility wrapper for the Shogunate MOD inbox watcher.

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
MOD_WATCHER="$SCRIPT_DIR/shogunate_mod/watcher/inbox_watcher.sh"

if [ "${BASH_SOURCE[0]}" != "$0" ]; then
    # shellcheck source=/dev/null
    source "$MOD_WATCHER"
else
    exec bash "$MOD_WATCHER" "$@"
fi
