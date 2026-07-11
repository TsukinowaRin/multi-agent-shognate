#!/usr/bin/env bash
# Compatibility wrapper for the Shogunate MOD agent status command.

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
MOD_COMMAND="${SCRIPT_DIR}/shogunate_mod/status/command.sh"

exec bash "$MOD_COMMAND" "$@"
