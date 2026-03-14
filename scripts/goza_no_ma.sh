#!/usr/bin/env bash
set -euo pipefail

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
cd "$ROOT_DIR"

GOZA_SESSION="${GOZA_SESSION_NAME:-goza-no-ma}"
TMUX_VIEW_WIDTH="${TMUX_VIEW_WIDTH:-200}"
TMUX_VIEW_HEIGHT="${TMUX_VIEW_HEIGHT:-60}"
SETUP_ONLY=false
ENSURE_BACKEND=false
REFRESH=false
NO_ATTACH=false
PASS_THROUGH=()

usage() {
  cat <<'USAGE'
Usage:
  bash scripts/goza_no_ma.sh [options] [-- <shutsujin_departure.sh options>]

Options:
  -s, --setup-only   backend を setup-only で起動してから御座の間を開く
  --ensure-backend   backend が無ければ出陣してから御座の間を開く
  --refresh          御座の間 view session を再生成する
  --no-attach        attach/switch せず存在確認のみ行う
  --view-only        互換オプション。backend 起動を行わない
  -h, --help         このヘルプ
USAGE
}

while [[ $# -gt 0 ]]; do
  case "$1" in
    -s|--setup-only) SETUP_ONLY=true; ENSURE_BACKEND=true; shift ;;
    --ensure-backend) ENSURE_BACKEND=true; shift ;;
    --refresh) REFRESH=true; shift ;;
    --no-attach) NO_ATTACH=true; shift ;;
    --view-only) shift ;;
    --)
      shift
      while [[ $# -gt 0 ]]; do PASS_THROUGH+=("$1"); shift; done
      ;;
    -h|--help) usage; exit 0 ;;
    *) PASS_THROUGH+=("$1"); shift ;;
  esac
done

if ! command -v tmux >/dev/null 2>&1; then
  echo "[ERROR] tmux が見つかりません。" >&2
  exit 1
fi

backend_ready() {
  tmux has-session -t shogun 2>/dev/null && tmux has-session -t multiagent 2>/dev/null
}

tmux_attach_session_cmd() {
  local session="$1"
  printf 'cd %q && TMUX= tmux attach-session -t %q || (echo %q; exec bash)' "$ROOT_DIR" "$session" "[WARN] attach失敗: $session"
}

create_goza_view() {
  tmux new-session -d -x "$TMUX_VIEW_WIDTH" -y "$TMUX_VIEW_HEIGHT" -s "$GOZA_SESSION" -n overview "$(tmux_attach_session_cmd shogun)"
  local right
  local right_cols gunshi_rows
  right_cols=$(( TMUX_VIEW_WIDTH * 42 / 100 ))
  (( right_cols < 50 )) && right_cols=50
  right="$(tmux split-window -h -l "$right_cols" -t "$GOZA_SESSION":overview -P -F '#{pane_id}' "$(tmux_attach_session_cmd multiagent)")"
  if tmux has-session -t gunshi 2>/dev/null; then
    gunshi_rows=$(( TMUX_VIEW_HEIGHT * 18 / 100 ))
    (( gunshi_rows < 10 )) && gunshi_rows=10
    tmux split-window -v -l "$gunshi_rows" -t "$right" "$(tmux_attach_session_cmd gunshi)" >/dev/null
    tmux select-pane -t "$GOZA_SESSION":overview.0 -T shogun >/dev/null 2>&1 || true
    tmux select-pane -t "$GOZA_SESSION":overview.1 -T multiagent >/dev/null 2>&1 || true
    tmux select-pane -t "$GOZA_SESSION":overview.2 -T gunshi >/dev/null 2>&1 || true
  else
    tmux select-pane -t "$GOZA_SESSION":overview.0 -T shogun >/dev/null 2>&1 || true
    tmux select-pane -t "$GOZA_SESSION":overview.1 -T multiagent >/dev/null 2>&1 || true
  fi
  tmux select-layout -t "$GOZA_SESSION":overview main-vertical >/dev/null 2>&1 || true
  tmux set-window-option -t "$GOZA_SESSION":overview main-pane-width 58% >/dev/null 2>&1 || true
}

if [[ "$REFRESH" == true ]]; then
  tmux kill-session -t "$GOZA_SESSION" 2>/dev/null || true
fi

if ! backend_ready; then
  if [[ "$ENSURE_BACKEND" != true ]]; then
    echo "[ERROR] shogun / multiagent backend が存在しません。" >&2
    echo "        先に: bash shutsujin_departure.sh" >&2
    echo "        あるいは: bash scripts/goza_no_ma.sh --ensure-backend" >&2
    exit 1
  fi
  START_ARGS=("${PASS_THROUGH[@]}")
  if [[ "$SETUP_ONLY" == true ]]; then
    START_ARGS=("-s" "${START_ARGS[@]}")
  fi
  bash "$ROOT_DIR/shutsujin_departure.sh" "${START_ARGS[@]}"
fi

if ! tmux has-session -t "$GOZA_SESSION" 2>/dev/null; then
  create_goza_view
fi

if [[ "$NO_ATTACH" == true ]]; then
  echo "[INFO] 御座の間 view session を確認しました: $GOZA_SESSION"
  echo "       attach: tmux attach -t $GOZA_SESSION"
  exit 0
fi

if [[ -n "${TMUX:-}" ]]; then
  tmux switch-client -t "$GOZA_SESSION"
else
  TMUX= tmux attach-session -t "$GOZA_SESSION"
fi
