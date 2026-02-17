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

TOPOLOGY_ADAPTER_LOADED=false
if [ -f "$SCRIPT_DIR/lib/topology_adapter.sh" ]; then
  # shellcheck source=/dev/null
  source "$SCRIPT_DIR/lib/topology_adapter.sh"
  TOPOLOGY_ADAPTER_LOADED=true
fi

if [ -f "$SCRIPT_DIR/lib/inbox_path.sh" ]; then
  # shellcheck source=/dev/null
  source "$SCRIPT_DIR/lib/inbox_path.sh"
fi

ensure_generated_instructions() {
  local ensure_script="$SCRIPT_DIR/scripts/ensure_generated_instructions.sh"
  if [ ! -x "$ensure_script" ]; then
    log_info "⚠️  指示書再生成スクリプトが見つからないため、既存 generated を使用します"
    return 0
  fi
  if ! bash "$ensure_script"; then
    log_info "⚠️  指示書再生成に失敗しました。既存 generated を使用して継続します"
  fi
}

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
seen = set()
for x in v:
    if isinstance(x, int):
        if x >= 1:
            name = f"ashigaru{x}"
            if name not in seen:
                out.append(name)
                seen.add(name)
    elif isinstance(x, str):
        s = x.strip()
        if s.isdigit():
            i = int(s)
            if i >= 1:
                name = f"ashigaru{i}"
                if name not in seen:
                    out.append(name)
                    seen.add(name)
        elif s.startswith("ashigaru") and s[8:].isdigit() and int(s[8:]) >= 1:
            if s not in seen:
                out.append(s)
                seen.add(s)
if out:
    for i in out:
        print(i)
PY
)
  if [ "${#_active_from_yaml[@]}" -gt 0 ]; then
    ACTIVE_ASHIGARU=("${_active_from_yaml[@]}")
  fi
