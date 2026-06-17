#!/usr/bin/env bash
# Compatibility wrapper for the Shogunate MOD agent registry helpers.

AGENT_REGISTRY_WRAPPER_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
AGENT_REGISTRY_WRAPPER_ROOT="$(cd "${AGENT_REGISTRY_WRAPPER_DIR}/.." && pwd)"
AGENT_REGISTRY_MOD_SOURCE="${AGENT_REGISTRY_WRAPPER_ROOT}/shogunate_mod/topology/agent_registry.sh"

# shellcheck source=/dev/null
source "$AGENT_REGISTRY_MOD_SOURCE"
