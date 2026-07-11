#!/usr/bin/env bash
# Compatibility wrapper for the Shogunate MOD CLI adapter.

CLI_ADAPTER_WRAPPER_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
CLI_ADAPTER_WRAPPER_ROOT="$(cd "${CLI_ADAPTER_WRAPPER_DIR}/.." && pwd)"
CLI_ADAPTER_MOD_SOURCE="${CLI_ADAPTER_WRAPPER_ROOT}/shogunate_mod/cli/adapter.sh"

# shellcheck source=/dev/null
source "$CLI_ADAPTER_MOD_SOURCE"
