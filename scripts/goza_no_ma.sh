#!/usr/bin/env bash
set -euo pipefail

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
cd "$ROOT_DIR"

GOZA_SESSION="${GOZA_SESSION_NAME:-goza-no-ma}"
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
  --ensure-backend   御座の間 session が無ければ出陣してから開く
  --refresh          御座の間を再出陣して作り直す
  --no-attach        attach/switch せず存在確認だけ行う
  --view-only        互換オプション（現行では既定と同じ）
  -h, --help         このヘルプ
USAGE
}

while [[ $# -gt 0 ]]; do
  case "$1" in
    -s|--setup-only) SETUP_ONLY=true; ENSURE_BACKEND=true; shift ;;
    --ensure-backend) ENSURE_BACKEND=true; shift ;;
    --refresh) REFRESH=true; ENSURE_BACKEND=true; shift ;;
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

if [[ "$REFRESH" == true ]]; then
  tmux kill-session -t "$GOZA_SESSION" 2>/dev/null || true
fi

if ! tmux has-session -t "$GOZA_SESSION" 2>/dev/null; then
  if [[ "$ENSURE_BACKEND" != true ]]; then
    echo "[ERROR] ${GOZA_SESSION} session が存在しません。" >&2
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

if [[ "$NO_ATTACH" == true ]]; then
  echo "[INFO] 御座の間 session を確認しました: ${GOZA_SESSION}"
  echo "       attach: tmux attach -t ${GOZA_SESSION}"
  exit 0
fi

if [[ -n "${TMUX:-}" ]]; then
  tmux switch-client -t "$GOZA_SESSION"
else
  TMUX= tmux attach-session -t "$GOZA_SESSION"
fi
