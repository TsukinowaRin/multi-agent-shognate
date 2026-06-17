#!/usr/bin/env bash
# Compatibility wrapper for the Shogunate MOD ntfy listener.

set -euo pipefail
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
MOD_LISTENER="${SCRIPT_DIR}/shogunate_mod/notify/listener.sh"

exec bash "$MOD_LISTENER" "$@"
