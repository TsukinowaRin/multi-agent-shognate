#!/usr/bin/env bash
# WSL再起動後のワンコマンド起動 + 分割ビュー
# - バックエンド: zellij セッション群（shogun/karo/ashigaru*）
# - 表示: tmux の分割ペインで各 zellij session に attach

set -euo pipefail

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
cd "$ROOT_DIR"

VIEW_SESSION="${VIEW_SESSION:-goza-no-ma}"
SETUP_ONLY=false
VIEW_ONLY=false
NO_ATTACH=false
MUX_MODE="${MUX_MODE:-zellij}"
PASS_THROUGH=()

usage() {
  cat << 'USAGE'
Usage:
  bash scripts/goza_no_ma.sh [options] [-- <shutsujin_departure.sh options>]

Options:
  -s, --setup-only   バックエンドは setup-only で起動（CLI未起動）
  --view-only        バックエンド起動をスキップし、ビューのみ起動
  --no-attach        tmuxへattachせず、ビュー作成だけ行う（検証向け）
  --mux MODE         起動モードを指定（zellij|tmux, default: zellij）
  --session NAME     tmux ビューセッション名（default: goza-no-ma）
  -h, --help         このヘルプ

Examples:
  bash scripts/goza_no_ma.sh --mux zellij
  bash scripts/goza_no_ma.sh --mux tmux
  bash scripts/goza_no_ma.sh -s --mux zellij
  bash scripts/goza_no_ma.sh -- --shogun-no-thinking
USAGE
}

while [[ $# -gt 0 ]]; do
  case "$1" in
    -s|--setup-only)
      SETUP_ONLY=true
      shift
      ;;
    --view-only)
      VIEW_ONLY=true
      shift
      ;;
    --no-attach)
      NO_ATTACH=true
      shift
      ;;
    --mux)
      if [[ -n "${2:-}" && "${2:-}" != -* ]]; then
        MUX_MODE="$2"
        shift 2
      else
        echo "[ERROR] --mux には zellij または tmux を指定してください" >&2
        exit 1
      fi
      ;;
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
      while [[ $# -gt 0 ]]; do
        PASS_THROUGH+=("$1")
        shift
      done
      ;;
    -h|--help)
      usage
      exit 0
      ;;
    *)
      PASS_THROUGH+=("$1")
      shift
      ;;
  esac
done

if [[ "$MUX_MODE" != "zellij" && "$MUX_MODE" != "tmux" ]]; then
  echo "[ERROR] --mux は zellij または tmux を指定してください（指定値: $MUX_MODE）" >&2
  exit 1
fi

if ! command -v tmux >/dev/null 2>&1; then
  echo "[ERROR] tmux が見つかりません。ビュー作成に tmux が必要です。" >&2
  exit 1
fi
if [[ "$MUX_MODE" == "zellij" ]] && ! command -v zellij >/dev/null 2>&1; then
  echo "[ERROR] zellij が見つかりません。zellij モードでは zellij が必要です。" >&2
  exit 1
fi

if [[ "$VIEW_ONLY" != true ]]; then
  START_ARGS=("${PASS_THROUGH[@]}")
  if [[ "$SETUP_ONLY" = true ]]; then
    START_ARGS=("-s" "${START_ARGS[@]}")
  fi

  MAS_MULTIPLEXER="$MUX_MODE" bash "$ROOT_DIR/shutsujin_departure.sh" "${START_ARGS[@]}"
fi

if [[ "$MUX_MODE" == "tmux" ]]; then
  if [[ "$NO_ATTACH" = true ]]; then
    echo "[INFO] tmux mode started."
    echo "       attach shogun: tmux attach-session -t shogun"
    echo "       attach agents: tmux attach-session -t multiagent"
    exit 0
  fi
  tmux attach-session -t shogun
  exit 0
fi

role_border_color() {
  local role="$1"
  case "$role" in
    shogun) echo "colour54" ;;   # 紫
    karo) echo "colour19" ;;     # 紺
    ashigaru*) echo "colour94" ;;# 茶
    *) echo "colour248" ;;
  esac
}

