#!/usr/bin/env bash
# Compatibility wrapper for the Shogunate MOD CLI switch command.

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
MOD_SWITCH="${SCRIPT_DIR}/shogunate_mod/configure/switch_cli.sh"

exec bash "$MOD_SWITCH" "$@"
