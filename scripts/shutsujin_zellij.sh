#!/usr/bin/env bash
# zellij deployment script (experimental but usable)
# Creates one zellij session per agent for deterministic external control.

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
cd "$SCRIPT_DIR"

log_info() { echo -e "\033[1;33m【報】\033[0m $1"; }
log_success() { echo -e "\033[1;32m【成】\033[0m $1"; }
log_war() { echo -e "\033[1;31m【戦】\033[0m $1"; }

SETUP_ONLY=false
CLEAN_MODE=false
SHOGUN_NO_THINKING=false
SILENT_MODE=false
SHELL_OVERRIDE=""

while [[ $# -gt 0 ]]; do
  case "$1" in
    -s|--setup-only) SETUP_ONLY=true; shift ;;
    -c|--clean) CLEAN_MODE=true; shift ;;
    --shogun-no-thinking) SHOGUN_NO_THINKING=true; shift ;;
    -S|--silent) SILENT_MODE=true; shift ;;
    -shell|--shell)
      if [[ -n "${2:-}" && "${2:-}" != -* ]]; then
        SHELL_OVERRIDE="$2"
        shift 2
      else
        echo "エラー: -shell オプションには bash または zsh を指定してください" >&2
        exit 1
      fi
      ;;
    -h|--help)
      cat << 'USAGE'
zellij モード出陣スクリプト

Usage:
  bash scripts/shutsujin_zellij.sh [options]

Options:
  -s, --setup-only         セッションのみ作成（CLI起動なし）
  -c, --clean              queue/dashboardをクリーン初期化
  --shogun-no-thinking     shogunがclaude時のみMAX_THINKING_TOKENS=0
  -S, --silent             DISPLAY_MODE=silent
  -shell, --shell <sh>     bash or zsh
USAGE
      exit 0
      ;;
    *)
      echo "不明なオプション: $1" >&2
      exit 1
      ;;
  esac
done

if ! command -v zellij >/dev/null 2>&1; then
  echo "[ERROR] zellij not found. Install zellij first." >&2
  exit 1
fi

if [ -f "$SCRIPT_DIR/lib/cli_adapter.sh" ]; then
  # shellcheck source=/dev/null
  source "$SCRIPT_DIR/lib/cli_adapter.sh"
else
  echo "[ERROR] lib/cli_adapter.sh not found" >&2
  exit 1
fi

LANG_SETTING="ja"
SHELL_SETTING="bash"
if [ -f "$SCRIPT_DIR/config/settings.yaml" ]; then
  LANG_SETTING=$(grep "^language:" "$SCRIPT_DIR/config/settings.yaml" 2>/dev/null | awk '{print $2}' || echo "ja")
  SHELL_SETTING=$(grep "^shell:" "$SCRIPT_DIR/config/settings.yaml" 2>/dev/null | awk '{print $2}' || echo "bash")
fi
if [ -n "$SHELL_OVERRIDE" ]; then
  SHELL_SETTING="$SHELL_OVERRIDE"
fi

DISPLAY_MODE="shout"
if [ "$SILENT_MODE" = true ]; then
  DISPLAY_MODE="silent"
fi

