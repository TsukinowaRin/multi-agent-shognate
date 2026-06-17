#!/usr/bin/env bash
# Compatibility wrapper for the Shogunate MOD agent configurator.

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
MOD_CONFIGURATOR="${SCRIPT_DIR}/shogunate_mod/configure/agents.sh"

exec bash "$MOD_CONFIGURATOR" "$@"
