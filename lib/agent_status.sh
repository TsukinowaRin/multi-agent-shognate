#!/usr/bin/env bash
# Compatibility wrapper for the Shogunate MOD agent status helpers.

AGENT_STATUS_WRAPPER_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
AGENT_STATUS_WRAPPER_ROOT="$(cd "${AGENT_STATUS_WRAPPER_DIR}/.." && pwd)"
AGENT_STATUS_MOD_SOURCE="${AGENT_STATUS_WRAPPER_ROOT}/shogunate_mod/status/agent_status.sh"

# shellcheck source=/dev/null
source "$AGENT_STATUS_MOD_SOURCE"
