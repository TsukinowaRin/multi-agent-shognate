#!/usr/bin/env bash
# Compatibility wrapper for the Shogunate MOD generated-instruction guard.

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
MOD_ENSURE="${SCRIPT_DIR}/shogunate_mod/instructions/ensure_generated.sh"

exec bash "$MOD_ENSURE" "$@"
