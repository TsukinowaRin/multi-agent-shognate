#!/usr/bin/env bash
# Compatibility wrapper for the Shogunate MOD Goza layout autosave helper.

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
MOD_HELPER="${SCRIPT_DIR}/shogunate_mod/view/goza_layout_autosave.sh"

exec bash "$MOD_HELPER" "$@"