# tmux版と同じ世界観で表示する（zellijモード用）
show_battle_cry() {
  clear
  echo ""
  echo -e "\033[1;31m╔══════════════════════════════════════════════════════════════════════════════════╗\033[0m"
  echo -e "\033[1;31m║\033[0m \033[1;33m███████╗██╗  ██╗██╗   ██╗████████╗███████╗██╗   ██╗     ██╗██╗███╗   ██╗\033[0m \033[1;31m║\033[0m"
  echo -e "\033[1;31m║\033[0m \033[1;33m██╔════╝██║  ██║██║   ██║╚══██╔══╝██╔════╝██║   ██║     ██║██║████╗  ██║\033[0m \033[1;31m║\033[0m"
  echo -e "\033[1;31m║\033[0m \033[1;33m███████╗███████║██║   ██║   ██║   ███████╗██║   ██║     ██║██║██╔██╗ ██║\033[0m \033[1;31m║\033[0m"
  echo -e "\033[1;31m║\033[0m \033[1;33m╚════██║██╔══██║██║   ██║   ██║   ╚════██║██║   ██║██   ██║██║██║╚██╗██║\033[0m \033[1;31m║\033[0m"
  echo -e "\033[1;31m║\033[0m \033[1;33m███████║██║  ██║╚██████╔╝   ██║   ███████║╚██████╔╝╚█████╔╝██║██║ ╚████║\033[0m \033[1;31m║\033[0m"
  echo -e "\033[1;31m║\033[0m \033[1;33m╚══════╝╚═╝  ╚═╝ ╚═════╝    ╚═╝   ╚══════╝ ╚═════╝  ╚════╝ ╚═╝╚═╝  ╚═══╝\033[0m \033[1;31m║\033[0m"
  echo -e "\033[1;31m╠══════════════════════════════════════════════════════════════════════════════════╣\033[0m"
  echo -e "\033[1;31m║\033[0m       \033[1;37m出陣じゃーーー！！！\033[0m    \033[1;36m⚔\033[0m    \033[1;35m天下布武！\033[0m                          \033[1;31m║\033[0m"
  echo -e "\033[1;31m╚══════════════════════════════════════════════════════════════════════════════════╝\033[0m"
  echo ""
}

role_tab_label() {
  local agent="$1"
  case "$agent" in
    shogun) echo "🟣 shogun" ;;
    karo) echo "🔵 karo" ;;
    ashigaru*) echo "🟤 ${agent}" ;;
    *) echo "$agent" ;;
  esac
}

show_battle_cry
echo -e "  \033[1;33m天下布武！陣立てを開始いたす\033[0m (Setting up the battlefield)"
echo ""

# 有効化する足軽リスト（デフォルト: ashigaru1 のみ）
ACTIVE_ASHIGARU=("ashigaru1")
if [ -f "$SCRIPT_DIR/config/settings.yaml" ]; then
  mapfile -t _active_from_yaml < <(python3 - << 'PY' 2>/dev/null || true
import yaml
from pathlib import Path
p = Path("config/settings.yaml")
cfg = yaml.safe_load(p.read_text(encoding="utf-8")) or {}
v = ((cfg.get("topology") or {}).get("active_ashigaru") or [])
out = []
for x in v:
    if isinstance(x, int):
        if 1 <= x <= 8:
            out.append(f"ashigaru{x}")
    elif isinstance(x, str):
        s = x.strip()
        if s.isdigit():
            i = int(s)
            if 1 <= i <= 8:
                out.append(f"ashigaru{i}")
        elif s.startswith("ashigaru") and s[8:].isdigit():
            i = int(s[8:])
            if 1 <= i <= 8:
                out.append(f"ashigaru{i}")
if out:
    for i in out:
        print(i)
PY
)
  if [ "${#_active_from_yaml[@]}" -gt 0 ]; then
    ACTIVE_ASHIGARU=("${_active_from_yaml[@]}")
  fi
fi

AGENTS=("shogun" "karo" "${ACTIVE_ASHIGARU[@]}")
ALL_MANAGED_AGENTS=("shogun" "karo" "ashigaru1" "ashigaru2" "ashigaru3" "ashigaru4" "ashigaru5" "ashigaru6" "ashigaru7" "ashigaru8")

mkdir -p queue/reports queue/tasks queue/inbox logs queue/runtime

if [ "$CLEAN_MODE" = true ]; then
  log_info "📜 クリーン初期化を実施"
  for i in {1..8}; do
    cat > "queue/tasks/ashigaru${i}.yaml" << TASK_EOF
# 足軽${i}専用タスクファイル
task:
  task_id: null
  parent_cmd: null
  description: null
  target_path: null
  status: idle
  timestamp: ""
TASK_EOF

    cat > "queue/reports/ashigaru${i}_report.yaml" << REPORT_EOF
worker_id: ashigaru${i}
task_id: null
timestamp: ""
status: idle
result: null
REPORT_EOF
  done

  cat > dashboard.md << 'DASHBOARD_EOF'
# dashboard

## 進行中
- なし

## 戦果
- なし

## 🚨 要対応
- なし
DASHBOARD_EOF
fi

for agent in "${AGENTS[@]}"; do
  [ -f "queue/inbox/${agent}.yaml" ] || echo "messages: []" > "queue/inbox/${agent}.yaml"
