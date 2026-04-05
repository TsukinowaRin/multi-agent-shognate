#!/usr/bin/env bash
set -euo pipefail

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"

if [[ "${BASH_SOURCE[0]}" == "$0" ]]; then
    cat <<EOF
[INFO] このスクリプトは source して使います。

  source "$ROOT_DIR/scripts/shell_aliases.sh"

永続化する場合:

  bash "$ROOT_DIR/scripts/install_shell_aliases.sh"
EOF
    exit 0
fi

alias csst="cd $ROOT_DIR && ./shutsujin_departure.sh"
alias css="bash $ROOT_DIR/scripts/focus_agent_pane.sh shogun"
alias csg="bash $ROOT_DIR/scripts/focus_agent_pane.sh gunshi"
alias csm="bash $ROOT_DIR/scripts/focus_agent_pane.sh karo"
alias cgo="bash $ROOT_DIR/scripts/goza_no_ma.sh"
