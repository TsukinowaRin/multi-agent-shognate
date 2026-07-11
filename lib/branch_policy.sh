#!/usr/bin/env bash
# Compatibility wrapper for the Shogunate MOD branch policy helpers.

BRANCH_POLICY_WRAPPER_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
BRANCH_POLICY_WRAPPER_ROOT="$(cd "${BRANCH_POLICY_WRAPPER_DIR}/.." && pwd)"
BRANCH_POLICY_MOD_SOURCE="${BRANCH_POLICY_WRAPPER_ROOT}/shogunate_mod/git/branch_policy.sh"

# shellcheck source=/dev/null
source "$BRANCH_POLICY_MOD_SOURCE"
