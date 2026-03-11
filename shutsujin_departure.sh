#!/usr/bin/env bash
# 🏯 multi-agent-shogun 出陣スクリプト（毎日の起動用）
# Daily Deployment Script for Multi-Agent Orchestration System
#
# 使用方法:
#   ./shutsujin_departure.sh           # 全エージェント起動（前回の状態を維持）
#   ./shutsujin_departure.sh -c        # キューをリセットして起動（クリーンスタート）
#   ./shutsujin_departure.sh -s        # セットアップのみ（Claude起動なし）
#   ./shutsujin_departure.sh -h        # ヘルプ表示

set -e

# スクリプトのディレクトリを取得
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
cd "$SCRIPT_DIR"

# 言語設定を読み取り（デフォルト: ja）
LANG_SETTING="ja"
if [ -f "./config/settings.yaml" ]; then
    LANG_SETTING=$(grep "^language:" ./config/settings.yaml 2>/dev/null | awk '{print $2}' || echo "ja")
fi

# シェル設定を読み取り（デフォルト: bash）
SHELL_SETTING="bash"
if [ -f "./config/settings.yaml" ]; then
    SHELL_SETTING=$(grep "^shell:" ./config/settings.yaml 2>/dev/null | awk '{print $2}' || echo "bash")
fi

EARLY_HELP_REQUESTED=false
for _arg in "$@"; do
    case "$_arg" in
        -h|--help)
            EARLY_HELP_REQUESTED=true
            break
            ;;
    esac
done

# ═══════════════════════════════════════════════════════════════════════════════
# Python / PyYAML プリフライトチェック
# ───────────────────────────────────────────────────────────────────────────────
# 現役コードは system python3 + PyYAML で動作可能とする。
# .venv が存在しても、それに yaml が無ければ system python3 を優先する。
# requirements.txt は現行 tmux 本線では必須にしない。
# ═══════════════════════════════════════════════════════════════════════════════
RUNTIME_PYTHON=""
if [ -x "$SCRIPT_DIR/.venv/bin/python3" ] && "$SCRIPT_DIR/.venv/bin/python3" -c "import yaml" >/dev/null 2>&1; then
    RUNTIME_PYTHON="$SCRIPT_DIR/.venv/bin/python3"
elif command -v python3 >/dev/null 2>&1 && python3 -c "import yaml" >/dev/null 2>&1; then
    RUNTIME_PYTHON="$(command -v python3)"
fi

if [ "$EARLY_HELP_REQUESTED" != true ] && [ -z "$RUNTIME_PYTHON" ]; then
    echo -e "\033[1;31m【ERROR】\033[0m Python 実行環境が不足しています。"
    echo "  必要条件:"
    echo "    - python3"
    echo "    - PyYAML (python3 -c 'import yaml' が成功すること)"
    echo ""
    echo "  まず次を実行してください:"
    echo "    bash first_setup.sh"
    echo ""
    echo "  あるいは Ubuntu/Debian なら:"
    echo "    sudo apt-get install -y python3 python3-yaml inotify-tools"
    exit 1
fi

# CLI Adapter読み込み（Multi-CLI Support）
if [ -f "$SCRIPT_DIR/lib/cli_adapter.sh" ]; then
    source "$SCRIPT_DIR/lib/cli_adapter.sh"
    CLI_ADAPTER_LOADED=true
else
    CLI_ADAPTER_LOADED=false
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

sync_gemini_workspace_settings() {
    local sync_script="$SCRIPT_DIR/scripts/sync_gemini_settings.py"
    if [ ! -x "$sync_script" ]; then
        return 0
    fi
    if ! python3 "$sync_script" >/dev/null 2>&1; then
        log_info "⚠️  Gemini workspace settings の同期に失敗しました。既存 .gemini/settings.json を使用して継続します"
    fi
}

sync_opencode_like_workspace_settings() {
    local sync_script="$SCRIPT_DIR/scripts/sync_opencode_config.py"
    if [ ! -x "$sync_script" ]; then
        return 0
    fi
    if ! python3 "$sync_script" >/dev/null 2>&1; then
        log_info "⚠️  OpenCode/Kilo project config の同期に失敗しました。既存 opencode.json を使用して継続します"
    fi
}

# 色付きログ関数（戦国風）
log_info() {
    echo -e "\033[1;33m【報】\033[0m $1"
}

log_success() {
    echo -e "\033[1;32m【成】\033[0m $1"
}

log_war() {
    echo -e "\033[1;31m【戦】\033[0m $1"
}

# Gemini CLI 初回の trust folder プロンプトを自動承認する（1回のみ）
auto_accept_gemini_trust_prompt_tmux() {
    local pane_target="$1"
    local agent_id="$2"
    local cli_type="$3"
    local i
    local pane_text

    [ "$cli_type" = "gemini" ] || return 0

    for i in {1..20}; do
        pane_text="$(tmux capture-pane -p -t "$pane_target" 2>/dev/null | tail -60 || true)"
        if echo "$pane_text" | grep -q "Do you trust this folder"; then
            tmux send-keys -t "$pane_target" "1"
            tmux send-keys -t "$pane_target" Enter
            log_info "  └─ ${agent_id}: Gemini trust prompt を自動承認"
            sleep 1
            return 0
        fi
        sleep 1
    done
    return 0
}

# Gemini CLI の高負荷画面（Keep trying/Stop）を自動で継続選択
auto_retry_gemini_busy_tmux() {
    local pane_target="$1"
    local agent_id="$2"
    local cli_type="$3"
    local i
    local pane_text

    [ "$cli_type" = "gemini" ] || return 0

    for i in {1..20}; do
        pane_text="$(tmux capture-pane -p -t "$pane_target" 2>/dev/null | tail -80 || true)"
        if echo "$pane_text" | grep -q "We are currently experiencing high demand"; then
            tmux send-keys -t "$pane_target" "1"
            tmux send-keys -t "$pane_target" Enter
            log_info "  └─ ${agent_id}: Gemini high-demand を自動再試行"
            sleep 2
            return 0
        fi
        sleep 1
    done
    return 0
}

auto_skip_codex_update_prompt_tmux() {
    local pane_target="$1"
    local agent_id="$2"
    local cli_type="$3"
    local i
    local pane_text

    [ "$cli_type" = "codex" ] || return 0

    for i in {1..20}; do
        pane_text="$(tmux capture-pane -p -t "$pane_target" 2>/dev/null | tail -80 || true)"
        if echo "$pane_text" | grep -qiE "Update available|Update now|Skip until next version|Press enter to continue"; then
            tmux send-keys -t "$pane_target" "2"
            tmux send-keys -t "$pane_target" Enter
            sleep 2
            pane_text="$(tmux capture-pane -p -t "$pane_target" 2>/dev/null | tail -80 || true)"
            if echo "$pane_text" | grep -qiE "Update available|Update now|Skip until next version|Press enter to continue"; then
                tmux send-keys -t "$pane_target" Down
                tmux send-keys -t "$pane_target" Enter
            fi
            log_info "  └─ ${agent_id}: Codex update prompt を自動スキップ"
            sleep 1
            return 0
        fi
        sleep 1
    done
    return 0
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

    if [ "$CLI_ADAPTER_LOADED" = true ]; then
        role_instruction_file="$(get_role_instruction_file "$agent_id" 2>/dev/null || true)"
        optimized_instruction_file="$(get_instruction_file "$agent_id" "$cli_type" 2>/dev/null || true)"
    fi

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

    mkdir -p "$bootstrap_dir"
    echo "$startup_msg" > "$bootstrap_file"
}

# CLIの準備完了をスクリーン内容で確認（pane_current_command の誤判定を回避）
# codex は node、gemini は node 等で表示されるため、UI文字列パターンで判定する。
wait_for_cli_ready_tmux() {
    local pane_target="$1"
    local cli_type="${2:-claude}"
    local max_wait="${3:-30}"
    local ready_pattern=""
    local i

    case "$cli_type" in
        claude)  ready_pattern='(claude code|Claude Code|╰|/model|for shortcuts)' ;;
        codex)   ready_pattern='(openai codex|Codex|context left|/model|for shortcuts|Press Ctrl|Working|esc to interrupt|% left)' ;;
        gemini)  ready_pattern='(gemini|Gemini|type your message|Tips to get|yolo mode|Working|esc to interrupt|Initializing the Agent)' ;;
        copilot) ready_pattern='(copilot|GitHub Copilot|/model)' ;;
        kimi)    ready_pattern='(kimi|moonshot|/model)' ;;
        localapi) ready_pattern='(localapi|LocalAPI|ready:|\$)' ;;
        *)       ready_pattern='(claude|codex|gemini|copilot|kimi|localapi|ready:)' ;;
    esac

    # max_wait=0 でも1回は即時チェックする（for ループでは 0<0 が偽でスキップされるため分離）
    local screen_content
    screen_content=$(tmux capture-pane -p -t "$pane_target" 2>/dev/null || true)
    if echo "$screen_content" | grep -qiE "$ready_pattern"; then
        return 0
    fi

    for ((i=0; i<max_wait; i++)); do
        sleep 1
        screen_content=$(tmux capture-pane -p -t "$pane_target" 2>/dev/null || true)
        if echo "$screen_content" | grep -qiE "$ready_pattern"; then
            return 0
        fi
    done
    return 1
}

