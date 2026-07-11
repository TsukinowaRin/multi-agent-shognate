#!/usr/bin/env bash
# Compatibility wrapper for the Shogunate MOD ntfy sender.

set -euo pipefail
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
MOD_SEND="${SCRIPT_DIR}/shogunate_mod/notify/send.sh"

exec bash "$MOD_SEND" "$@"
