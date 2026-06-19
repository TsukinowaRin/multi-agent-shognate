#!/usr/bin/env bash
set -euo pipefail

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)"
cd "$ROOT_DIR"

GOZA_SESSION="${GOZA_SESSION_NAME:-${SHOGUNATE_SESSION_NAME:-shogunate}}"
LEGACY_GOZA_SESSION="${LEGACY_GOZA_SESSION_NAME:-goza-no-ma}"
GOZA_WINDOW="${GOZA_WINDOW_NAME:-goza}"
AGENT_ID="${1:-}"

if [[ -z "$AGENT_ID" ]]; then
  echo "Usage: bash shogunate_mod/view/focus_agent_pane.sh <agent_id>" >&2
  exit 1
fi

if ! command -v tmux >/dev/null 2>&1; then
  echo "[ERROR] tmux が見つかりません。" >&2
  exit 1
fi

if ! tmux has-session -t "$GOZA_SESSION" 2>/dev/null; then
  if [[ "$LEGACY_GOZA_SESSION" != "$GOZA_SESSION" ]] && tmux has-session -t "$LEGACY_GOZA_SESSION" 2>/dev/null; then
    GOZA_SESSION="$LEGACY_GOZA_SESSION"
    GOZA_WINDOW="${GOZA_WINDOW_NAME:-overview}"
  fi
fi

if ! tmux has-session -t "$GOZA_SESSION" 2>/dev/null; then
  echo "[ERROR] ${GOZA_SESSION} session が存在しません。先に bash shutsujin_departure.sh を実行してください。" >&2
  exit 1
fi

TARGET_PANE=""
while IFS= read -r pane; do
  [[ -n "$pane" ]] || continue
  pane_agent="$(tmux show-options -p -t "$pane" -v @agent_id 2>/dev/null | tr -d '\r' | head -n1)"
  if [[ "$pane_agent" == "$AGENT_ID" ]]; then
    TARGET_PANE="$pane"
    break
  fi
done < <(tmux list-panes -t "${GOZA_SESSION}:${GOZA_WINDOW}" -F '#{pane_id}' 2>/dev/null || true)

if [[ -z "$TARGET_PANE" ]]; then
  echo "[ERROR] agent pane unresolved: $AGENT_ID" >&2
  exit 1
fi

tmux select-window -t "${GOZA_SESSION}:${GOZA_WINDOW}" >/dev/null 2>&1 || true
tmux select-pane -t "$TARGET_PANE" >/dev/null 2>&1 || true

if [[ -n "${TMUX:-}" ]]; then
  tmux switch-client -t "$GOZA_SESSION"
else
  TMUX= tmux attach-session -t "$GOZA_SESSION"
fi
