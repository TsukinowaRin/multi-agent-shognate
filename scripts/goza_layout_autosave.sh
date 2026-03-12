#!/usr/bin/env bash
set -euo pipefail

SESSION="${1:-}"
LAYOUT_FILE="${2:-}"
INTERVAL="${GOZA_LAYOUT_AUTOSAVE_INTERVAL:-1}"

if [[ -z "$SESSION" || -z "$LAYOUT_FILE" ]]; then
  echo "[ERROR] usage: goza_layout_autosave.sh <session> <layout-file>" >&2
  exit 1
fi

if ! command -v tmux >/dev/null 2>&1; then
  echo "[ERROR] tmux が見つかりません。" >&2
  exit 1
fi

window_target="${SESSION}:overview"
last_layout=""
last_count=""

while tmux has-session -t "$SESSION" 2>/dev/null; do
  pane_count="$(tmux list-panes -t "$window_target" 2>/dev/null | wc -l | tr -d '[:space:]')"
  layout="$(tmux display-message -p -t "$window_target" "#{window_layout}" 2>/dev/null || true)"

  if [[ -n "$pane_count" && -n "$layout" ]] && { [[ "$layout" != "$last_layout" ]] || [[ "$pane_count" != "$last_count" ]]; }; then
    mkdir -p "$(dirname "$LAYOUT_FILE")"
    printf '%s\t%s\n' "$pane_count" "$layout" > "$LAYOUT_FILE"
    last_layout="$layout"
    last_count="$pane_count"
  fi

  sleep "$INTERVAL"
done
