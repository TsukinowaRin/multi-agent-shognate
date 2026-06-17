#!/usr/bin/env bash
set -euo pipefail

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
MOD_ALIASES="$ROOT_DIR/shogunate_mod/shell/aliases.sh"

if [[ "${BASH_SOURCE[0]}" == "$0" ]]; then
    exec bash "$MOD_ALIASES" "$@"
fi

source "$MOD_ALIASES"
