#!/usr/bin/env bash
# Compatibility wrapper for the Shogunate MOD instruction builder.

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
MOD_BUILDER="${SCRIPT_DIR}/shogunate_mod/instructions/build.sh"

exec bash "$MOD_BUILDER" "$@"