# ファイルベースでブートストラップ配信（tmux版）
# ペインターゲットの存在を確認し、CLIの準備完了を待ってから送信
deliver_bootstrap_tmux() {
    local pane_target="$1"
    local agent_id="$2"
    local cli_type="${3:-claude}"
    local bootstrap_file="$SCRIPT_DIR/queue/runtime/bootstrap_${agent_id}.md"

    if [ ! -f "$bootstrap_file" ]; then
        echo "[WARN] bootstrap file not found for $agent_id: $bootstrap_file" >&2
        return 1
    fi

    # ペイン存在チェック
    if ! tmux display-message -p -t "$pane_target" "#{pane_id}" >/dev/null 2>&1; then
        echo "[WARN] pane '$pane_target' not found, skipping bootstrap for $agent_id" >&2
        return 1
    fi

    # CLIの準備完了を最大30秒待機（スクリーン内容ベース判定）
    if ! wait_for_cli_ready_tmux "$pane_target" "$cli_type" 30; then
        echo "[WARN] CLI '$cli_type' not ready in '$pane_target' after 30s, sending bootstrap anyway" >&2
    fi

    local msg
    msg="$(cat "$bootstrap_file")"
    # -l: リテラル送信（日本語・特殊文字をキーシーケンスと誤解釈させない）
    # sleep: CLI がテキストをバッファに受け取ってから Enter を送る
    tmux send-keys -l -t "$pane_target" "$msg"
    sleep 0.3
    tmux send-keys -t "$pane_target" Enter
}

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

role_linkage_directive() {
    local agent_id="$1"
    case "$agent_id" in
        shogun)
            echo "連携順序: 殿の指示を受けたら、必ず『将軍→家老→足軽』で委譲せよ。家老への委譲は queue/shogun_to_karo.yaml 更新 + inbox通知を使い、足軽へ直接命令してはならない。"
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

fallback_model_display_name() {
    local agent_id="$1"
    if [[ "$agent_id" == shogun || "$agent_id" == gunshi || "$agent_id" == karo* ]]; then
        echo "Opus"
    elif [ "$KESSEN_MODE" = true ]; then
        echo "Opus"
    else
        echo "Sonnet"
    fi
}

resolve_model_display_name() {
    local agent_id="$1"
    if [ "$CLI_ADAPTER_LOADED" = true ]; then
        get_model_display_name "$agent_id" 2>/dev/null && return 0
    fi
    fallback_model_display_name "$agent_id"
}

resolve_cli_summary() {
    local agent_id="$1"
    local cli_type="${2:-claude}"
    printf "%s / %s" "$cli_type" "$(resolve_model_display_name "$agent_id")"
}

# ═══════════════════════════════════════════════════════════════════════════════
# プロンプト生成関数（bash/zsh対応）
# ───────────────────────────────────────────────────────────────────────────────
# 使用法: generate_prompt "ラベル" "色" "シェル"
# 色: red, green, blue, magenta, cyan, yellow
# ═══════════════════════════════════════════════════════════════════════════════
generate_prompt() {
    local label="$1"
    local color="$2"
    local shell_type="$3"

    if [ "$shell_type" == "zsh" ]; then
        # zsh用: %F{color}%B...%b%f 形式
        echo "(%F{${color}}%B${label}%b%f) %F{green}%B%~%b%f%# "
    else
        # bash用: \[\033[...m\] 形式
        local color_code
        case "$color" in
            red)     color_code="1;31" ;;
            green)   color_code="1;32" ;;
            yellow)  color_code="1;33" ;;
            blue)    color_code="1;34" ;;
            magenta) color_code="1;35" ;;
            cyan)    color_code="1;36" ;;
            *)       color_code="1;37" ;;  # white (default)
        esac
        echo "(\[\033[${color_code}m\]${label}\[\033[0m\]) \[\033[1;32m\]\w\[\033[0m\]\$ "
    fi
}

# ═══════════════════════════════════════════════════════════════════════════════
# オプション解析
# ═══════════════════════════════════════════════════════════════════════════════
SETUP_ONLY=false
OPEN_TERMINAL=false
CLEAN_MODE=false
KESSEN_MODE=false
SHOGUN_NO_THINKING=false
SILENT_MODE=false
SHELL_OVERRIDE=""

while [[ $# -gt 0 ]]; do
    case $1 in
        -s|--setup-only)
            SETUP_ONLY=true
            shift
            ;;
        -c|--clean)
            CLEAN_MODE=true
            shift
            ;;
        -k|--kessen)
            KESSEN_MODE=true
            shift
            ;;
        -t|--terminal)
            OPEN_TERMINAL=true
            shift
            ;;
        --shogun-no-thinking)
            SHOGUN_NO_THINKING=true
            shift
            ;;
        -S|--silent)
            SILENT_MODE=true
            shift
            ;;
        -shell|--shell)
            if [[ -n "$2" && "$2" != -* ]]; then
                SHELL_OVERRIDE="$2"
                shift 2
            else
                echo "エラー: -shell オプションには bash または zsh を指定してください"
                exit 1
            fi
            ;;
        -h|--help)
            echo ""
            echo "🏯 multi-agent-shogun 出陣スクリプト"
            echo ""
            echo "使用方法: ./shutsujin_departure.sh [オプション]"
            echo ""
            echo "オプション:"
            echo "  -c, --clean         キューとダッシュボードをリセットして起動（クリーンスタート）"
            echo "                      未指定時は前回の状態を維持して起動"
            echo "  -k, --kessen        決戦の陣（Claude系エージェントをOpus優先で起動）"
            echo "                      未指定時は config/settings.yaml のCLI/モデル設定を使用"
            echo "  -s, --setup-only    セッションのセットアップのみ（CLI起動なし）"
            echo "  -t, --terminal      Windows Terminal で新しいタブを開く"
            echo "  -shell, --shell SH  シェルを指定（bash または zsh）"
            echo "                      未指定時は config/settings.yaml の設定を使用"
            echo "  -S, --silent        サイレントモード（足軽の戦国echo表示を無効化・API節約）"
            echo "                      未指定時はshoutモード（タスク完了時に戦国風echo表示）"
            echo "  -h, --help          このヘルプを表示"
            echo ""
            echo "マルチプレクサ設定:"
            echo "  config/settings.yaml の multiplexer.default は tmux 専用です"
            echo ""
            echo "例:"
            echo "  ./shutsujin_departure.sh              # 前回の状態を維持して出陣"
            echo "  ./shutsujin_departure.sh -c           # クリーンスタート（キューリセット）"
            echo "  ./shutsujin_departure.sh -s           # セットアップのみ（CLI起動なし）"
            echo "  ./shutsujin_departure.sh -t           # 全エージェント起動 + ターミナルタブ展開"
            echo "  ./shutsujin_departure.sh -shell bash  # bash用プロンプトで起動"
            echo "  ./shutsujin_departure.sh -k           # 決戦の陣（Claude系をOpus優先）"
            echo "  ./shutsujin_departure.sh -c -k         # クリーンスタート＋決戦の陣"
            echo "  ./shutsujin_departure.sh -shell zsh   # zsh用プロンプトで起動"
            echo "  ./shutsujin_departure.sh --shogun-no-thinking  # 将軍のthinkingを無効化（中継特化）"
            echo "  ./shutsujin_departure.sh -S           # サイレントモード（echo表示なし）"
            echo ""
            echo "CLI/モデル構成:"
            echo "  config/settings.yaml の cli.default / cli.agents.* を使用"
            echo "  変更は scripts/configure_agents.sh から行う"
            echo "  --kessen は Claude 系エージェントのみ Opus 優先に上書き"
            echo ""
            echo "表示モード:"
            echo "  shout（デフォルト）:  タスク完了時に戦国風echo表示"
            echo "  silent（--silent）:   echo表示なし（API節約）"
            echo ""
            echo "エイリアス:"
            echo "  csst  → cd /mnt/c/tools/multi-agent-shogun && ./shutsujin_departure.sh"
            echo "  css   → tmux attach-session -t shogun"
            echo "  csg   → tmux attach-session -t gunshi"
            echo "  csm   → tmux attach-session -t multiagent"
            echo "  cgo   → bash scripts/goza_no_ma.sh"
            echo ""
            exit 0
            ;;
        *)
            echo "不明なオプション: $1"
            echo "./shutsujin_departure.sh -h でヘルプを表示"
            exit 1
            ;;
    esac
