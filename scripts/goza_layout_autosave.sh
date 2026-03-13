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
signature_file="${GOZA_SIGNATURE_FILE:-}"

collect_signature() {
  local pane_id=""
  local agent_id=""
  local agents=()

  while IFS= read -r pane_id; do
    [ -n "$pane_id" ] || continue
    agent_id="$(tmux show-options -p -t "$pane_id" -v @agent_id 2>/dev/null | tr -d '\r' | head -n1)"
    [ -n "$agent_id" ] || continue
    agents+=("$agent_id")
  done < <(tmux list-panes -s -t "$SESSION" -F "#{pane_id}" 2>/dev/null || true)

  if [ "${#agents[@]}" -eq 0 ]; then
    return 0
  fi
  printf '%s\n' "${agents[@]}" | awk 'NF' | sort -V | paste -sd, -
}

while tmux has-session -t "$SESSION" 2>/dev/null; do
  pane_count="$(tmux list-panes -t "$window_target" 2>/dev/null | wc -l | tr -d '[:space:]')"
  layout="$(tmux display-message -p -t "$window_target" "#{window_layout}" 2>/dev/null || true)"
  signature="$(collect_signature)"

  if [[ -n "$pane_count" && -n "$layout" ]] && { [[ "$layout" != "$last_layout" ]] || [[ "$pane_count" != "$last_count" ]]; }; then
    mkdir -p "$(dirname "$LAYOUT_FILE")"
    printf '%s\t%s\t%s\n' "$pane_count" "$signature" "$layout" > "$LAYOUT_FILE"
    if [[ -n "$signature_file" ]]; then
      mkdir -p "$(dirname "$signature_file")"
      printf '%s\n' "$signature" > "$signature_file"
    fi
    last_layout="$layout"
    last_count="$pane_count"
  fi

  sleep "$INTERVAL"
done