done

session_exists() {
  local session="$1"
  zellij list-sessions -n 2>/dev/null | awk '{print $1}' | grep -qx "$session"
}

is_selected_agent() {
  local name="$1"
  local agent
  for agent in "${AGENTS[@]}"; do
    if [ "$agent" = "$name" ]; then
      return 0
    fi
  done
  return 1
}

create_session() {
  local session="$1"
  if session_exists "$session"; then
    zellij delete-session "$session" --force >/dev/null 2>&1 || zellij kill-session "$session" >/dev/null 2>&1 || true
  fi

  if zellij attach --create-background "$session" >/dev/null 2>&1; then
    return 0
  fi
  if zellij attach --create-background --session "$session" >/dev/null 2>&1; then
    return 0
  fi

  echo "[ERROR] failed to create zellij session: $session" >&2
  return 1
}

send_line() {
  local session="$1"
  local text="$2"
  zellij -s "$session" action write-chars "$text" >/dev/null 2>&1 || return 1
  zellij -s "$session" action write 13 >/dev/null 2>&1 || return 1
}

log_war "⚔️ zellij セッションを構築中（1エージェント=1セッション）"
# 非アクティブ化された管理セッションは削除して配備一覧を一致させる
for stale in "${ALL_MANAGED_AGENTS[@]}"; do
  if ! is_selected_agent "$stale" && session_exists "$stale"; then
    zellij delete-session "$stale" --force >/dev/null 2>&1 || zellij kill-session "$stale" >/dev/null 2>&1 || true
  fi
done

for agent in "${AGENTS[@]}"; do
  create_session "$agent"
  zellij -s "$agent" action rename-tab "$(role_tab_label "$agent")" >/dev/null 2>&1 || true
  send_line "$agent" "cd \"$SCRIPT_DIR\" && export AGENT_ID=\"$agent\" && export DISPLAY_MODE=\"$DISPLAY_MODE\" && clear"
  log_info "  └─ $agent セッション作成"
done

if [ "$SETUP_ONLY" = false ]; then
  log_war "👑 全エージェントCLIを起動中"

  if ! get_first_available_cli >/dev/null 2>&1; then
    echo "[ERROR] No supported CLI found. Install one of: claude, codex, gemini, localapi, copilot, kimi" >&2
    exit 1
  fi

  : > queue/runtime/agent_cli.tsv
  for agent in "${AGENTS[@]}"; do
    cli_type=$(resolve_cli_type_for_agent "$agent")
    cli_cmd=$(build_cli_command_with_type "$agent" "$cli_type")

    if [ "$agent" = "shogun" ] && [ "$SHOGUN_NO_THINKING" = true ] && [ "$cli_type" = "claude" ]; then
      cli_cmd="MAX_THINKING_TOKENS=0 $cli_cmd"
    fi

    send_line "$agent" "$cli_cmd"
    printf "%s\t%s\n" "$agent" "$cli_type" >> queue/runtime/agent_cli.tsv
    log_info "  └─ $agent: $cli_type"
  done

  log_info "📬 inbox_watcher を起動中 (MUX_TYPE=zellij)"
  for agent in "${AGENTS[@]}"; do
    cli_type=$(awk -F '\t' -v a="$agent" '$1==a{print $2}' queue/runtime/agent_cli.tsv | tail -n1)
    if ! pgrep -f "scripts/inbox_watcher.sh ${agent} ${agent} .* zellij" >/dev/null 2>&1; then
      nohup env MUX_TYPE=zellij bash "$SCRIPT_DIR/scripts/inbox_watcher.sh" "$agent" "$agent" "$cli_type" "zellij" \
        >> "$SCRIPT_DIR/logs/inbox_watcher_${agent}.log" 2>&1 &
    fi
  done

  log_success "✅ zellij モードで起動完了"
else
  log_success "✅ セットアップのみ完了（CLI未起動）"
fi

echo ""
echo "接続方法（zellij）:"
echo "  zellij attach shogun"
echo "  zellij attach karo"
for a in "${ACTIVE_ASHIGARU[@]}"; do
  echo "  zellij attach $a"
done
echo ""
echo "現在のセッション一覧:"
zellij list-sessions -n || true