done

# シェル設定のオーバーライド（コマンドラインオプション優先）
if [ -n "$SHELL_OVERRIDE" ]; then
    if [[ "$SHELL_OVERRIDE" == "bash" || "$SHELL_OVERRIDE" == "zsh" ]]; then
        SHELL_SETTING="$SHELL_OVERRIDE"
    else
        echo "エラー: -shell オプションには bash または zsh を指定してください（指定値: $SHELL_OVERRIDE）"
        exit 1
    fi
fi

# 役職正本/CLI最適化指示書の差分がある場合は自動再生成
ensure_generated_instructions
sync_gemini_workspace_settings
sync_opencode_like_workspace_settings

# 有効化する足軽リスト（デフォルト: ashigaru1）
ACTIVE_ASHIGARU=("ashigaru1")
if [ -f "./config/settings.yaml" ]; then
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

# shell配列をpythonへ安全に渡せないため、ACTIVEを個別に合流
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

# ═══════════════════════════════════════════════════════════════════════════════
# 出陣バナー表示（CC0ライセンスASCIIアート使用）
# ───────────────────────────────────────────────────────────────────────────────
# 【著作権・ライセンス表示】
# 忍者ASCIIアート: syntax-samurai/ryu - CC0 1.0 Universal (Public Domain)
# 出典: https://github.com/syntax-samurai/ryu
# "all files and scripts in this repo are released CC0 / kopimi!"
# ═══════════════════════════════════════════════════════════════════════════════
show_battle_cry() {
    if [ -t 1 ]; then
        clear || true
    else
        echo ""
    fi

    # タイトルバナー（色付き）
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

    # ═══════════════════════════════════════════════════════════════════════════
    # 足軽隊列（オリジナル）
    # ═══════════════════════════════════════════════════════════════════════════
    echo -e "\033[1;34m  ╔═════════════════════════════════════════════════════════════════════════════╗\033[0m"
    echo -e "\033[1;34m  ║\033[0m                    \033[1;37m【 足 軽 隊 列 ・ ${ACTIVE_ASHIGARU_COUNT} 名 配 備 】\033[0m                      \033[1;34m║\033[0m"
    echo -e "\033[1;34m  ╚═════════════════════════════════════════════════════════════════════════════╝\033[0m"
    render_ashigaru_ascii "$ACTIVE_ASHIGARU_COUNT"

    echo -e "                    \033[1;36m「「「 はっ！！ 出陣いたす！！ 」」」\033[0m"
    echo ""

    # ═══════════════════════════════════════════════════════════════════════════
    # システム情報
    # ═══════════════════════════════════════════════════════════════════════════
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

# バナー表示実行
show_battle_cry

echo -e "  \033[1;33m天下布武！陣立てを開始いたす\033[0m (Setting up the battlefield)"
echo ""

# ═══════════════════════════════════════════════════════════════════════════════
# STEP 1: 既存セッションクリーンアップ
# ═══════════════════════════════════════════════════════════════════════════════
log_info "🧹 既存の陣を撤収中..."
tmux kill-session -t multiagent 2>/dev/null && log_info "  └─ multiagent陣、撤収完了" || log_info "  └─ multiagent陣は存在せず"
tmux kill-session -t shogun 2>/dev/null && log_info "  └─ shogun本陣、撤収完了" || log_info "  └─ shogun本陣は存在せず"

# ═══════════════════════════════════════════════════════════════════════════════
# STEP 1.5: 前回記録のバックアップ（--clean時のみ、内容がある場合）
# ═══════════════════════════════════════════════════════════════════════════════
if [ "$CLEAN_MODE" = true ]; then
    BACKUP_DIR="./logs/backup_$(date '+%Y%m%d_%H%M%S')"
    NEED_BACKUP=false

    if [ -f "./dashboard.md" ]; then
        if grep -q "cmd_" "./dashboard.md" 2>/dev/null; then
            NEED_BACKUP=true
        fi
    fi

    # 既存の dashboard.md 判定の後に追加
    if [ -f "./queue/shogun_to_karo.yaml" ]; then
        if grep -q "id: cmd_" "./queue/shogun_to_karo.yaml" 2>/dev/null; then
            NEED_BACKUP=true
        fi
    fi

    if [ "$NEED_BACKUP" = true ]; then
        mkdir -p "$BACKUP_DIR" || true
        cp "./dashboard.md" "$BACKUP_DIR/" 2>/dev/null || true
        cp -r "./queue/reports" "$BACKUP_DIR/" 2>/dev/null || true
        cp -r "./queue/tasks" "$BACKUP_DIR/" 2>/dev/null || true
        cp "./queue/shogun_to_karo.yaml" "$BACKUP_DIR/" 2>/dev/null || true
        log_info "📦 前回の記録をバックアップ: $BACKUP_DIR"
    fi
fi

# ═══════════════════════════════════════════════════════════════════════════════
# STEP 2: キューディレクトリ確保 + リセット（--clean時のみリセット）
# ═══════════════════════════════════════════════════════════════════════════════

# queue ディレクトリが存在しない場合は作成（初回起動時に必要）
[ -d ./queue/reports ] || mkdir -p ./queue/reports
[ -d ./queue/tasks ] || mkdir -p ./queue/tasks
if declare -F ensure_local_inbox_dir >/dev/null 2>&1; then
    ensure_local_inbox_dir "./queue/inbox"
else
    [ -d ./queue/inbox ] || mkdir -p ./queue/inbox
fi

if [ "$CLEAN_MODE" = true ]; then
    log_info "📜 前回の軍議記録を破棄中..."

    # 足軽タスクファイルリセット
    for _agent in "${KNOWN_ASHIGARU[@]}"; do
        _num="${_agent#ashigaru}"
        cat > "./queue/tasks/${_agent}.yaml" << EOF
# 足軽${_num}専用タスクファイル
task:
  task_id: null
  parent_cmd: null
  description: null
  target_path: null
  status: idle
  timestamp: ""
EOF
    done

    # 足軽レポートファイルリセット
    for _agent in "${KNOWN_ASHIGARU[@]}"; do
        _num="${_agent#ashigaru}"
        cat > "./queue/reports/${_agent}_report.yaml" << EOF
worker_id: ${_agent}
task_id: null
timestamp: ""
status: idle
result: null
EOF
    done

    # 軍師タスク・レポートファイルリセット
    cat > "./queue/tasks/gunshi.yaml" << EOF
# 軍師専用タスクファイル
task:
  task_id: null
  parent_cmd: null
  description: null
  target_path: null
  status: idle
  timestamp: ""
EOF
    cat > "./queue/reports/gunshi_report.yaml" << EOF
worker_id: gunshi
task_id: null
timestamp: ""
status: idle
result: null
EOF

    # ntfy inbox リセット
    echo "inbox:" > ./queue/ntfy_inbox.yaml

    # agent inbox リセット
    for agent in shogun gunshi "${KARO_AGENTS[@]}" "${KNOWN_ASHIGARU[@]}"; do
        echo "messages: []" > "./queue/inbox/${agent}.yaml"
    done

    log_success "✅ 陣払い完了"
else
    log_info "📜 前回の陣容を維持して出陣..."
    log_success "✅ キュー・報告ファイルはそのまま継続"
fi

mkdir -p "$SCRIPT_DIR/queue/runtime"
if [ "$TOPOLOGY_ADAPTER_LOADED" = true ]; then
    build_even_ownership_map "$SCRIPT_DIR/queue/runtime/ashigaru_owner.tsv" "${ACTIVE_ASHIGARU[@]}"
else
    : > "$SCRIPT_DIR/queue/runtime/ashigaru_owner.tsv"
    for _agent in "${ACTIVE_ASHIGARU[@]}"; do
        printf "%s\tkaro\n" "$_agent" >> "$SCRIPT_DIR/queue/runtime/ashigaru_owner.tsv"
    done
fi

# ═══════════════════════════════════════════════════════════════════════════════
# STEP 3: ダッシュボード初期化（--clean時のみ）
# ═══════════════════════════════════════════════════════════════════════════════
if [ "$CLEAN_MODE" = true ]; then
    log_info "📊 戦況報告板を初期化中..."
    TIMESTAMP=$(date "+%Y-%m-%d %H:%M")

    if [ "$LANG_SETTING" = "ja" ]; then
        # 日本語のみ
        cat > ./dashboard.md << EOF
# 📊 戦況報告
最終更新: ${TIMESTAMP}

## 🚨 要対応 - 殿のご判断をお待ちしております
なし

## 🔄 進行中 - 只今、戦闘中でござる
なし

## ✅ 本日の戦果
| 時刻 | 戦場 | 任務 | 結果 |
|------|------|------|------|

## 🎯 スキル化候補 - 承認待ち
なし

## 🛠️ 生成されたスキル
なし

## ⏸️ 待機中
なし

## ❓ 伺い事項
なし
EOF
    else
        # 日本語 + 翻訳併記
        cat > ./dashboard.md << EOF
# 📊 戦況報告 (Battle Status Report)
最終更新 (Last Updated): ${TIMESTAMP}

## 🚨 要対応 - 殿のご判断をお待ちしております (Action Required - Awaiting Lord's Decision)
なし (None)

## 🔄 進行中 - 只今、戦闘中でござる (In Progress - Currently in Battle)
なし (None)

## ✅ 本日の戦果 (Today's Achievements)
| 時刻 (Time) | 戦場 (Battlefield) | 任務 (Mission) | 結果 (Result) |
|------|------|------|------|

## 🎯 スキル化候補 - 承認待ち (Skill Candidates - Pending Approval)
なし (None)

## 🛠️ 生成されたスキル (Generated Skills)
なし (None)

## ⏸️ 待機中 (On Standby)
なし (None)

## ❓ 伺い事項 (Questions for Lord)
なし (None)
EOF
    fi

    log_success "  └─ ダッシュボード初期化完了 (言語: $LANG_SETTING, シェル: $SHELL_SETTING)"
else
    log_info "📊 前回のダッシュボードを維持"
fi
echo ""

# ═══════════════════════════════════════════════════════════════════════════════
# STEP 4: tmux の存在確認
# ═══════════════════════════════════════════════════════════════════════════════
if ! command -v tmux &> /dev/null; then
    echo ""
    echo "  ╔════════════════════════════════════════════════════════╗"
    echo "  ║  [ERROR] tmux not found!                              ║"
    echo "  ║  tmux が見つかりません                                 ║"
    echo "  ╠════════════════════════════════════════════════════════╣"
    echo "  ║  Run first_setup.sh first:                            ║"
    echo "  ║  まず first_setup.sh を実行してください:               ║"
    echo "  ║     ./first_setup.sh                                  ║"
    echo "  ╚════════════════════════════════════════════════════════╝"
    echo ""
    exit 1
fi

# ═══════════════════════════════════════════════════════════════════════════════
# STEP 5: shogun セッション作成（1ペイン・window 0 を必ず確保）
# ═══════════════════════════════════════════════════════════════════════════════
log_war "👑 将軍の本陣を構築中..."

# shogun セッションがなければ作る（-s 時もここで必ず shogun が存在するようにする）
# window 0 のみ作成し -n main で名前付け（第二 window にするとアタッチ時に空ペインが開くため 1 window に限定）
if ! tmux has-session -t shogun 2>/dev/null; then
    tmux new-session -d -s shogun -n main
fi

# 将軍ペインはウィンドウ名 "main" で指定（base-index 1 環境でも動く）
SHOGUN_PROMPT=$(generate_prompt "将軍" "magenta" "$SHELL_SETTING")
tmux send-keys -t shogun:main "cd \"$(pwd)\" && export PS1='${SHOGUN_PROMPT}' && clear" Enter
tmux select-pane -t shogun:main -P 'bg=#002b36'  # 将軍の Solarized Dark
tmux set-option -p -t shogun:main @agent_id "shogun"

log_success "  └─ 将軍の本陣、構築完了"
echo ""

# ═══════════════════════════════════════════════════════════════════════════════
# STEP 5.0.5: gunshi（軍師）セッション構築
# ═══════════════════════════════════════════════════════════════════════════════
log_war "🧠 軍師の陣営を構築中..."

if ! tmux has-session -t gunshi 2>/dev/null; then
    tmux new-session -d -s gunshi -n main
fi

GUNSHI_PROMPT=$(generate_prompt "軍師" "cyan" "$SHELL_SETTING")
tmux send-keys -t gunshi:main "cd \"$(pwd)\" && export PS1='${GUNSHI_PROMPT}' && clear" C-m
tmux select-pane -t gunshi:main -P 'bg=#002b36'
tmux set-option -p -t gunshi:main @agent_id "gunshi"

log_success "  └─ 軍師の陣営、構築完了"
echo ""

# pane-base-index を取得（1 の環境ではペインは 1,2,... になる）
PANE_BASE=$(tmux show-options -gv pane-base-index 2>/dev/null || echo 0)

MULTIAGENT_IDS=("${KARO_AGENTS[@]}" "${ACTIVE_ASHIGARU[@]}")
MULTIAGENT_COUNT=${#MULTIAGENT_IDS[@]}

# ═══════════════════════════════════════════════════════════════════════════════
# STEP 5.1: multiagent セッション作成（karo + active_ashigaru）
# ═══════════════════════════════════════════════════════════════════════════════
log_war "⚔️ 家老・足軽の陣を構築中（${MULTIAGENT_COUNT}名配備）..."

# 最初のペイン作成
if ! tmux new-session -d -s multiagent -n "agents" 2>/dev/null; then
    echo ""
    echo "  ╔════════════════════════════════════════════════════════════╗"
    echo "  ║  [ERROR] Failed to create tmux session 'multiagent'      ║"
    echo "  ║  tmux セッション 'multiagent' の作成に失敗しました       ║"
    echo "  ╠════════════════════════════════════════════════════════════╣"
    echo "  ║  An existing session may be running.                     ║"
    echo "  ║  既存セッションが残っている可能性があります              ║"
    echo "  ║                                                          ║"
    echo "  ║  Check: tmux ls                                          ║"
    echo "  ║  Kill:  tmux kill-session -t multiagent                  ║"
    echo "  ╚════════════════════════════════════════════════════════════╝"
    echo ""
    exit 1
fi

# DISPLAY_MODE: shout (default) or silent (--silent flag)
if [ "$SILENT_MODE" = true ]; then
    tmux set-environment -t multiagent DISPLAY_MODE "silent"
    echo "  📢 表示モード: サイレント（echo表示なし）"
else
    tmux set-environment -t multiagent DISPLAY_MODE "shout"
fi

# タイル分割作成（合計: karo + active_ashigaru）
for ((i=1; i<MULTIAGENT_COUNT; i++)); do
    tmux split-window -v -t "multiagent:agents"
    tmux select-layout -t "multiagent:agents" tiled >/dev/null 2>&1 || true
done

# ペインラベル設定（プロンプト用）
PANE_LABELS=("${MULTIAGENT_IDS[@]}")
PANE_TITLES=("${MULTIAGENT_IDS[@]}")
PANE_COLORS=()
for _agent in "${MULTIAGENT_IDS[@]}"; do
    if [[ "$_agent" == karo* ]]; then
        PANE_COLORS+=("red")
    else
        PANE_COLORS+=("blue")
    fi
done

AGENT_IDS=("${MULTIAGENT_IDS[@]}")

# モデル名設定（pane-border-format で常時表示するための既定値）
MODEL_NAMES=()
for _agent in "${AGENT_IDS[@]}"; do
    MODEL_NAMES+=("$(resolve_model_display_name "$_agent")")
done

for i in "${!AGENT_IDS[@]}"; do
    p=$((PANE_BASE + i))
    tmux select-pane -t "multiagent:agents.${p}" -T "${PANE_TITLES[$i]}"
    tmux set-option -p -t "multiagent:agents.${p}" @agent_id "${AGENT_IDS[$i]}"
    tmux set-option -p -t "multiagent:agents.${p}" @model_name "${MODEL_NAMES[$i]}"
    tmux set-option -p -t "multiagent:agents.${p}" @current_task ""
    PROMPT_STR=$(generate_prompt "${PANE_LABELS[$i]}" "${PANE_COLORS[$i]}" "$SHELL_SETTING")
    tmux send-keys -t "multiagent:agents.${p}" "cd \"$(pwd)\" && export PS1='${PROMPT_STR}' && clear" Enter
done

# pane-border-format でモデル名を常時表示
tmux set-option -t multiagent -w pane-border-status top
tmux set-option -t multiagent -w pane-border-format '#{?pane_active,#[reverse],}#[bold]#{@agent_id}#[default] (#{@model_name}) #{@current_task}'

log_success "  └─ 家老・足軽の陣、構築完了"
echo ""

# ═══════════════════════════════════════════════════════════════════════════════
# STEP 6: CLI 起動（-s / --setup-only のときはスキップ）
# ═══════════════════════════════════════════════════════════════════════════════
if [ "$SETUP_ONLY" = false ]; then
    # CLI の存在チェック（Multi-CLI対応）
    if [ "$CLI_ADAPTER_LOADED" = true ]; then
        if ! get_first_available_cli >/dev/null 2>&1; then
            echo "[ERROR] No supported CLI found. Install one of: claude, codex, gemini, localapi, copilot, kimi" >&2
            exit 1
        fi
    else
        if ! command -v claude &> /dev/null; then
            log_info "⚠️  claude コマンドが見つかりません"
            echo "  first_setup.sh を再実行してください:"
            echo "    ./first_setup.sh"
            exit 1
        fi
    fi

    log_war "👑 全エージェントCLIを起動中..."
    mkdir -p "$SCRIPT_DIR/queue/runtime"
    : > "$SCRIPT_DIR/queue/runtime/agent_cli.tsv"

    # Phase 0: 全エージェントのブートストラップファイルを事前生成
    # CLI起動前にファイルを書き出すことで、レースコンディションを排除
    log_info "📝 ブートストラップファイルを事前生成中"

    # 将軍: CLI Adapter経由でコマンド構築
    _shogun_cli_type="claude"
    _shogun_cmd="claude --model opus --dangerously-skip-permissions"
    if [ "$CLI_ADAPTER_LOADED" = true ]; then
        _shogun_cli_type=$(resolve_cli_type_for_agent "shogun")
        _shogun_cmd=$(build_cli_command_with_type "shogun" "$_shogun_cli_type")
    fi
    tmux set-option -p -t "shogun:main" @agent_cli "$_shogun_cli_type"
    generate_bootstrap_file "shogun" "$_shogun_cli_type"
    printf "shogun\t%s\n" "$_shogun_cli_type" >> "$SCRIPT_DIR/queue/runtime/agent_cli.tsv"
    if [ "$SHOGUN_NO_THINKING" = true ] && [ "$_shogun_cli_type" = "claude" ]; then
        tmux send-keys -t shogun:main "MAX_THINKING_TOKENS=0 $_shogun_cmd"
        tmux send-keys -t shogun:main C-m
        tmux set-option -p -t "shogun:main" @model_name "$(resolve_model_display_name "shogun")"
        log_info "  └─ 将軍（$(resolve_cli_summary "shogun" "$_shogun_cli_type") / thinking無効）、召喚完了"
    else
        tmux send-keys -t shogun:main "$_shogun_cmd"
        tmux send-keys -t shogun:main C-m
        tmux set-option -p -t "shogun:main" @model_name "$(resolve_model_display_name "shogun")"
        log_info "  └─ 将軍（$(resolve_cli_summary "shogun" "$_shogun_cli_type")）、召喚完了"
    fi

    # 軍師: CLI Adapter経由でコマンド構築
    _gunshi_cli_type="claude"
    _gunshi_cmd="claude --model opus --dangerously-skip-permissions"
    if [ "$CLI_ADAPTER_LOADED" = true ]; then
        _gunshi_cli_type=$(resolve_cli_type_for_agent "gunshi")
        _gunshi_cmd=$(build_cli_command_with_type "gunshi" "$_gunshi_cli_type")
    fi
    tmux set-option -p -t "gunshi:main" @agent_cli "$_gunshi_cli_type"
    generate_bootstrap_file "gunshi" "$_gunshi_cli_type"
    printf "gunshi\t%s\n" "$_gunshi_cli_type" >> "$SCRIPT_DIR/queue/runtime/agent_cli.tsv"
    tmux send-keys -t gunshi:main "$_gunshi_cmd"
    tmux send-keys -t gunshi:main C-m
    tmux set-option -p -t "gunshi:main" @model_name "$(resolve_model_display_name "gunshi")"
    log_info "  └─ 軍師（$(resolve_cli_summary "gunshi" "$_gunshi_cli_type")）、召喚完了"

    # 少し待機（安定のため）
    sleep 1

    declare -A MULTIAGENT_CLI=()
    _karo_launched=0
    _ashigaru_launched=0
    for _idx in "${!MULTIAGENT_IDS[@]}"; do
        _agent="${MULTIAGENT_IDS[$_idx]}"
        p=$((PANE_BASE + _idx))

        if [[ "$_agent" == karo* ]]; then
            _agent_cli_type="claude"
            _agent_cmd="claude --model opus --dangerously-skip-permissions"
            if [ "$CLI_ADAPTER_LOADED" = true ]; then
                _agent_cli_type=$(resolve_cli_type_for_agent "$_agent")
                _agent_cmd=$(build_cli_command_with_type "$_agent" "$_agent_cli_type")
            fi
            _karo_launched=$((_karo_launched + 1))
        else
            _ashi_num="${_agent#ashigaru}"
            _agent_cli_type="claude"
            if [ "$KESSEN_MODE" = true ]; then
                _agent_cmd="claude --model opus --dangerously-skip-permissions"
            elif [ "${_ashi_num:-0}" -le 4 ]; then
                _agent_cmd="claude --model sonnet --dangerously-skip-permissions"
            else
                _agent_cmd="claude --model opus --dangerously-skip-permissions"
            fi
            if [ "$CLI_ADAPTER_LOADED" = true ]; then
                _agent_cli_type=$(resolve_cli_type_for_agent "$_agent")
                if [ "$KESSEN_MODE" = true ] && [ "$_agent_cli_type" = "claude" ]; then
                    _agent_cmd="claude --model opus --dangerously-skip-permissions"
                else
                    _agent_cmd=$(build_cli_command_with_type "$_agent" "$_agent_cli_type")
                fi
            fi
            _ashigaru_launched=$((_ashigaru_launched + 1))
        fi

        tmux set-option -p -t "multiagent:agents.${p}" @agent_cli "$_agent_cli_type"
        generate_bootstrap_file "$_agent" "$_agent_cli_type"
        tmux send-keys -t "multiagent:agents.${p}" "$_agent_cmd"
        tmux send-keys -t "multiagent:agents.${p}" C-m
        printf "%s\t%s\n" "$_agent" "$_agent_cli_type" >> "$SCRIPT_DIR/queue/runtime/agent_cli.tsv"
        MULTIAGENT_CLI["$_agent"]="$_agent_cli_type"
        tmux set-option -p -t "multiagent:agents.${p}" @model_name "$(resolve_model_display_name "$_agent")"
        log_info "  └─ ${_agent}（$(resolve_cli_summary "$_agent" "$_agent_cli_type")）、召喚完了"
    done
    log_info "  └─ 家老（${_karo_launched}名）、召喚完了"
    if [ "$KESSEN_MODE" = true ]; then
        log_info "  └─ 足軽（決戦の陣 / Claude系Opus優先: ${_ashigaru_launched}名）"
    else
        log_info "  └─ 足軽（設定どおり: ${_ashigaru_launched}名）"
    fi

    # Gemini / Codex の初回プリフライトを自動処理（並列実行）
    _gemini_pids=()
    _cli_gate_handler() {
        local _pane="$1" _agent="$2" _cli="$3"
        auto_skip_codex_update_prompt_tmux "$_pane" "$_agent" "$_cli"
        auto_accept_gemini_trust_prompt_tmux "$_pane" "$_agent" "$_cli"
        auto_retry_gemini_busy_tmux "$_pane" "$_agent" "$_cli"
    }
    _cli_gate_handler "shogun:main" "shogun" "$_shogun_cli_type" &
    _gemini_pids+=($!)
    _cli_gate_handler "gunshi:main" "gunshi" "$_gunshi_cli_type" &
    _gemini_pids+=($!)
    for _idx in "${!MULTIAGENT_IDS[@]}"; do
        _agent="${MULTIAGENT_IDS[$_idx]}"
        p=$((PANE_BASE + _idx))
        _pane_cli=$(tmux show-options -p -t "multiagent:agents.${p}" -v @agent_cli 2>/dev/null || echo "claude")
        _cli_gate_handler "multiagent:agents.${p}" "$_agent" "$_pane_cli" &
        _gemini_pids+=($!)
    done
    for _pid in "${_gemini_pids[@]}"; do
        wait "$_pid" 2>/dev/null || true
    done
    unset _gemini_pids

    if [ "$KESSEN_MODE" = true ]; then
        log_success "✅ 決戦の陣で出陣（Claude系Opus優先）"
    else
        log_success "✅ 設定どおりの陣容で出陣"
    fi
    echo ""

    # ═══════════════════════════════════════════════════════════════════════════
    # STEP 6.5: 各エージェントに指示書を読み込ませる
    # ═══════════════════════════════════════════════════════════════════════════
    log_war "📜 各エージェントに指示書を読み込ませ中..."
    echo ""

    # ═══════════════════════════════════════════════════════════════════════════
    # 忍者戦士（syntax-samurai/ryu - CC0 1.0 Public Domain）
    # ═══════════════════════════════════════════════════════════════════════════
    echo -e "\033[1;35m  ┌────────────────────────────────────────────────────────────────────────────────────────────────────────────┐\033[0m"
    echo -e "\033[1;35m  │\033[0m                              \033[1;37m【 忍 者 戦 士 】\033[0m  Ryu Hayabusa (CC0 Public Domain)                        \033[1;35m│\033[0m"
    echo -e "\033[1;35m  └────────────────────────────────────────────────────────────────────────────────────────────────────────────┘\033[0m"

    cat << 'NINJA_EOF'
...................................░░░░░░░░░░░░░░░░░░░░░░░░░░░░░▒▒▒▒▒▒▒▒▒▒▒▒▒▒▒▒▒▒▒▒▒▒▒▒▒▒▒▒▒▒▒▒▒▒▒▒▒▒▒▒▒▒▒▒                        ...................................
..................................░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░▒▒▒▒▒▒▒▒▒▒▒▒▒▒▒▒▒▒▒▒▒▒▒▒▒▒▒▒▒▒▒▒▒▒▒▒▒▒▒▒▒▒▒▒                        ...................................
..................................░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░▒▒▒▒▒▒▒▒▒▒▒▒▒▒▒▒▒▒▒▒▒▒▒▒▒▒▒▒▒▒▒▒▒▒▒▒▒▒▒▒▒▒▒▒                        ...................................
..................................░░░░░░░░░░░░░░░░░░░░░░░░░░░▒▒▒▒▒▒▒▒▒▒▒▒▒▒▒▒▒▒▒▒▒▒▒▒▒▒▒▒▒▒▒▒▒▒▒▒▒▒▒▒▒▒▒▒▒▒▒                        ...................................
..................................░░░░░░░░░░░░░░░░░░░░░░░░▒▒▒▒▒▒▒▒▒▒▒▒▒▒▒▒▒▒▒▒▒▒▒▒▒▒▒▒▒▒▒▒▒▒▒▒▒▒▒▒▒▒▒▒▒▒▒▒▒▒                        ...................................
..................................░░░░░░░░░░░░░░░░░░░░▒▒▒▒▒▒▒▒▒▒▒▒▒▒▒▒▒▒▒▒▒▒▒▒▒▒▒▒▒▒▒▒▒▒▒▒▒▒▒░░░░░░░░▒▒▒▒▒▒                         ...................................
..................................░░░░░░░░░░░░░░░░░░▒▒▒▒▒▒▒▒▒▒▒▒▒▒▒  ▒▒▒▒▒▒░░▒▒▒▒▒▒▒▒▒▒▒▒▒▒▒░░░░░░░░▒▒▒▒▒▒▒                         ...................................
..................................░░░░░░░░░░░░░░░░▒▒▒▒          ▒▒▒▒▒▒▒▒░░░░░▒▒▒▒▒▒▒▒▒▒▒▒▒░░░░▒▒▒▒▒▒▒▒▒                             ...................................
..................................░░░░░░░░░░░░░░▒▒▒▒               ▒▒▒▒▒░░░░▒▒▒▒▒▒▒▒▒▒▒▒▒▒▒▒▒▒▒▒▒▒▒▒                                ...................................
..................................░░░░░░░░░░░░░▒▒▒                    ▒▒▒▒░░▒▒▒▒▒▒▒▒▒▒▒▒▒▒▒▒▒▒▒▒                                    ...................................
..................................░░░░░░░░░░░░▒                            ▒▒▒▒▒▒▒▒▒▒▒▒▒▒▒▒▒                                        ...................................
..................................░░░░░░░░░░░      ░░░░░░░░░░░░░                                      ░░░░░░░░░░░░       ▒          ...................................
..................................░░░░░░░░░░ ▒    ░░░▓▓▓▓▓▓▓▓▓▓▓▓░░                                 ░░░░░░░░░░░░░░░ ░               ...................................
..................................░░░░░░░░░░     ░░░▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓░░░                          ░░░░░░░░░░░░░░░░░░░                ...................................
..................................░░░░░░░░░ ▒  ░░░░▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓░░░░             ░░▓▓▓▓▓▓▓▓░░░░░░░░░░░░░░░░  ░   ▒         ...................................
..................................░░░░░░░░ ░  ░░░░░░▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓░░░░░░░░░░░░░░░▓▓▓▓▓▓▓▓▓▓░░░░░░░░░░░░░░░░░ ░  ▒         ...................................
..................................░░░░░░░░ ░  ░░░░░░░▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓░░░░░░░░░░░▓▓▓▓▓▓▓▓▓▓▓░░░░░░░░░░░░░░░  ░    ▒        ...................................
..................................░░░░░░░░░▒  ░ ░               ▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓░░░░░░░░░▓▓▓▓▓▓▓▓▓▓▓░                 ░            ...................................
.................................░░░░░░░░░░   ░░░  ░                 ▓▓▓▓▓▓▓▓░▓▓▓▓░░░▓░░░░░░▓▓▓▓▓                    ░ ░   ▒         ..................................
.................................░░░░░░░░▒▒   ░░░░░ ░                  ▓▓▓▓▓▓░▓▓▓▓░░▓▓▓░░░░░░▓▓                    ░  ░ ░  ▒         ..................................
.................................░░░░░░░░▒    ░░░░░░░░░ ░                 ░▓░░▓▓▓▓▓░▓▓▓░░░░░                   ░ ░░ ░░ ░   ▒         ..................................
.................................░░░░░░░▒▒    ░░░░░░░   ░░                    ▓▓▓▓▓▓▓▓▓░░                   ░░    ░ ░░ ░    ▒        ..................................
.................................░░░░░░░▒▒    ░░░░░░░░░░                      ░▓▓▓▓▓▓▓░░░                     ░░░  ░  ░ ░   ▒        ..................................
.................................░░░░░░░ ▒    ░░░░░░                         ░░░▓▓▓░▓░░░░      ░                  ░ ░░ ░    ▒        ..................................
.................................░░░░░░░ ▒    ░░░░░░░     ▓▓        ▓  ░░ ░░░░░░░░░░░░░  ░   ░░  ▓        █▓       ░  ░ ░   ▒▒       ..................................
..................................░░░░░▒ ▒    ░░░░░░░░  ▓▓██  ▓  ██ ██▓  ▓ ░░░▓░  ░ ░ ░░░░  ▓   ██ ▓█  ▓  ██▓▓  ░░░░  ░ ░    ▒      ...................................
..................................░░░░░▒ ▒▒   ░░░░░░░░░  ▓██  ▓▓  ▓ ██▓  ▓░░░░▓▓░  ░░░░░░░░ ▓  ▓██ ▓   ▓  ██▓▓ ░░░░░░░ ░     ▒      ...................................
..................................░░░░░  ▒░   ░░░░░░░▓░░ ▓███  ▓▓▓▓ ███░  ░░░░▓▓░░░░░░░░░░    ░▓██  ▓▓▓  ███▓ ░░▓▓░░  ░    ▒ ▒      ...................................
...................................░░░░  ▒░    ░░░░▓▓▓▓▓▓░  ███    ██      ░░░░░▓▓▓▓▓░░░░░░░     ███   ████ ░░▓▓▓▓░░  ░    ▒ ▒      ...................................
...................................░░░░ ▒ ░▒    ░░▓▓▓▓▓▓▓▓▓▓ ██████  ▓▓▓░░ ░░░░▓▓▓▓▓▓░░░░░░░░░▓▓▓   █████  ▓▓▓▓▓▓▓░░░░    ▒▒ ▒      ...................................
...................................░░░░ ░ ░░     ░▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓█░░░░░░░▓▓▓▓▓▓▓░░░░ ░░   ░░▓░▓▓░░░░░░░▓▓▓▓▓▓░░      ▒▒ ▒      ...................................
...................................░░░░ ░ ░░      ░▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓██  ░░░░░░░▓▓▓▓▓▓▓░░░░  ░░░░░   ░░░░░░░░░▓▓▓▓▓░░ ░    ▒▒  ▒      ...................................
...................................░░░░▒░░▒░░      ░▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓░░░▓▓▓▓▓▓▓▓░░░  ░░░░░░░░░░░░░░░░░░▓▓░░░░      ▒▒  ▒     ....................................
...................................░░░░▒░░ ░░       ░▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓░░▓▓▓▓▓▓▓▓▓░░░░  ░░░░░░░░░░░░░░░░░░░░░        ▒▒  ▒     ....................................
...................................░░░░░░░ ▒░▒       ░▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓░▓▓▓░░   ░░░░░  ░░░░░░░░░░░░░░░░░░░░         ▒   ▒     ....................................
...................................░░░░░░░░░░░           ░▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓              ░    ░░░░░░░░░░░░░░░            ▒   ▒     ....................................
....................................░░░░░░░░░░░▒  ▒▒        ▓▓▓▓▓▓▓▓▓▓▓▓▓  ░░░░░░░░░░▒▒                         ▒▒▒▒▒   ▒    ▒    .....................................
....................................░░░░░░░░░░ ░▒ ▒▒▒░░░        ▓▓▓▓▓▓   ░░░░░░░░░░░░░▒▒▒      ▒▒▒▒▒░░░░▒▒    ▒▒▒▒▒▒▒  ▒▒    ▒    .....................................
....................................░░░░░░░░░░ ░░░ ▒▒▒░░░░░░          ░░░░░ ░░░░░░░░░░▒░▒     ▒▒▒▒▒▒░░░░░░▒▒▒▒▒░▒▒▒▒   ▒▒         .....................................
.....................................░░░░░░░░░░ ░░░░░  ▒▒░░░░░░░░░░░░░    ░░░░░░░░░  ▒░▒▒    ▒▒▒▒▒░░░░▒▒▒▒▒▒░░▒▒▒   ▒▒▒         ......................................
.....................................░░░░░░░░░░░░░░░░░░  ▒░░░░░░░░░░░   ░░░░░░░░░░░░░░   ▒   ▒▒▒▒▒▒▒░▒▒▒▒▒▒░░░░▒▒▒   ▒▒          ......................................
.....................................░░░░░░░░░░░ ░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░      ▒▒▒▒▒▒▒    ▒  ░░░▒▒▒▒  ▒▒▒          ......................................
......................................░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░ ▒░▒▒▒ ▒▒▒    ▒░░░░░░░░░░▒   ▒▒▒▒      ▒   .......................................
......................................░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░▒  ░░▒▒▒▒▒▒░░░░░░░░░░░░░▒  ░▒▒▒▒       ▒   .......................................
......................................░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░▒ ▒▒░▒▒▒▒▒▒▒░░░░░░░░░░  ░░▒▒▒▒▒       ▒   .......................................
......................................░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░▒▒ ░▒▒▒▒▒▒▒▒▒░░▒░░░░░░ ░░▒▒▒▒▒▒      ▒    .......................................
.......................................░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░▒▒░░▒░▒▒▒ ▒▒▒▒▒░░░░░░░░░▒▒▒▒▒        ▒    .......................................
.......................................░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░▒▒▒▒░▒▒▒▒▒     ░░░░░░░░▒▒▒▒▒▒        ▒    .......................................
.......................................░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░▒▒▒░░▒░▒▒▒▒▒▒  ▒░░░░░░░▒▒▒▒▒▒        ▒     .......................................
NINJA_EOF

    echo ""
    echo -e "                                    \033[1;35m「 天下布武！勝利を掴め！ 」\033[0m"
    echo ""
    echo -e "                               \033[0;36m[ASCII Art: syntax-samurai/ryu - CC0 1.0 Public Domain]\033[0m"
    echo ""

    # 一括起動確認（高速パス）: スクリーン内容ベースで全CLI同時チェック
    # 注: deliver_bootstrap_tmux でも個別に最大30秒待機するため、ここでは短時間チェックのみ。
    # codex は node、gemini は node 等で表示されるため pane_current_command は使用しない。
    CLI_READY_TIMEOUT="${MAS_CLI_READY_TIMEOUT:-15}"
    if ! [[ "$CLI_READY_TIMEOUT" =~ ^[0-9]+$ ]]; then
        CLI_READY_TIMEOUT=15
    fi
    echo "  エージェントCLIの起動を確認中（最大${CLI_READY_TIMEOUT}秒、スクリーン内容判定）..."

    _all_cli_ready=false
    for ((i=1; i<=CLI_READY_TIMEOUT; i++)); do
        _ready_count=0
        _total_count=0

        # 将軍
        _shogun_cli=$(tmux show-options -p -t "shogun:main" -v @agent_cli 2>/dev/null || echo "claude")
        _total_count=$((_total_count + 1))
        if wait_for_cli_ready_tmux "shogun:main" "$_shogun_cli" 0 2>/dev/null; then
            _ready_count=$((_ready_count + 1))
        fi

        # 家老 + 足軽
        for _idx in "${!MULTIAGENT_IDS[@]}"; do
            p=$((PANE_BASE + _idx))
            _pane_target="multiagent:agents.${p}"
            _expected_cli=$(tmux show-options -p -t "$_pane_target" -v @agent_cli 2>/dev/null || echo "claude")
            _total_count=$((_total_count + 1))
            if wait_for_cli_ready_tmux "$_pane_target" "$_expected_cli" 0 2>/dev/null; then
                _ready_count=$((_ready_count + 1))
            fi
        done

        if [ "$_ready_count" -ge "$_total_count" ] && [ "$_total_count" -gt 0 ]; then
            echo "  └─ ${_ready_count}/${_total_count} エージェントCLI起動を確認（${i}秒）"
            _all_cli_ready=true
            break
        fi
        sleep 1
    done

    if [ "$_all_cli_ready" != true ]; then
        log_info "⚠️  一部CLIの起動確認は未完了（タイムアウト）ですが、deliver_bootstrap_tmux で個別待機します"
    fi

    # 各エージェントへ初動命令を投入（CLI起動確認後）
    # deliver_bootstrap_tmux 内でCLI毎のready判定（スクリーン内容ベース）を行うため、
    # ここでの一括待機は不要。将軍への注入を最後にしてフォーカスを将軍ペインに固定。
    log_info "📜 初動命令をエージェント毎に個別配信中（CLI ready確認つき）"
    for _idx in "${!MULTIAGENT_IDS[@]}"; do
        _agent="${MULTIAGENT_IDS[$_idx]}"
        p=$((PANE_BASE + _idx))
        _agent_cli_type="${MULTIAGENT_CLI[$_agent]:-claude}"
        deliver_bootstrap_tmux "multiagent:agents.${p}" "$_agent" "$_agent_cli_type"
    done
    deliver_bootstrap_tmux "gunshi:main" "gunshi" "$_gunshi_cli_type"
    deliver_bootstrap_tmux "shogun:main" "shogun" "$_shogun_cli_type"
    tmux select-pane -t shogun:main >/dev/null 2>&1 || true
    log_info "📜 初動命令の配信完了"

    # ═══════════════════════════════════════════════════════════════════
    # STEP 6.6: inbox_watcher起動（全エージェント）
    # ═══════════════════════════════════════════════════════════════════
    log_info "📬 メールボックス監視を起動中..."

    # inbox ディレクトリ初期化（シンボリックリンク先のLinux FSに作成）
    mkdir -p "$SCRIPT_DIR/logs"
    for agent in shogun gunshi "${KARO_AGENTS[@]}" "${ACTIVE_ASHIGARU[@]}"; do
        [ -f "$SCRIPT_DIR/queue/inbox/${agent}.yaml" ] || echo "messages: []" > "$SCRIPT_DIR/queue/inbox/${agent}.yaml"
    done

    # 既存のwatcherと孤児inotifywaitをkill
    pkill -f "inbox_watcher.sh" 2>/dev/null || true
    pkill -f "inotifywait.*queue/inbox" 2>/dev/null || true
    sleep 1

    if command -v inotifywait >/dev/null 2>&1; then
        # 将軍のwatcher（ntfy受信の自動起床に必要）
        # 安全モード: phase2/phase3エスカレーションは無効、timeout周期処理も無効（event-drivenのみ）
        _shogun_watcher_cli=$(tmux show-options -p -t "shogun:main" -v @agent_cli 2>/dev/null || echo "claude")
        nohup env ASW_DISABLE_ESCALATION=1 ASW_PROCESS_TIMEOUT=0 ASW_DISABLE_NORMAL_NUDGE=0 \
            MUX_TYPE=tmux bash "$SCRIPT_DIR/scripts/inbox_watcher.sh" shogun "shogun:main" "$_shogun_watcher_cli" "tmux" \
            >> "$SCRIPT_DIR/logs/inbox_watcher_shogun.log" 2>&1 &
        disown

        # 軍師 watcher
        _gunshi_watcher_cli=$(tmux show-options -p -t "gunshi:main" -v @agent_cli 2>/dev/null || echo "claude")
        nohup env ASW_DISABLE_ESCALATION=1 ASW_PROCESS_TIMEOUT=0 ASW_DISABLE_NORMAL_NUDGE=0 \
            MUX_TYPE=tmux bash "$SCRIPT_DIR/scripts/inbox_watcher.sh" gunshi "gunshi:main" "$_gunshi_watcher_cli" "tmux" \
            >> "$SCRIPT_DIR/logs/inbox_watcher_gunshi.log" 2>&1 &
        disown

        # 家老 + 足軽 watcher
        for _idx in "${!MULTIAGENT_IDS[@]}"; do
            _agent="${MULTIAGENT_IDS[$_idx]}"
            p=$((PANE_BASE + _idx))
            _agent_watcher_cli=$(tmux show-options -p -t "multiagent:agents.${p}" -v @agent_cli 2>/dev/null || echo "claude")
            nohup env ASW_DISABLE_ESCALATION=1 ASW_PROCESS_TIMEOUT=0 ASW_DISABLE_NORMAL_NUDGE=0 \
                MUX_TYPE=tmux bash "$SCRIPT_DIR/scripts/inbox_watcher.sh" "$_agent" "multiagent:agents.${p}" "$_agent_watcher_cli" "tmux" \
                >> "$SCRIPT_DIR/logs/inbox_watcher_${_agent}.log" 2>&1 &
            disown
        done

        _watcher_total=$((2 + ${#MULTIAGENT_IDS[@]}))
        log_success "  └─ ${_watcher_total}エージェント分のinbox_watcher起動完了"
    else
        log_info "⚠️  inotifywait 未導入のため inbox_watcher はスキップ（sudo apt install -y inotify-tools）"
    fi

    # STEP 6.7 は廃止 — CLAUDE.md Session Start (step 1: tmux agent_id) で各自が自律的に
    # 自分のinstructions/*.mdを読み込む。検証済み (2026-02-08)。
    log_info "📜 指示書読み込みは各エージェントが自律実行（CLAUDE.md Session Start）"
    if [ -x "$SCRIPT_DIR/scripts/history_book.sh" ]; then
        bash "$SCRIPT_DIR/scripts/history_book.sh" >/dev/null 2>&1 || true
    fi
    echo ""
fi

# ═══════════════════════════════════════════════════════════════════════════════
# STEP 6.8: ntfy入力リスナー起動
# ═══════════════════════════════════════════════════════════════════════════════
NTFY_TOPIC=$(grep 'ntfy_topic:' ./config/settings.yaml 2>/dev/null | awk '{print $2}' | tr -d '"' || true)
if [ -n "$NTFY_TOPIC" ]; then
    pkill -f "ntfy_listener.sh" 2>/dev/null || true
    [ ! -f ./queue/ntfy_inbox.yaml ] && echo "inbox:" > ./queue/ntfy_inbox.yaml
    nohup bash "$SCRIPT_DIR/scripts/ntfy_listener.sh" &>/dev/null &
    disown
    log_info "📱 ntfy入力リスナー起動 (topic: $NTFY_TOPIC)"
else
    log_info "📱 ntfy未設定のためリスナーはスキップ"
fi
echo ""

# ═══════════════════════════════════════════════════════════════════════════════
# STEP 7: 環境確認・完了メッセージ
# ═══════════════════════════════════════════════════════════════════════════════
log_info "🔍 陣容を確認中..."
echo ""
echo "  ┌──────────────────────────────────────────────────────────┐"
echo "  │  📺 Tmux陣容 (Sessions)                                  │"
echo "  └──────────────────────────────────────────────────────────┘"
tmux list-sessions | sed 's/^/     /'
echo ""
echo "  ┌──────────────────────────────────────────────────────────┐"
echo "  │  📋 布陣図 (Formation)                                   │"
echo "  └──────────────────────────────────────────────────────────┘"
echo ""
echo "     【shogunセッション】将軍の本陣"
echo "     ┌─────────────────────────────┐"
echo "     │  Pane 0: 将軍 (SHOGUN)      │  ← 総大将・プロジェクト統括"
echo "     └─────────────────────────────┘"
echo ""
echo "     【gunshiセッション】軍師の陣"
echo "     ┌─────────────────────────────┐"
echo "     │  Pane 0: 軍師 (GUNSHI)      │  ← 戦略・分析・助言"
echo "     └─────────────────────────────┘"
echo ""
echo "     【multiagentセッション】家老・足軽の陣（${MULTIAGENT_COUNT}ペイン）"
echo "     ┌─────────────────────────────────────────────┐"
for i in "${!MULTIAGENT_IDS[@]}"; do
    _pane=$((PANE_BASE + i))
    _agent="${MULTIAGENT_IDS[$i]}"
    if [[ "$_agent" == karo* ]]; then
        echo "     │  Pane ${_pane}: ${_agent} (家老)             │"
    else
        echo "     │  Pane ${_pane}: ${_agent} (足軽)             │"
    fi
done
echo "     └─────────────────────────────────────────────┘"
echo ""

echo ""
echo "  ╔══════════════════════════════════════════════════════════╗"
echo "  ║  🏯 出陣準備完了！天下布武！                              ║"
echo "  ╚══════════════════════════════════════════════════════════╝"
echo ""

if [ "$SETUP_ONLY" = true ]; then
    echo "  ⚠️  セットアップのみモード: CLIは未起動です"
    echo ""
    echo "  手動でCLIを起動するには:"
    echo "  ┌──────────────────────────────────────────────────────────┐"
    echo "  │  # 将軍を召喚                                            │"
    echo "  │  tmux send-keys -t shogun:main \\                         │"
    echo "  │    '$(build_cli_command_with_type "shogun" "${_shogun_cli_type:-$(resolve_cli_type_for_agent "shogun" 2>/dev/null || echo claude)}")' Enter  │"
    echo "  │                                                          │"
    echo "  │  # 軍師を召喚                                            │"
    echo "  │  tmux send-keys -t gunshi:main \\                         │"
    echo "  │    '$(build_cli_command_with_type "gunshi" "${_gunshi_cli_type:-$(resolve_cli_type_for_agent "gunshi" 2>/dev/null || echo claude)}")' Enter  │"
    echo "  │                                                          │"
    echo "  │  # 家老・足軽は settings.yaml に従い個別起動             │"
    echo "  │  cat queue/runtime/agent_cli.tsv                         │"
    echo "  └──────────────────────────────────────────────────────────┘"
    echo ""
fi

echo "  次のステップ:"
echo "  ┌──────────────────────────────────────────────────────────┐"
echo "  │  将軍の本陣にアタッチして命令を開始:                      │"
echo "  │     tmux attach-session -t shogun   (または: css)        │"
echo "  │                                                          │"
echo "  │  軍師の陣へアタッチする:                                  │"
echo "  │     tmux attach-session -t gunshi   (または: csg)        │"
echo "  │                                                          │"
echo "  │  家老・足軽の陣を確認する:                                │"
echo "  │     tmux attach-session -t multiagent   (または: csm)    │"
echo "  │                                                          │"
echo "  │  既存の全陣を一望する御座の間を開く:                      │"
echo "  │     bash scripts/goza_no_ma.sh   (または: cgo)           │"
echo "  │                                                          │"
echo "  │  ※ 各エージェントは指示書を読み込み済み。                 │"
echo "  │    すぐに命令を開始できます。                             │"
echo "  └──────────────────────────────────────────────────────────┘"
echo ""
echo "  ════════════════════════════════════════════════════════════"
echo "   天下布武！勝利を掴め！ (Tenka Fubu! Seize victory!)"
echo "  ════════════════════════════════════════════════════════════"
echo ""

# ═══════════════════════════════════════════════════════════════════════════════
# STEP 8: Windows Terminal でタブを開く（-t オプション時のみ）
# ═══════════════════════════════════════════════════════════════════════════════
if [ "$OPEN_TERMINAL" = true ]; then
    log_info "📺 Windows Terminal でタブを展開中..."

    # Windows Terminal が利用可能か確認
    if command -v wt.exe &> /dev/null; then
        wt.exe -w 0 new-tab wsl.exe -e bash -c "tmux attach-session -t shogun" \; new-tab wsl.exe -e bash -c "tmux attach-session -t gunshi" \; new-tab wsl.exe -e bash -c "tmux attach-session -t multiagent"
        log_success "  └─ ターミナルタブ展開完了"
    else
        log_info "  └─ wt.exe が見つかりません。手動でアタッチしてください。"
    fi
    echo ""
fi
