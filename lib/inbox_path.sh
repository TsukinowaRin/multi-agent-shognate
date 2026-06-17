#!/usr/bin/env bash
# Compatibility wrapper for the Shogunate MOD inbox path helpers.

INBOX_PATH_WRAPPER_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
INBOX_PATH_WRAPPER_ROOT="$(cd "${INBOX_PATH_WRAPPER_DIR}/.." && pwd)"
INBOX_PATH_MOD_SOURCE="${INBOX_PATH_WRAPPER_ROOT}/shogunate_mod/inbox/path.sh"

# shellcheck source=/dev/null
source "$INBOX_PATH_MOD_SOURCE"
