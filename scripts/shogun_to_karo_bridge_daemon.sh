#!/usr/bin/env bash
# Compatibility wrapper for the Shogunate MOD Shogun-to-Karo bridge daemon.

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
MOD_DAEMON="${SCRIPT_DIR}/shogunate_mod/runtime/shogun_to_karo_bridge_daemon.sh"

exec bash "$MOD_DAEMON" "$@"
