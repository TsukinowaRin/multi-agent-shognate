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

# Upstream-style shortcuts.
alias csst="cd $ROOT_DIR && ./shutsujin_departure.sh"
alias css="bash $ROOT_DIR/scripts/focus_agent_pane.sh shogun"
alias csm="bash $ROOT_DIR/scripts/goza_no_ma.sh -t multiagent"
alias CSST="cd $ROOT_DIR && ./shutsujin_departure.sh"
alias CSS="bash $ROOT_DIR/scripts/focus_agent_pane.sh shogun"
alias CSM="bash $ROOT_DIR/scripts/goza_no_ma.sh -t multiagent"

# Shogunate-specific view shortcuts.
alias cgo="bash $ROOT_DIR/scripts/goza_no_ma.sh"
alias csa="bash $ROOT_DIR/scripts/goza_no_ma.sh -t ashigaru"
alias cgn="bash $ROOT_DIR/scripts/focus_agent_pane.sh gunkan"
alias csg="bash $ROOT_DIR/scripts/focus_agent_pane.sh gunshi"
alias csk="bash $ROOT_DIR/scripts/focus_agent_pane.sh karo"
alias ckr="bash $ROOT_DIR/scripts/focus_agent_pane.sh karo"
alias cma="bash $ROOT_DIR/scripts/goza_no_ma.sh -t multiagent"
alias CGO="bash $ROOT_DIR/scripts/goza_no_ma.sh"
alias CSA="bash $ROOT_DIR/scripts/goza_no_ma.sh -t ashigaru"
alias CGN="bash $ROOT_DIR/scripts/focus_agent_pane.sh gunkan"
alias CSG="bash $ROOT_DIR/scripts/focus_agent_pane.sh gunshi"
alias CSK="bash $ROOT_DIR/scripts/focus_agent_pane.sh karo"
alias CKR="bash $ROOT_DIR/scripts/focus_agent_pane.sh karo"
alias CMA="bash $ROOT_DIR/scripts/goza_no_ma.sh -t multiagent"
