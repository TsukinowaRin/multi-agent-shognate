#!/bin/bash
# Compatibility wrapper for the Shogunate MOD watcher supervisor.
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
exec bash "$SCRIPT_DIR/shogunate_mod/watcher/supervisor.sh" "$@"
