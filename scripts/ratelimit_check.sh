#!/usr/bin/env bash
# Compatibility wrapper for the Shogunate MOD rate-limit status command.

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
MOD_RATELIMIT="${SCRIPT_DIR}/shogunate_mod/status/ratelimit_check.sh"

exec bash "$MOD_RATELIMIT" "$@"
