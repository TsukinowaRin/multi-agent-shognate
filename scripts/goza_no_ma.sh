#!/usr/bin/env bash
set -euo pipefail

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
cd "$ROOT_DIR"

VIEW_SESSION="${VIEW_SESSION:-goza-no-ma}"
VIEW_WIDTH="${VIEW_WIDTH:-220}"
VIEW_HEIGHT="${VIEW_HEIGHT:-60}"
SETUP_ONLY=false
VIEW_ONLY=false
NO_ATTACH=false
PASS_THROUGH=()

backend_sessions_ready() {
  local session
  for session in shogun gunshi multiagent; do
    if ! tmux has-session -t "$session" 2>/dev/null; then
      return 1
    fi
  done
  return 0
}

usage() {
  cat <<'USAGE'
Usage:
  bash scripts/goza_no_ma.sh [options] [-- <shutsujin_departure.sh options>]

Options:
  -s, --setup-only   バックエンドを setup-only で起動（CLI未起動）
  --view-only        バックエンド起動をスキップし、御座の間だけ開く
  --no-attach        tmux へ attach せず、ビュー作成だけ行う
  --session NAME     御座の間 session 名（default: goza-no-ma）
  -h, --help         このヘルプ
USAGE
}

while [[ $# -gt 0 ]]; do
  case "$1" in
    -s|--setup-only) SETUP_ONLY=true; shift ;;
    --view-only) VIEW_ONLY=true; shift ;;
    --no-attach) NO_ATTACH=true; shift ;;
    --session)
      if [[ -n "${2:-}" && "${2:-}" != -* ]]; then
        VIEW_SESSION="$2"
        shift 2
      else
        echo "[ERROR] --session には名前を指定してください" >&2
        exit 1
      fi
      ;;
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

if [[ "$VIEW_ONLY" != true ]] || ! backend_sessions_ready; then
  START_ARGS=("${PASS_THROUGH[@]}")
  if [[ "$SETUP_ONLY" = true ]]; then
    START_ARGS=("-s" "${START_ARGS[@]}")
  fi
  if [[ "$VIEW_ONLY" = true ]]; then
    echo "[INFO] backend session が不足しているため、shutsujin_departure.sh を起動します"
  fi
  set +e
  bash "$ROOT_DIR/shutsujin_departure.sh" "${START_ARGS[@]}"
  _rc=$?
  set -e
  if [[ "$_rc" -ne 0 ]]; then
    echo "[WARN] shutsujin_departure.sh exited with code $_rc (continuing to view setup)" >&2
  fi
fi

for session in shogun gunshi multiagent; do
  if ! tmux has-session -t "$session" 2>/dev/null; then
    echo "[ERROR] $session セッションが存在しません。" >&2
    echo "        先に: bash shutsujin_departure.sh -s" >&2
    exit 1
  fi
done

tmux_attach_session_cmd() {
  local session="$1"
  printf 'cd %q && while ! stty size >/dev/null 2>&1; do sleep 0.1; done && TMUX= tmux attach-session -t %q || (echo %q; exec bash)' \
    "$ROOT_DIR" "$session" "[WARN] attach失敗: $session"
}

placeholder_cmd() {
  printf 'cd %q && printf %q && exec bash' \
    "$ROOT_DIR" "[INFO] attach後に御座の間を初期化します\n"
}

create_goza_session() {
  local session="$1"
  local placeholder bootstrap_cmd right_cols lower_rows
  placeholder="$(placeholder_cmd)"
  bootstrap_cmd="$(printf 'bash %q %q %q' "$ROOT_DIR/scripts/bootstrap_goza_view.sh" "$session" "$ROOT_DIR")"
  right_cols=$(( VIEW_WIDTH * 36 / 100 ))
  if [[ "$right_cols" -lt 40 ]]; then
    right_cols=40
  fi
  lower_rows=$(( VIEW_HEIGHT * 58 / 100 ))
  if [[ "$lower_rows" -lt 12 ]]; then
    lower_rows=12
  fi

  tmux new-session -d -x "$VIEW_WIDTH" -y "$VIEW_HEIGHT" -s "$session" -n overview "$placeholder"
  tmux split-window -h -l "$right_cols" -t "$session":overview "$placeholder"
  tmux split-window -v -l "$lower_rows" -t "$session":overview.1 "$placeholder"
  tmux select-layout -t "$session":overview main-vertical >/dev/null 2>&1 || true
  tmux set-window-option -t "$session":overview main-pane-width 64% >/dev/null 2>&1 || true
  tmux select-pane -t "$session":overview.0 -T "shogun" >/dev/null 2>&1 || true
  tmux select-pane -t "$session":overview.1 -T "gunshi" >/dev/null 2>&1 || true
  tmux select-pane -t "$session":overview.2 -T "multiagent" >/dev/null 2>&1 || true
  tmux set-window-option -t "$session":overview synchronize-panes off >/dev/null 2>&1 || true
  tmux set-option -t "$session":overview mouse on >/dev/null 2>&1 || true
  tmux set-option -t "$session" @goza_bootstrapped 0 >/dev/null 2>&1 || true
  tmux set-hook -t "$session" client-attached "run-shell '$bootstrap_cmd'" >/dev/null 2>&1 || true
  tmux select-pane -t "$session":overview.0 >/dev/null 2>&1 || true
}

if ! tmux has-session -t "$VIEW_SESSION" 2>/dev/null; then
  create_goza_session "$VIEW_SESSION"
else
  tmux select-window -t "$VIEW_SESSION":overview >/dev/null 2>&1 || true
  tmux select-pane -t "$VIEW_SESSION":overview.0 >/dev/null 2>&1 || true
fi

if [[ "$NO_ATTACH" = true ]]; then
  echo "[INFO] 御座の間 session ready: $VIEW_SESSION"
  echo "       attach: tmux attach -t $VIEW_SESSION"
  exit 0
fi

TMUX= tmux attach -t "$VIEW_SESSION"
