#!/usr/bin/env bash
set -euo pipefail

SESSION="${1:-goza-no-ma}"
WINDOW_TARGET="${SESSION}:overview"
WATCH_MODE="${2:-}"

if ! command -v tmux >/dev/null 2>&1; then
  exit 0
fi

update_target() {
  local pane_id target_agent
  pane_id="$(tmux display-message -p -t "$WINDOW_TARGET" "#{pane_id}" 2>/dev/null || true)"
  if [[ -z "$pane_id" ]]; then
    return 0
  fi

  target_agent="$(tmux show-options -p -t "$pane_id" -v @goza_target 2>/dev/null | tr -d '\r' | head -n1)"
  if [[ -n "$target_agent" ]]; then
    tmux set-option -w -t "$WINDOW_TARGET" @goza_active_target "$target_agent" >/dev/null 2>&1 || true
  fi
}

if [[ "$WATCH_MODE" == "--watch" ]]; then
  while tmux has-session -t "$SESSION" 2>/dev/null; do
    update_target
    sleep 1
  done
  exit 0
fi

update_target
