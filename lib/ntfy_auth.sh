#!/usr/bin/env bash
# Compatibility wrapper for the Shogunate MOD ntfy auth helpers.

NTFY_AUTH_WRAPPER_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
NTFY_AUTH_WRAPPER_ROOT="$(cd "${NTFY_AUTH_WRAPPER_DIR}/.." && pwd)"
NTFY_AUTH_MOD_SOURCE="${NTFY_AUTH_WRAPPER_ROOT}/shogunate_mod/notify/ntfy_auth.sh"

# shellcheck source=/dev/null
source "$NTFY_AUTH_MOD_SOURCE"