fi
ACTIVE_ASHIGARU_COUNT=${#ACTIVE_ASHIGARU[@]}
KARO_AGENTS=("karo")
if [ "$TOPOLOGY_ADAPTER_LOADED" = true ]; then
  mapfile -t _karo_from_topology < <(topology_resolve_karo_agents "${ACTIVE_ASHIGARU[@]}" 2>/dev/null || true)
  if [ "${#_karo_from_topology[@]}" -gt 0 ]; then
    KARO_AGENTS=("${_karo_from_topology[@]}")
  fi
fi

KNOWN_ASHIGARU=("${ACTIVE_ASHIGARU[@]}")
mapfile -t _known_from_files < <(python3 - << 'PY' 2>/dev/null || true
import re
from pathlib import Path
ids = set()
for p in Path("queue/tasks").glob("ashigaru*.yaml"):
    m = re.fullmatch(r"ashigaru([1-9][0-9]*)\.yaml", p.name)
    if m:
        ids.add(int(m.group(1)))
for p in Path("queue/reports").glob("ashigaru*_report.yaml"):
    m = re.fullmatch(r"ashigaru([1-9][0-9]*)_report\.yaml", p.name)
    if m:
        ids.add(int(m.group(1)))
for p in Path("queue/inbox").glob("ashigaru*.yaml"):
    m = re.fullmatch(r"ashigaru([1-9][0-9]*)\.yaml", p.name)
    if m:
        ids.add(int(m.group(1)))
for i in sorted(ids):
    print(f"ashigaru{i}")
PY
)
for _a in "${_known_from_files[@]}"; do
  _found=0
  for _b in "${KNOWN_ASHIGARU[@]}"; do
    if [ "$_a" = "$_b" ]; then
      _found=1
      break
    fi
  done
  if [ "$_found" -eq 0 ]; then
    KNOWN_ASHIGARU+=("$_a")
  fi
done
if [ "${#KNOWN_ASHIGARU[@]}" -eq 0 ]; then
  KNOWN_ASHIGARU=("ashigaru1")
fi

# tmux版と同じ世界観で表示する（zellijモード用）
show_battle_cry() {
  if [ -t 1 ]; then
    clear || true
  else
    echo ""
  fi
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

  echo -e "\033[1;34m  ╔═════════════════════════════════════════════════════════════════════════════╗\033[0m"
  echo -e "\033[1;34m  ║\033[0m                    \033[1;37m【 足 軽 隊 列 ・ ${ACTIVE_ASHIGARU_COUNT} 名 配 備 】\033[0m                      \033[1;34m║\033[0m"
  echo -e "\033[1;34m  ╚═════════════════════════════════════════════════════════════════════════════╝\033[0m"
  render_ashigaru_ascii "$ACTIVE_ASHIGARU_COUNT"
  echo -e "                    \033[1;36m「「「 はっ！！ 出陣いたす！！ 」」」\033[0m"
  echo ""
  echo -e "\033[1;33m  ┏━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━┓\033[0m"
  echo -e "\033[1;33m  ┃\033[0m  \033[1;37m🏯 multi-agent-shogun\033[0m  〜 \033[1;36m戦国マルチエージェント統率システム\033[0m 〜           \033[1;33m┃\033[0m"
  echo -e "\033[1;33m  ┃\033[0m                                                                           \033[1;33m┃\033[0m"
  echo -e "\033[1;33m  ┃\033[0m    \033[1;35m将軍\033[0m: プロジェクト統括    \033[1;31m家老\033[0m: タスク管理    \033[1;34m足軽\033[0m: 実働部隊×${ACTIVE_ASHIGARU_COUNT}      \033[1;33m┃\033[0m"
  echo -e "\033[1;33m  ┗━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━┛\033[0m"
  echo ""
}

render_ashigaru_ascii() {
  local count="$1"
  local i
  local from=1
  local to=0
  local row1="" row2="" row3="" row4="" row5="" row6="" row7=""
  local per_row=8

  if ! [[ "$count" =~ ^[0-9]+$ ]]; then
    count=1
  fi
  if [ "$count" -lt 1 ]; then
    count=1
  fi
  while [ "$from" -le "$count" ]; do
    to=$((from + per_row - 1))
    if [ "$to" -gt "$count" ]; then
      to="$count"
    fi
    row1="" row2="" row3="" row4="" row5="" row6="" row7=""
    for ((i=from; i<=to; i++)); do
      row1+="       /\\  "
      row2+="      /||\\ "
      row3+="     /_||\\ "
      row4+="       ||  "
      row5+="      /||\\ "
      row6+="      /  \\ "
      row7+="     [足${i}] "
    done

    echo ""
    echo "$row1"
    echo "$row2"
    echo "$row3"
    echo "$row4"
    echo "$row5"
    echo "$row6"
    echo "$row7"
    echo ""
    from=$((to + 1))
  done
}

role_tab_label() {
  local agent="$1"
  case "$agent" in
    shogun) echo "🟣 shogun" ;;
    karo|karo[1-9]*|karo_gashira) echo "🔵 ${agent}" ;;
    ashigaru*) echo "🟤 ${agent}" ;;
    *) echo "$agent" ;;
  esac
}

show_battle_cry
echo -e "  \033[1;33m天下布武！陣立てを開始いたす\033[0m (Setting up the battlefield)"
echo ""

AGENTS=("shogun" "gunshi" "${KARO_AGENTS[@]}" "${ACTIVE_ASHIGARU[@]}")

mkdir -p queue/reports queue/tasks logs queue/runtime
if declare -F ensure_local_inbox_dir >/dev/null 2>&1; then
  ensure_local_inbox_dir "queue/inbox"
else
  mkdir -p queue/inbox
fi
if [ "$TOPOLOGY_ADAPTER_LOADED" = true ]; then
  build_even_ownership_map "$SCRIPT_DIR/queue/runtime/ashigaru_owner.tsv" "${ACTIVE_ASHIGARU[@]}"
else
  : > "$SCRIPT_DIR/queue/runtime/ashigaru_owner.tsv"
  for _agent in "${ACTIVE_ASHIGARU[@]}"; do
    printf "%s\tkaro\n" "$_agent" >> "$SCRIPT_DIR/queue/runtime/ashigaru_owner.tsv"
  done
