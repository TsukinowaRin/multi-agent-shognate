#!/usr/bin/env bash
set -euo pipefail

SESSION="${1:-}"
ROOT_DIR="${2:-}"

if [[ -z "$SESSION" || -z "$ROOT_DIR" ]]; then
  echo "[ERROR] usage: bootstrap_goza_view.sh <session> <root_dir>" >&2
  exit 1
fi

if ! command -v tmux >/dev/null 2>&1; then
  exit 0
fi

if ! tmux has-session -t "$SESSION" 2>/dev/null; then
  exit 0
fi

bootstrapped="$(tmux show-options -t "$SESSION" -vq @goza_bootstrapped 2>/dev/null || echo 0)"
if [[ "$bootstrapped" == "1" ]]; then
  exit 0
fi

tmux_attach_session_cmd() {
  local session="$1"
  printf 'cd %q && TMUX= tmux attach-session -t %q || (echo %q; exec bash)' \
    "$ROOT_DIR" "$session" "[WARN] attach失敗: $session"
}

tmux respawn-pane -k -t "$SESSION":overview.0 "$(tmux_attach_session_cmd shogun)"
tmux respawn-pane -k -t "$SESSION":overview.1 "$(tmux_attach_session_cmd gunshi)"
tmux respawn-pane -k -t "$SESSION":overview.2 "$(tmux_attach_session_cmd multiagent)"
tmux select-pane -t "$SESSION":overview.0 -T "shogun" >/dev/null 2>&1 || true
tmux select-pane -t "$SESSION":overview.1 -T "gunshi" >/dev/null 2>&1 || true
tmux select-pane -t "$SESSION":overview.2 -T "multiagent" >/dev/null 2>&1 || true
tmux set-option -t "$SESSION" @goza_bootstrapped 1 >/dev/null 2>&1 || true
