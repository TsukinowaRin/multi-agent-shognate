#!/usr/bin/env bash
# Compatibility wrapper for the Shogunate MOD Karo-to-Shogun completion bridge daemon.

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
MOD_DAEMON="${SCRIPT_DIR}/shogunate_mod/runtime/karo_done_to_shogun_bridge_daemon.sh"

exec bash "$MOD_DAEMON" "$@"