fi

if [ "$CLEAN_MODE" = true ]; then
  log_info "📜 クリーン初期化を実施"
  for _agent in "${KNOWN_ASHIGARU[@]}"; do
    _num="${_agent#ashigaru}"
    cat > "queue/tasks/${_agent}.yaml" << TASK_EOF
# 足軽${_num}専用タスクファイル
task:
  task_id: null
  parent_cmd: null
  description: null
  target_path: null
  status: idle
  timestamp: ""
TASK_EOF

    cat > "queue/reports/${_agent}_report.yaml" << REPORT_EOF
worker_id: ${_agent}
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

# tmuxモードと同じく ntfy inbox を常に確保（clean時は初期化）
if [ "$CLEAN_MODE" = true ]; then
  echo "inbox:" > queue/ntfy_inbox.yaml
else
  [ -f queue/ntfy_inbox.yaml ] || echo "inbox:" > queue/ntfy_inbox.yaml
fi

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
  # セッション存在チェック（存在しないセッションへの誤送信を防止）
  if ! session_exists "$session"; then
    echo "[WARN] send_line: session '$session' does not exist, skipping" >&2
    return 1
  fi
  zellij -s "$session" action write-chars "$text" >/dev/null 2>&1 || return 1
  if zellij -s "$session" action write 13 >/dev/null 2>&1; then
    # 送信完了を待機（zellijのバッファ処理完了を待つ）
    sleep 0.5
    return 0
  fi
  if zellij -s "$session" action write 10 >/dev/null 2>&1; then
    # 送信完了を待機
    sleep 0.5
    return 0
  fi
  zellij -s "$session" action write-chars $'\n' >/dev/null 2>&1 || return 1
  # 送信完了を待機
  sleep 0.5
}

# ブートストラップメッセージを事前にファイルへ書き出す
# 各エージェントが自分専用のファイルを読むことで誤送信を根本的に排除
generate_bootstrap_file() {
  local agent_id="$1"
  local cli_type="$2"
  local bootstrap_dir="$SCRIPT_DIR/queue/runtime"
  local bootstrap_file="$bootstrap_dir/bootstrap_${agent_id}.md"
  local role_instruction_file=""
  local optimized_instruction_file=""
  local lang_rule="" event_rule="" report_rule="" linkage_rule=""

  role_instruction_file="$(get_role_instruction_file "$agent_id" 2>/dev/null || true)"
  optimized_instruction_file="$(get_instruction_file "$agent_id" "$cli_type" 2>/dev/null || true)"

  if [ -z "$role_instruction_file" ]; then
    case "$agent_id" in
      shogun) role_instruction_file="instructions/shogun.md" ;;
      gunshi) role_instruction_file="instructions/gunshi.md" ;;
      karo|karo[1-9]*|karo_gashira) role_instruction_file="instructions/karo.md" ;;
      ashigaru*) role_instruction_file="instructions/ashigaru.md" ;;
      *) role_instruction_file="AGENTS.md" ;;
    esac
  fi

  if [ -z "$optimized_instruction_file" ] || [ ! -f "$SCRIPT_DIR/$optimized_instruction_file" ]; then
    optimized_instruction_file="$role_instruction_file"
  fi

  linkage_rule="$(role_linkage_directive "$agent_id")"
  lang_rule="$(language_directive)"
  event_rule="$(event_driven_directive "$agent_id")"
  report_rule="$(reporting_chain_directive "$agent_id")"

  local startup_msg
  if [ "$optimized_instruction_file" != "$role_instruction_file" ]; then
    startup_msg="【初動命令】あなたは${agent_id}。まず 'ready:${agent_id}' を1行で即時送信し、次に AGENTS.md と ${role_instruction_file} を読み、続けて ${optimized_instruction_file} を読んで ${cli_type} 向け差分を適用せよ。${lang_rule} ${event_rule} ${linkage_rule} ${report_rule} 準備が整ったら未読inbox監視へ戻れ。"
  else
    startup_msg="【初動命令】あなたは${agent_id}。まず 'ready:${agent_id}' を1行で即時送信し、次に AGENTS.md と ${role_instruction_file} を読み、役割・口調・禁止事項を適用せよ。${lang_rule} ${event_rule} ${linkage_rule} ${report_rule} 準備が整ったら未読inbox監視へ戻れ。"
  fi

  echo "$startup_msg" > "$bootstrap_file"
}

