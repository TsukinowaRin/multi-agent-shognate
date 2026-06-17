#!/usr/bin/env bash
# Compatibility wrapper for the Shogunate MOD runtime CLI preference daemon.

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
MOD_DAEMON="${SCRIPT_DIR}/shogunate_mod/runtime/cli_pref_daemon.sh"

exec bash "$MOD_DAEMON" "$@"
