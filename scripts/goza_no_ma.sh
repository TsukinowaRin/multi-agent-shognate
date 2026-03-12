#!/usr/bin/env bash
set -euo pipefail

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
cd "$ROOT_DIR"

VIEW_SESSION="${VIEW_SESSION:-goza-no-ma}"
VIEW_WIDTH="${VIEW_WIDTH:-220}"
VIEW_HEIGHT="${VIEW_HEIGHT:-60}"
GOZA_LAYOUT_FILE="${GOZA_LAYOUT_FILE:-$ROOT_DIR/queue/runtime/goza_layout.tsv}"
SETUP_ONLY=false
VIEW_ONLY=true
ENSURE_BACKEND=false
REFRESH_VIEW=false
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

discover_karo_target() {
  local target agent_id
  while IFS= read -r target; do
    [ -n "$target" ] || continue
    agent_id="$(tmux show-options -p -t "$target" -v @agent_id 2>/dev/null | tr -d '\r' | head -n1)"
    if [[ "$agent_id" =~ ^karo([0-9]+)?$ || "$agent_id" == "karo_gashira" ]]; then
      printf '%s\n' "$target"
      return 0
    fi
  done < <(tmux list-panes -t multiagent:agents -F '#{session_name}:#{window_name}.#{pane_index}' 2>/dev/null || true)
  return 1
}

discover_ashigaru_targets() {
  local target agent_id
  while IFS= read -r target; do
    [ -n "$target" ] || continue
    agent_id="$(tmux show-options -p -t "$target" -v @agent_id 2>/dev/null | tr -d '\r' | head -n1)"
    if [[ "$agent_id" =~ ^ashigaru[0-9]+$ ]]; then
      printf '%s\t%s\n' "$target" "$agent_id"
    fi
  done < <(tmux list-panes -t multiagent:agents -F '#{session_name}:#{window_name}.#{pane_index}' 2>/dev/null || true)
}

usage() {
  cat <<'USAGE'
Usage:
  bash scripts/goza_no_ma.sh [options] [-- <shutsujin_departure.sh options>]

Options:
  -s, --setup-only   バックエンドを setup-only で起動してから御座の間を開く
  --ensure-backend   backend session が無ければ起動してから御座の間を開く
  --view-only        backend を起動せず、既存 session だけで御座の間を開く（default）
  --refresh          既存の御座の間を破棄して再生成する
  --no-attach        tmux へ attach せず、ビュー作成だけ行う
  --session NAME     御座の間 session 名（default: goza-no-ma）
  -h, --help         このヘルプ
USAGE
}

while [[ $# -gt 0 ]]; do
  case "$1" in
    -s|--setup-only) SETUP_ONLY=true; ENSURE_BACKEND=true; VIEW_ONLY=false; shift ;;
    --ensure-backend) ENSURE_BACKEND=true; VIEW_ONLY=false; shift ;;
    --view-only) VIEW_ONLY=true; ENSURE_BACKEND=false; shift ;;
    --refresh) REFRESH_VIEW=true; shift ;;
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

if [[ "$ENSURE_BACKEND" = true ]]; then
  START_ARGS=("${PASS_THROUGH[@]}")
  if [[ "$SETUP_ONLY" = true ]]; then
    START_ARGS=("-s" "${START_ARGS[@]}")
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
    echo "        先に: bash shutsujin_departure.sh" >&2
    echo "        あるいは: bash scripts/goza_no_ma.sh --ensure-backend" >&2
    exit 1
  fi
done

if tmux has-session -t "$VIEW_SESSION" 2>/dev/null && [[ "$REFRESH_VIEW" != true ]]; then
  if [[ "$NO_ATTACH" = true ]]; then
    echo "[INFO] 既存の御座の間 session を再利用します: $VIEW_SESSION"
    echo "       attach: tmux attach -t $VIEW_SESSION"
    exit 0
  fi
  TMUX= tmux attach -t "$VIEW_SESSION"
  exit 0
fi

mirror_cmd() {
  local target="$1"
  local label="$2"
  printf 'cd %q && bash %q %q %q' \
    "$ROOT_DIR" "$ROOT_DIR/scripts/goza_mirror_pane.sh" "$target" "$label"
}

start_goza_layout_autosave() {
  local session="$1"
  mkdir -p "$ROOT_DIR/logs"
  pkill -f "scripts/goza_layout_autosave.sh ${session} " >/dev/null 2>&1 || true
  nohup bash "$ROOT_DIR/scripts/goza_layout_autosave.sh" "$session" "$GOZA_LAYOUT_FILE" \
    >> "$ROOT_DIR/logs/goza_layout_autosave.log" 2>&1 &
  disown
}

save_goza_layout() {
  local session="$1"
  local window_target="${session}:overview"
  local pane_count layout

  tmux has-session -t "$session" 2>/dev/null || return 0
  pane_count="$(tmux list-panes -t "$window_target" 2>/dev/null | wc -l | tr -d '[:space:]')"
  layout="$(tmux display-message -p -t "$window_target" "#{window_layout}" 2>/dev/null || true)"
  if [[ -n "$pane_count" && -n "$layout" ]]; then
    mkdir -p "$(dirname "$GOZA_LAYOUT_FILE")"
    printf '%s\t%s\n' "$pane_count" "$layout" > "$GOZA_LAYOUT_FILE"
  fi
}