# エージェントのCLIが起動済みかをセッション画面ダンプで確認
wait_for_cli_ready() {
  local session="$1"
  local cli_type="${2:-claude}"
  local max_wait="${3:-15}"
  local i
  local tmp_dump="/tmp/zellij_ready_${session}.txt"
  local ready_pattern=""

  case "$cli_type" in
    claude)
      ready_pattern='(claude code|claude|for shortcuts|/model)'
      ;;
    codex)
      ready_pattern='(openai codex|codex|for shortcuts|context left|/model)'
      ;;
    gemini)
      ready_pattern='(gemini|trust this folder|keep trying|type your message|yolo mode)'
      ;;
    copilot)
      ready_pattern='(copilot|github copilot|for shortcuts|/model)'
      ;;
    kimi)
      ready_pattern='(kimi|moonshot|for shortcuts|/model)'
      ;;
    localapi)
      ready_pattern='(localapi|ready:|api)'
      ;;
    *)
      ready_pattern='(claude|codex|gemini|copilot|kimi|localapi|ready:)'
      ;;
  esac

  for ((i=0; i<max_wait; i++)); do
    if ! session_exists "$session"; then
      rm -f "$tmp_dump"
      return 1
    fi
    if zellij -s "$session" action dump-screen "$tmp_dump" 2>/dev/null; then
      if grep -qiE "$ready_pattern" "$tmp_dump" 2>/dev/null; then
        rm -f "$tmp_dump"
        return 0
      fi
    fi
    sleep 1
  done
  rm -f "$tmp_dump"
  return 1
}

# 初動ブートストラップをファイルベースで配信（レースコンディション排除）
# send_line ではなく、短い「ファイル読み込み」指示のみ送信
deliver_bootstrap_zellij() {
  local agent_id="$1"
  local cli_type="${2:-claude}"
  local bootstrap_file="queue/runtime/bootstrap_${agent_id}.md"

  if [ ! -f "$SCRIPT_DIR/$bootstrap_file" ]; then
    echo "[WARN] bootstrap file not found for $agent_id: $bootstrap_file" >&2
    return 1
  fi

  if ! session_exists "$agent_id"; then
    echo "[WARN] session '$agent_id' not found, skipping bootstrap delivery" >&2
    return 1
  fi

  # ブートストラップファイルの内容を読み込んで送信
  local msg
  msg="$(cat "$SCRIPT_DIR/$bootstrap_file")"
  if ! send_line "$agent_id" "$msg"; then
    echo "[WARN] failed to deliver bootstrap to $agent_id, retrying..." >&2
    sleep 2
    send_line "$agent_id" "$msg" || echo "[ERROR] bootstrap delivery failed for $agent_id ($cli_type) after retry" >&2
  fi

  # 送信完了を待機（混線防止のため、次のエージェントへ進む前にバッファ処理完了を待つ）
  sleep 1
}

role_linkage_directive() {
  local agent_id="$1"
  case "$agent_id" in
    shogun)
      echo "連携順序: 殿の指示を受けたら、必ず『将軍→家老→足軽』で委譲せよ。家老への委譲は queue/shogun_to_karo.yaml 更新 + inbox通知を使い、足軽へ直接命令してはならない。"
      ;;
    gunshi)
      echo "連携順序: 軍師は家老から戦略分析・設計・評価の任務を受け、分析結果を queue/reports/gunshi_report.yaml に書いて家老へ返せ。実装は行わず、足軽が迷わぬための地図を描け。"
      ;;
    karo|karo[1-9]*|karo_gashira)
      echo "連携順序: 家老は担当足軽のみを管理せよ。家老同士の直接連携は禁止。割当は queue/runtime/ashigaru_owner.tsv を正本として従うこと。"
      ;;
    ashigaru*)
      echo "連携順序: 足軽は自分の task YAML のみ処理し、完了後は queue/runtime/ashigaru_owner.tsv で定義された担当家老へ報告せよ。非担当家老への報告は禁止。"
      ;;
    *)
      echo "連携順序: 将軍→家老→足軽の指揮系統を順守せよ。"
      ;;
  esac
}

