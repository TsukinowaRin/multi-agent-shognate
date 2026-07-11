#!/usr/bin/env bash
set -euo pipefail
SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
export SHOGUNATE_ROLE_CONFIG_PAUSE=1
exec bash "$SCRIPT_DIR/shogunate_mod/configure/role_launcher.sh" "$@"
