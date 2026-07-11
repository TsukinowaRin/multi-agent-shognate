#!/usr/bin/env bash
# Compatibility wrapper for the Shogunate MOD YAML slimming command.

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
MOD_SLIM="${SCRIPT_DIR}/shogunate_mod/queue/slim_yaml.sh"

exec bash "$MOD_SLIM" "$@"