language_directive() {
  if [ "${LANG_SETTING:-ja}" = "ja" ]; then
    echo "言語規則: 以後の応答は日本語（戦国口調）で統一せよ。"
  else
    echo "Language rule: Follow system language '${LANG_SETTING}' for all outputs (include all agent communication)."
  fi
}

event_driven_directive() {
  local agent_id="$1"
  case "$agent_id" in
    shogun)
      echo "イベント駆動規則: 家老へ委譲したら即ターンを閉じ、殿の次入力を待て。自分で実装作業に入るな。"
      ;;
    gunshi)
      echo "イベント駆動規則: 家老からの分析依頼を受けたら深く考察し、完了後は報告して待機へ戻れ。ポーリング禁止。"
      ;;
    karo|karo[1-9]*|karo_gashira|ashigaru*)
      echo "イベント駆動規則: ポーリング禁止。inboxイベント起点でタスク処理し、未読処理後は待機へ戻れ。"
      ;;
    *)
      echo "イベント駆動規則: inboxイベント起点で処理し、完了後は待機へ戻れ。"
      ;;
  esac
}

reporting_chain_directive() {
  local agent_id="$1"
  case "$agent_id" in
    shogun)
      echo "報告規則: 家老の報告を受けて殿へ要約報告せよ。家老の問題を検知したら即改善指示を返せ。"
      ;;
    gunshi)
      echo "報告規則: 分析・設計・評価の結果は queue/reports/gunshi_report.yaml に書き、依頼元の家老へ inbox 通知で返せ。将軍・人間へ直接報告しない。"
      ;;
    karo|karo[1-9]*|karo_gashira)
      echo "報告規則: タスク完了時は将軍へ要約を返し、人間へ直接報告しない。"
      ;;
    ashigaru*)
      echo "報告規則: 完了報告は必ず家老へ返す。将軍・人間へ直接報告しない。"
      ;;
    *)
      echo "報告規則: 指揮系統（将軍→家老→足軽）を守って報告せよ。"
      ;;
  esac
}

ensure_generated_instructions

log_war "⚔️ zellij セッションを構築中（1エージェント=1セッション）"
# 非アクティブ化された管理セッションは削除して配備一覧を一致させる
mapfile -t _managed_sessions < <(zellij list-sessions -n 2>/dev/null | awk '{print $1}' | grep -E '^(shogun|gunshi|karo([1-9][0-9]*)?|karo_gashira|ashigaru[1-9][0-9]*)$' || true)
for stale in "${_managed_sessions[@]}"; do
  if ! is_selected_agent "$stale"; then
    zellij delete-session "$stale" --force >/dev/null 2>&1 || zellij kill-session "$stale" >/dev/null 2>&1 || true
  fi
done

for agent in "${AGENTS[@]}"; do
  create_session "$agent"
  zellij -s "$agent" action rename-tab "$(role_tab_label "$agent")" >/dev/null 2>&1 || true
  if ! send_line "$agent" "cd \"$SCRIPT_DIR\" && export AGENT_ID=\"$agent\" && export DISPLAY_MODE=\"$DISPLAY_MODE\" && clear"; then
    echo "[WARN] failed to send bootstrap command to $agent" >&2
  fi
  log_info "  └─ $agent セッション作成"
done

