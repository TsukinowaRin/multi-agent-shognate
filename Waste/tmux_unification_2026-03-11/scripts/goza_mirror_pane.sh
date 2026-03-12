#!/usr/bin/env bash
set -euo pipefail

TARGET="${1:-}"
LABEL="${2:-mirror}"
REFRESH_INTERVAL="${GOZA_REFRESH_INTERVAL:-1}"

if [[ -z "$TARGET" ]]; then
  echo "[ERROR] usage: goza_mirror_pane.sh <tmux-target> [label]" >&2
  exit 1
fi

if ! command -v tmux >/dev/null 2>&1; then
  echo "[ERROR] tmux が見つかりません。" >&2
  exit 1
fi

while true; do
  clear
  printf '[%s] %s\n\n' "$LABEL" "$TARGET"
  if tmux has-session -t "${TARGET%%:*}" 2>/dev/null; then
    tmux capture-pane -e -J -p -t "$TARGET" -S -200 2>/dev/null || printf '[WARN] capture-pane failed: %s\n' "$TARGET"
  else
    printf '[WAIT] target session is not ready: %s\n' "$TARGET"
  fi
  sleep "$REFRESH_INTERVAL"
done
