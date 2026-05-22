#!/usr/bin/env bash
set -euo pipefail

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
cd "$ROOT_DIR"

GOZA_SESSION="${GOZA_SESSION_NAME:-goza-no-ma}"
GOZA_WINDOW="${GOZA_WINDOW_NAME:-overview}"
SETUP_ONLY=false
ENSURE_BACKEND=false
REFRESH=false
NO_ATTACH=false
TEMPLATE="${GOZA_TEMPLATE:-goza}"  # goza | shogun | gunshi | karo | multiagent | ashigaru
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
  -t, --template     レイアウトテンプレートを指定
                     goza       = 御座の間（全エージェント）
                     shogun     = 将軍のみ
                     gunshi     = 軍師のみ
                     karo       = 家老のみ
                     multiagent = 家老＋足軽
                     ashigaru   = 足軽のみ
  -h, --help         このヘルプ

Aliases (shell):
  cgo  → bash scripts/goza_no_ma.sh
  css  → bash scripts/focus_agent_pane.sh shogun
  csg  → bash scripts/focus_agent_pane.sh gunshi
  csm  → bash scripts/focus_agent_pane.sh karo
  csa  → bash scripts/goza_no_ma.sh -t ashigaru
  cma  → bash scripts/goza_no_ma.sh -t multiagent
USAGE
}

while [[ $# -gt 0 ]]; do
  case "$1" in
    -s|--setup-only) SETUP_ONLY=true; ENSURE_BACKEND=true; shift ;;
    --ensure-backend) ENSURE_BACKEND=true; shift ;;
    --refresh) REFRESH=true; ENSURE_BACKEND=true; shift ;;
    --no-attach) NO_ATTACH=true; shift ;;
    --view-only) shift ;;
    -t|--template)
      shift
      TEMPLATE="${1:-goza}"
      shift
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

# ═══════════════════════════════════════════════════════════
# Helper: attach or switch to a target
# ═══════════════════════════════════════════════════════════
attach_target() {
  local target="$1"
  if [[ "$NO_ATTACH" == true ]]; then
    echo "[INFO] 対象 session を確認しました: ${target}"
    return 0
  fi
  if [[ -n "${TMUX:-}" ]]; then
    tmux switch-client -t "$target"
  else
    TMUX= tmux attach-session -t "$target"
  fi
}

# ═══════════════════════════════════════════════════════════
# Helper: focus pane by @agent_id within a session:window
# ═══════════════════════════════════════════════════════════
focus_agent_in_window() {
  local session="$1"
  local window="$2"
  local agent_id="$3"
  local target_pane=""

  while IFS= read -r pane; do
    [[ -n "$pane" ]] || continue
    local pane_agent
    pane_agent="$(tmux show-options -p -t "$pane" -v @agent_id 2>/dev/null | tr -d '\r' | head -n1)"
    if [[ "$pane_agent" == "$agent_id" ]]; then
      target_pane="$pane"
      break
    fi
  done < <(tmux list-panes -t "${session}:${window}" -F '#{pane_id}' 2>/dev/null || true)

  if [[ -z "$target_pane" ]]; then
    echo "[WARN] agent pane not found: $agent_id in ${session}:${window}" >&2
    return 1
  fi

  tmux select-window -t "${session}:${window}" >/dev/null 2>&1 || true
  tmux select-pane -t "$target_pane" >/dev/null 2>&1 || true
  attach_target "$session"
}

# ═══════════════════════════════════════════════════════════
# Helper: create or focus ashigaru-only window
# ═══════════════════════════════════════════════════════════
focus_ashigaru_only() {
  local ashigaru_window="ashigaru"

  # If ashigaru window already exists, just switch to it
  if tmux list-windows -t "$GOZA_SESSION" -F '#{window_name}' 2>/dev/null | grep -Fxq "$ashigaru_window"; then
    tmux select-window -t "${GOZA_SESSION}:${ashigaru_window}" >/dev/null 2>&1 || true
    attach_target "$GOZA_SESSION"
    return 0
  fi

  # Create new window with ashigaru panes only
  tmux new-window -d -t "$GOZA_SESSION" -n "$ashigaru_window" 2>/dev/null || true

  local ashigaru_panes=()
  while IFS= read -r pane; do
    [[ -n "$pane" ]] || continue
    local pane_agent
    pane_agent="$(tmux show-options -p -t "$pane" -v @agent_id 2>/dev/null | tr -d '\r' | head -n1)"
    if [[ "$pane_agent" =~ ^ashigaru[0-9]+$ ]]; then
      ashigaru_panes+=("$pane_agent")
    fi
  done < <(tmux list-panes -t "${GOZA_SESSION}:${GOZA_WINDOW}" -F '#{pane_id}' 2>/dev/null || true)

  if [[ ${#ashigaru_panes[@]} -eq 0 ]]; then
    echo "[WARN] 足軽 pane が見つかりません" >&2
    return 1
  fi

  # Link panes: first pane is already there, split for remaining
  local first_pane
  first_pane="$(tmux display-message -p -t "${GOZA_SESSION}:${ashigaru_window}" '#{pane_id}')"
  tmux set-option -p -t "$first_pane" @agent_id "${ashigaru_panes[0]}" >/dev/null 2>&1 || true
  tmux select-pane -t "$first_pane" -T "${ashigaru_panes[0]}" >/dev/null 2>&1 || true

  local prev_pane="$first_pane"
  for ((i=1; i<${#ashigaru_panes[@]}; i++)); do
    local new_pane
    new_pane="$(tmux split-window -h -t "$prev_pane" -P -F '#{pane_id}')"
    tmux set-option -p -t "$new_pane" @agent_id "${ashigaru_panes[$i]}" >/dev/null 2>&1 || true
    tmux select-pane -t "$new_pane" -T "${ashigaru_panes[$i]}" >/dev/null 2>&1 || true
    prev_pane="$new_pane"
  done

  tmux select-layout -t "${GOZA_SESSION}:${ashigaru_window}" tiled >/dev/null 2>&1 || true
  tmux select-window -t "${GOZA_SESSION}:${ashigaru_window}" >/dev/null 2>&1 || true
  attach_target "$GOZA_SESSION"
}

# ═══════════════════════════════════════════════════════════
# Main logic
# ═══════════════════════════════════════════════════════════

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

case "$TEMPLATE" in
  shogun)
    if tmux has-session -t "shogun" 2>/dev/null; then
      attach_target "shogun"
    else
      focus_agent_in_window "$GOZA_SESSION" "$GOZA_WINDOW" "shogun"
    fi
    ;;
  gunshi)
    if tmux has-session -t "gunshi" 2>/dev/null; then
      attach_target "gunshi"
    else
      focus_agent_in_window "$GOZA_SESSION" "$GOZA_WINDOW" "gunshi"
    fi
    ;;
  karo)
    focus_agent_in_window "$GOZA_SESSION" "$GOZA_WINDOW" "karo"
    ;;
  multiagent)
    if tmux has-session -t "multiagent" 2>/dev/null; then
      attach_target "multiagent"
    else
      echo "[WARN] multiagent session が見つかりません。御座の間の家老ペインにフォーカスします。" >&2
      focus_agent_in_window "$GOZA_SESSION" "$GOZA_WINDOW" "karo"
    fi
    ;;
  ashigaru)
    focus_ashigaru_only
    ;;
  goza|all|default|*)
    attach_target "$GOZA_SESSION"
    ;;
esac
