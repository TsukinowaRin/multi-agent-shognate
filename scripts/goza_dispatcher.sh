#!/usr/bin/env bash
set -euo pipefail

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
cd "$ROOT_DIR"

GOZA_SESSION="${1:-goza-no-ma}"
CURRENT_TARGET="${GOZA_DEFAULT_TARGET:-shogun}"

if ! command -v tmux >/dev/null 2>&1; then
  echo "[ERROR] tmux が見つかりません。" >&2
  exit 1
fi

resolve_multiagent_agent() {
  local wanted="$1"
  local pane_target agent_id
  if tmux has-session -t "$GOZA_SESSION" 2>/dev/null; then
    while IFS= read -r pane_target; do
      [ -n "$pane_target" ] || continue
      agent_id="$(tmux show-options -p -t "$pane_target" -v @agent_id 2>/dev/null | tr -d '\r' | head -n1)"
      if [[ "$agent_id" == "$wanted" ]]; then
        printf '%s\n' "$pane_target"
        return 0
      fi
    done < <(tmux list-panes -t "$GOZA_SESSION" -F '#{pane_id}' 2>/dev/null || true)
    return 1
  fi
  while IFS= read -r pane_target; do
    [ -n "$pane_target" ] || continue
    agent_id="$(tmux show-options -p -t "$pane_target" -v @agent_id 2>/dev/null | tr -d '\r' | head -n1)"
    if [[ "$agent_id" == "$wanted" ]]; then
      printf '%s\n' "$pane_target"
      return 0
    fi
  done < <(tmux list-panes -t multiagent:agents -F '#{session_name}:#{window_name}.#{pane_index}' 2>/dev/null || true)
  return 1
}

resolve_target() {
  local wanted="$1"
  case "$wanted" in
    shogun|gunshi|karo|karo_gashira|karo[0-9]*|ashigaru[0-9]*) resolve_multiagent_agent "$wanted" ;;
    *) return 1 ;;
  esac
}

read_session_target() {
  local target
  target="$(tmux show-options -w -t "${GOZA_SESSION}:overview" -v @goza_active_target 2>/dev/null | tr -d '\r' | head -n1 || true)"
  if [[ -n "$target" ]]; then
    CURRENT_TARGET="$target"
  fi
}

persist_session_target() {
  local target="$1"
  tmux set-option -w -t "${GOZA_SESSION}:overview" @goza_active_target "$target" >/dev/null 2>&1 || true
}

print_help() {
  cat <<'EOF'
[御座の間 使者]
  使い方:
    /target <agent_id>    送信先を変更
    /show                 現在の送信先を表示
    /agents               送信可能な agent_id 一覧を表示
    /help                 このヘルプ
    <agent_id>: <message> その場で指定先へ送信
    <message>             現在の送信先へ送信

  例:
    /target shogun
    shogun: docs を確認せよ
    ashigaru1: queue を確認せよ
EOF
}

list_agents() {
  local pane_target agent_id
  printf '送信可能:'
  if tmux has-session -t "$GOZA_SESSION" 2>/dev/null; then
    while IFS= read -r pane_target; do
      [ -n "$pane_target" ] || continue
      agent_id="$(tmux show-options -p -t "$pane_target" -v @agent_id 2>/dev/null | tr -d '\r' | head -n1)"
      [[ -n "$agent_id" ]] || continue
      printf ' %s' "$agent_id"
    done < <(tmux list-panes -t "$GOZA_SESSION" -F '#{pane_id}' 2>/dev/null || true)
    printf '\n'
    return 0
  fi
  while IFS= read -r pane_target; do
    [ -n "$pane_target" ] || continue
    agent_id="$(tmux show-options -p -t "$pane_target" -v @agent_id 2>/dev/null | tr -d '\r' | head -n1)"
    [[ -n "$agent_id" ]] || continue
    printf ' %s' "$agent_id"
  done < <(tmux list-panes -t multiagent:agents -F '#{session_name}:#{window_name}.#{pane_index}' 2>/dev/null || true)
  printf '\n'
}

send_line_to_target() {
  local target_agent="$1"
  local message="$2"
  local pane_target
  pane_target="$(resolve_target "$target_agent" || true)"
  if [[ -z "$pane_target" ]]; then
    printf '[WARN] target unresolved: %s\n' "$target_agent"
    return 1
  fi
  tmux send-keys -t "$pane_target" -l -- "$message"
  tmux send-keys -t "$pane_target" Enter
  printf '[SEND] %s -> %s\n' "$target_agent" "$message"
}

print_help
read_session_target
printf '[INFO] 現在の送信先: %s\n' "$CURRENT_TARGET"

while true; do
  read_session_target
  printf '[%s] > ' "$CURRENT_TARGET"
  if ! IFS= read -r line; then
    printf '\n[INFO] 使者を終了します\n'
    exit 0
  fi
  line="${line//$'\r'/}"
  [[ -n "$line" ]] || continue

  case "$line" in
    /help)
      print_help
      continue
      ;;
    /show)
      read_session_target
      printf '[INFO] 現在の送信先: %s\n' "$CURRENT_TARGET"
      continue
      ;;
    /agents)
      list_agents
      continue
      ;;
    /target\ *)
      candidate="${line#"/target "}"
      if resolve_target "$candidate" >/dev/null 2>&1; then
        CURRENT_TARGET="$candidate"
        persist_session_target "$CURRENT_TARGET"
        printf '[INFO] 送信先を変更: %s\n' "$CURRENT_TARGET"
      else
        printf '[WARN] target unresolved: %s\n' "$candidate"
      fi
      continue
      ;;
  esac

  if [[ "$line" =~ ^([a-zA-Z0-9_]+):[[:space:]]*(.+)$ ]]; then
    persist_session_target "${BASH_REMATCH[1]}"
    send_line_to_target "${BASH_REMATCH[1]}" "${BASH_REMATCH[2]}" || true
    continue
  fi

  send_line_to_target "$CURRENT_TARGET" "$line" || true
done