if [ "$SETUP_ONLY" = false ]; then
  log_war "👑 全エージェントCLIを起動中"

  if ! get_first_available_cli >/dev/null 2>&1; then
    echo "[ERROR] No supported CLI found. Install one of: claude, codex, gemini, localapi, copilot, kimi" >&2
    exit 1
  fi

  : > queue/runtime/agent_cli.tsv

  # Phase 1: ブートストラップファイルを事前生成（CLIへの送信より前に全エージェント分書き出す）
  log_info "📝 ブートストラップファイルを事前生成中"
  for agent in "${AGENTS[@]}"; do
    cli_type=$(resolve_cli_type_for_agent "$agent")
    printf "%s\t%s\n" "$agent" "$cli_type" >> queue/runtime/agent_cli.tsv
    generate_bootstrap_file "$agent" "$cli_type"
  done

  BOOTSTRAP_AGENT_GAP="${MAS_ZELLIJ_BOOTSTRAP_GAP:-5}"
  if ! [[ "$BOOTSTRAP_AGENT_GAP" =~ ^[0-9]+$ ]]; then
    BOOTSTRAP_AGENT_GAP=5
  fi

  # Phase 2: エージェント単位で「CLI起動→ready確認→初動命令送信」を順次実行
  log_info "📜 初動命令をエージェント単位で順次配信中（起動確認つき）"
  for agent in "${AGENTS[@]}"; do
    cli_type="$(awk -F '\t' -v a="$agent" '$1==a{print $2}' queue/runtime/agent_cli.tsv | tail -n1)"
    cli_cmd=$(build_cli_command_with_type "$agent" "$cli_type")

    if [ "$agent" = "shogun" ] && [ "$SHOGUN_NO_THINKING" = true ] && [ "$cli_type" = "claude" ]; then
      cli_cmd="MAX_THINKING_TOKENS=0 $cli_cmd"
    fi

    if ! send_line "$agent" "$cli_cmd"; then
      echo "[WARN] failed to send CLI launch command to $agent ($cli_type)" >&2
    fi
    if ! wait_for_cli_ready "$agent" "$cli_type" 25; then
      echo "[WARN] CLI not ready in session '$agent' after timeout, sending bootstrap anyway" >&2
    fi
    deliver_bootstrap_zellij "$agent" "$cli_type"
    log_info "  └─ $agent: $cli_type（初動配信完了）"
    if [ "$BOOTSTRAP_AGENT_GAP" -gt 0 ]; then
      sleep "$BOOTSTRAP_AGENT_GAP"
    fi
  done
  log_info "📜 初動命令の配信完了"

  if command -v inotifywait >/dev/null 2>&1; then
    log_info "📬 inbox_watcher を起動中 (MUX_TYPE=zellij)"
    for agent in "${AGENTS[@]}"; do
      cli_type=$(awk -F '\t' -v a="$agent" '$1==a{print $2}' queue/runtime/agent_cli.tsv | tail -n1)
      if ! pgrep -f "scripts/inbox_watcher.sh ${agent} ${agent} .* zellij" >/dev/null 2>&1; then
        nohup env ASW_DISABLE_ESCALATION=1 ASW_PROCESS_TIMEOUT=0 ASW_DISABLE_NORMAL_NUDGE=0 \
          MUX_TYPE=zellij bash "$SCRIPT_DIR/scripts/inbox_watcher.sh" "$agent" "$agent" "$cli_type" "zellij" \
          >> "$SCRIPT_DIR/logs/inbox_watcher_${agent}.log" 2>&1 &
      fi
    done
  else
    log_info "⚠️  inotifywait 未導入のため inbox_watcher はスキップ（sudo apt install -y inotify-tools）"
  fi

  if [ -x "$SCRIPT_DIR/scripts/history_book.sh" ]; then
    bash "$SCRIPT_DIR/scripts/history_book.sh" >/dev/null 2>&1 || true
  fi

  log_success "✅ zellij モードで起動完了"
else
  log_success "✅ セットアップのみ完了（CLI未起動）"
fi

echo ""
echo "接続方法（zellij）:"
echo "  zellij attach shogun"
for k in "${KARO_AGENTS[@]}"; do
  echo "  zellij attach $k"
done
for a in "${ACTIVE_ASHIGARU[@]}"; do
  echo "  zellij attach $a"
done
echo ""
echo "現在のセッション一覧:"
zellij list-sessions -n || true