restore_goza_layout_if_available() {
  local session="$1"
  local window_target="${session}:overview"
  local current_count saved_count saved_layout

  [[ -f "$GOZA_LAYOUT_FILE" ]] || return 0
  current_count="$(tmux list-panes -t "$window_target" 2>/dev/null | wc -l | tr -d '[:space:]')"
  IFS=$'\t' read -r saved_count saved_layout < "$GOZA_LAYOUT_FILE" || return 0
  [[ -n "$saved_count" && -n "$saved_layout" ]] || return 0
  [[ "$saved_count" = "$current_count" ]] || return 0
  tmux select-layout -t "$window_target" "$saved_layout" >/dev/null 2>&1 || true
}

create_goza_session() {
  local session="$1"
  local karo_target=""
  local ashigaru_targets=()
  local ashigaru_ids=()
  local line target agent_id
  local right_width gunshi_height ashigaru_top_height half_width

  right_width=$(( VIEW_WIDTH * 54 / 100 ))
  (( right_width < 60 )) && right_width=60
  (( right_width > VIEW_WIDTH - 40 )) && right_width=$(( VIEW_WIDTH - 40 ))

  gunshi_height=$(( VIEW_HEIGHT * 36 / 100 ))
  (( gunshi_height < 12 )) && gunshi_height=12
  (( gunshi_height > VIEW_HEIGHT - 12 )) && gunshi_height=$(( VIEW_HEIGHT - 12 ))

  ashigaru_top_height=$(( (VIEW_HEIGHT - gunshi_height) / 2 ))
  (( ashigaru_top_height < 8 )) && ashigaru_top_height=8

  half_width=$(( right_width / 2 ))
  (( half_width < 24 )) && half_width=24

  karo_target="$(discover_karo_target || true)"
  while IFS=$'\t' read -r target agent_id; do
    [[ -n "$target" && -n "$agent_id" ]] || continue
    ashigaru_targets+=("$target")
    ashigaru_ids+=("$agent_id")
  done < <(discover_ashigaru_targets)

  tmux new-session -d -x "$VIEW_WIDTH" -y "$VIEW_HEIGHT" -s "$session" -n overview "$(mirror_cmd "shogun:main" "shogun")"
  tmux split-window -h -l "$right_width" -t "$session":overview "$(mirror_cmd "${karo_target:-multiagent:agents.0}" "karo")"
  tmux split-window -v -l "$gunshi_height" -t "$session":overview.1 "$(mirror_cmd "gunshi:main" "gunshi")"

  if (( ${#ashigaru_targets[@]} > 0 )); then
    tmux split-window -h -l "$half_width" -t "$session":overview.2 "$(mirror_cmd "${ashigaru_targets[0]}" "${ashigaru_ids[0]}")"
    tmux select-pane -t "$session":overview.3 -T "${ashigaru_ids[0]}" >/dev/null 2>&1 || true

    if (( ${#ashigaru_targets[@]} > 1 )); then
      tmux split-window -v -l "$ashigaru_top_height" -t "$session":overview.3 "$(mirror_cmd "${ashigaru_targets[1]}" "${ashigaru_ids[1]}")"
      tmux select-pane -t "$session":overview.4 -T "${ashigaru_ids[1]}" >/dev/null 2>&1 || true
    fi

    if (( ${#ashigaru_targets[@]} > 2 )); then
      tmux split-window -h -l "$half_width" -t "$session":overview.3 "$(mirror_cmd "${ashigaru_targets[2]}" "${ashigaru_ids[2]}")"
      tmux select-pane -t "$session":overview.5 -T "${ashigaru_ids[2]}" >/dev/null 2>&1 || true
    fi

    if (( ${#ashigaru_targets[@]} > 3 )); then
      tmux split-window -h -l "$half_width" -t "$session":overview.4 "$(mirror_cmd "${ashigaru_targets[3]}" "${ashigaru_ids[3]}")"
      tmux select-pane -t "$session":overview.6 -T "${ashigaru_ids[3]}" >/dev/null 2>&1 || true
    fi
  fi

  tmux set-window-option -t "$session":overview synchronize-panes off >/dev/null 2>&1 || true
  tmux set-option -t "$session":overview mouse on >/dev/null 2>&1 || true
  tmux select-pane -t "$session":overview.0 >/dev/null 2>&1 || true
  tmux select-pane -t "$session":overview.0 -T "shogun" >/dev/null 2>&1 || true
  tmux select-pane -t "$session":overview.1 -T "karo" >/dev/null 2>&1 || true
  tmux select-pane -t "$session":overview.2 -T "gunshi" >/dev/null 2>&1 || true
  restore_goza_layout_if_available "$session"
}

if tmux has-session -t "$VIEW_SESSION" 2>/dev/null; then
  save_goza_layout "$VIEW_SESSION"
  pkill -f "scripts/goza_layout_autosave.sh ${VIEW_SESSION} " >/dev/null 2>&1 || true
  tmux kill-session -t "$VIEW_SESSION" >/dev/null 2>&1 || true
fi
create_goza_session "$VIEW_SESSION"
start_goza_layout_autosave "$VIEW_SESSION"

if [[ "$NO_ATTACH" = true ]]; then
  echo "[INFO] 御座の間 session ready: $VIEW_SESSION"
  echo "       attach: tmux attach -t $VIEW_SESSION"
  exit 0
fi

TMUX= tmux attach -t "$VIEW_SESSION"