apply_role_border_styles() {
  local pane
  local title
  local color

  tmux set-option -t "$VIEW_SESSION":agents pane-border-status top >/dev/null 2>&1 || true
  tmux set-option -t "$VIEW_SESSION":agents pane-border-format '#{pane_index}:#{pane_title}' >/dev/null 2>&1 || true

  while IFS= read -r pane; do
    title="$(tmux display-message -p -t "$pane" '#{pane_title}' 2>/dev/null || true)"
    color="$(role_border_color "$title")"
    tmux set-option -p -t "$pane" pane-border-style "fg=${color}" >/dev/null 2>&1 || true
    tmux set-option -p -t "$pane" pane-active-border-style "fg=${color}" >/dev/null 2>&1 || true
  done < <(tmux list-panes -t "$VIEW_SESSION":agents -F '#{pane_id}' 2>/dev/null || true)
}

mapfile -t AGENTS < <(python3 - << 'PY'
from pathlib import Path

try:
    import yaml
except Exception:
    print("shogun")
    print("karo")
    print("ashigaru1")
    raise SystemExit(0)

cfg = {}
p = Path("config/settings.yaml")
if p.exists():
    cfg = yaml.safe_load(p.read_text(encoding="utf-8")) or {}

active = (cfg.get("topology") or {}).get("active_ashigaru") or ["ashigaru1"]
normalized = []
for x in active:
    if isinstance(x, int):
        if 1 <= x <= 8:
            normalized.append(f"ashigaru{x}")
        continue
    s = str(x).strip()
    if s.isdigit():
        i = int(s)
        if 1 <= i <= 8:
            normalized.append(f"ashigaru{i}")
    elif s.startswith("ashigaru") and s[8:].isdigit():
        i = int(s[8:])
        if 1 <= i <= 8:
            normalized.append(f"ashigaru{i}")

if not normalized:
    normalized = ["ashigaru1"]

agents = ["shogun", "karo"] + normalized
for a in agents:
    print(a)
PY
)

# 実在する zellij セッションのみ表示対象にする
zellij_sessions="$(zellij list-sessions -n 2>/dev/null || true)"
VISIBLE=()
for a in "${AGENTS[@]}"; do
  if echo "$zellij_sessions" | awk '{print $1}' | grep -qx "$a"; then
    VISIBLE+=("$a")
  fi
done

if [[ ${#VISIBLE[@]} -eq 0 ]]; then
  echo "[ERROR] attach可能な zellij session が見つかりませんでした。" >&2
  echo "        先に: bash shutsujin_departure.sh" >&2
  exit 1
fi

if tmux has-session -t "$VIEW_SESSION" 2>/dev/null; then
  # 既存ビューでも毎回スタイルを再適用する
  apply_role_border_styles
  if [[ "$NO_ATTACH" = true ]]; then
    echo "[INFO] tmux session already exists: $VIEW_SESSION"
    echo "       attach: tmux attach -t $VIEW_SESSION"
    exit 0
  fi
  tmux attach -t "$VIEW_SESSION"
  exit 0
fi

attach_cmd() {
  local agent="$1"
  printf 'cd "%s" && zellij attach %q || (echo "[WARN] attach失敗: %s"; exec bash)' "$ROOT_DIR" "$agent" "$agent"
}

# 1ペイン目
first="${VISIBLE[0]}"
tmux new-session -d -s "$VIEW_SESSION" -n agents "$(attach_cmd "$first")"
tmux select-pane -t "$VIEW_SESSION":agents.0 -T "$first"

# 2ペイン目以降
for i in "${!VISIBLE[@]}"; do
  if [[ "$i" -eq 0 ]]; then
    continue
  fi
  agent="${VISIBLE[$i]}"
  tmux split-window -t "$VIEW_SESSION":agents -v "$(attach_cmd "$agent")"
  tmux select-layout -t "$VIEW_SESSION":agents tiled >/dev/null 2>&1 || true
  tmux select-pane -t "$VIEW_SESSION":agents."$i" -T "$agent" >/dev/null 2>&1 || true
done

# 見やすさ調整
apply_role_border_styles

tmux display-message -t "$VIEW_SESSION":agents "Attached agents: ${VISIBLE[*]}"
if [[ "$NO_ATTACH" = true ]]; then
  echo "[INFO] view session created: $VIEW_SESSION"
  echo "       attach: tmux attach -t $VIEW_SESSION"
  exit 0
fi
tmux attach -t "$VIEW_SESSION"
