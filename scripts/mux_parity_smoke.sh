#!/usr/bin/env bash
# tmux / zellij parity smoke test
# - setup-only 起動を両モードで実行
# - inbox と owner map の基本整合を確認

set -euo pipefail

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
cd "$ROOT_DIR"

RUN_TMUX=1
RUN_ZELLIJ=1
DRY_RUN=0
SETUP_ARGS=(-s)

usage() {
  cat <<'USAGE'
Usage:
  bash scripts/mux_parity_smoke.sh [options]

Options:
  --tmux-only      tmux のみ検証
  --zellij-only    zellij のみ検証
  --dry-run        実行せずコマンド表示のみ
  --clean          shutsujin_departure.sh に -c を追加
  -h, --help       ヘルプ
USAGE
}

while [[ $# -gt 0 ]]; do
  case "$1" in
    --tmux-only) RUN_TMUX=1; RUN_ZELLIJ=0; shift ;;
    --zellij-only) RUN_TMUX=0; RUN_ZELLIJ=1; shift ;;
    --dry-run) DRY_RUN=1; shift ;;
    --clean) SETUP_ARGS=(-s -c); shift ;;
    -h|--help) usage; exit 0 ;;
    *)
      echo "[ERROR] Unknown option: $1" >&2
      usage >&2
      exit 1
      ;;
  esac
done

mkdir -p logs queue/runtime queue/inbox

run_or_print() {
  if [[ "$DRY_RUN" -eq 1 ]]; then
    echo "[DRY-RUN] $*"
    return 0
  fi
  "$@"
}

run_setup_mode() {
  local mode="$1"
  local log_file="logs/mux_parity_${mode}.log"

  if [[ "$DRY_RUN" -eq 1 ]]; then
    echo "[DRY-RUN] MAS_MULTIPLEXER=${mode} bash shutsujin_departure.sh ${SETUP_ARGS[*]} > ${log_file}"
    return 0
  fi

  if ! command -v "$mode" >/dev/null 2>&1; then
    echo "[WARN] ${mode} command not found. skip."
    return 2
  fi

  echo "[INFO] setup-only start: ${mode}"

  if MAS_MULTIPLEXER="$mode" bash shutsujin_departure.sh "${SETUP_ARGS[@]}" >"$log_file" 2>&1; then
    :
  else
    echo "[ERROR] ${mode} setup-only failed. log: ${log_file}" >&2
    tail -n 40 "$log_file" >&2 || true
    return 1
  fi

  if [[ ! -d "queue/inbox" ]]; then
    echo "[ERROR] queue/inbox is not a directory after ${mode} setup" >&2
    return 1
  fi

  if [[ ! -f "queue/ntfy_inbox.yaml" ]]; then
    echo "[ERROR] queue/ntfy_inbox.yaml missing after ${mode} setup" >&2
    return 1
  fi

  if [[ -f "queue/runtime/ashigaru_owner.tsv" ]]; then
    cp -f "queue/runtime/ashigaru_owner.tsv" "queue/runtime/ashigaru_owner.${mode}.tsv"
  else
    echo "[ERROR] queue/runtime/ashigaru_owner.tsv missing after ${mode} setup" >&2
    return 1
  fi

  echo "[OK] ${mode} setup-only succeeded"
  return 0
}

tmux_rc=3
zellij_rc=3

if [[ "$RUN_TMUX" -eq 1 ]]; then
  run_setup_mode "tmux" || tmux_rc=$?
fi
if [[ "$RUN_ZELLIJ" -eq 1 ]]; then
  run_setup_mode "zellij" || zellij_rc=$?
fi

if [[ "$DRY_RUN" -eq 1 ]]; then
  echo "[OK] dry-run complete"
  exit 0
fi

if [[ "$RUN_TMUX" -eq 1 && "$tmux_rc" -ne 0 ]]; then
  exit 1
fi
if [[ "$RUN_ZELLIJ" -eq 1 && "$zellij_rc" -ne 0 ]]; then
  exit 1
fi

if [[ "$RUN_TMUX" -eq 1 && "$RUN_ZELLIJ" -eq 1 ]]; then
  if cmp -s queue/runtime/ashigaru_owner.tmux.tsv queue/runtime/ashigaru_owner.zellij.tsv; then
    echo "[OK] owner map parity: tmux == zellij"
  else
    echo "[ERROR] owner map mismatch between tmux and zellij" >&2
    echo "--- tmux ---" >&2
    cat queue/runtime/ashigaru_owner.tmux.tsv >&2
    echo "--- zellij ---" >&2
    cat queue/runtime/ashigaru_owner.zellij.tsv >&2
    exit 1
  fi
fi

echo "[OK] mux parity smoke test passed"
