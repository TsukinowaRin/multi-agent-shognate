#!/usr/bin/env bash
# Compatibility wrapper for the Shogunate MOD topology adapter.

TOPOLOGY_ADAPTER_WRAPPER_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
TOPOLOGY_ADAPTER_WRAPPER_ROOT="$(cd "${TOPOLOGY_ADAPTER_WRAPPER_DIR}/.." && pwd)"
TOPOLOGY_ADAPTER_MOD_SOURCE="${TOPOLOGY_ADAPTER_WRAPPER_ROOT}/shogunate_mod/topology/adapter.sh"

# shellcheck source=/dev/null
source "$TOPOLOGY_ADAPTER_MOD_SOURCE"
