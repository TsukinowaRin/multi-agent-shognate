#!/usr/bin/env bash
# Compatibility wrapper for the Shogunate MOD role pane focus helper.

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
MOD_HELPER="${SCRIPT_DIR}/shogunate_mod/view/focus_agent_pane.sh"

exec bash "$MOD_HELPER" "$@"
