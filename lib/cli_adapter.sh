#!/usr/bin/env bash
# cli_adapter.sh — CLI抽象化レイヤー
# Multi-CLI統合設計書 (reports/design_multi_cli_support.md) §2.2 準拠
#
# 提供関数:
#   get_cli_type(agent_id)                  → "claude" | "codex" | "copilot" | "kimi" | "gemini" | "localapi"
#   build_cli_command(agent_id)             → 完全なコマンド文字列
#   get_role_instruction_file(agent_id)     → 役職共通指示書パス
#   get_instruction_file(agent_id [,cli_type]) → CLI最適化指示書パス
#   validate_cli_availability(cli_type)     → 0=OK, 1=NG
#   get_agent_model(agent_id)               → "opus" | "sonnet" | "haiku" | "k2.5"

# プロジェクトルートを基準にsettings.yamlのパスを解決
CLI_ADAPTER_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
CLI_ADAPTER_PROJECT_ROOT="$(cd "${CLI_ADAPTER_DIR}/.." && pwd)"
CLI_ADAPTER_SETTINGS="${CLI_ADAPTER_SETTINGS:-${CLI_ADAPTER_PROJECT_ROOT}/config/settings.yaml}"

# 許可されたCLI種別
CLI_ADAPTER_ALLOWED_CLIS="claude codex copilot kimi gemini localapi"

# --- 内部ヘルパー ---

# _cli_adapter_read_yaml key [fallback]
# python3でsettings.yamlから値を読み取る
_cli_adapter_read_yaml() {
    local key_path="$1"
    local fallback="${2:-}"
    local result
    result=$(python3 -c "
import yaml, sys
try:
    with open('${CLI_ADAPTER_SETTINGS}') as f:
        cfg = yaml.safe_load(f) or {}
    keys = '${key_path}'.split('.')
    val = cfg
    for k in keys:
        if isinstance(val, dict):
            val = val.get(k)
        else:
            val = None
            break
    if val is not None:
        print(val)
    else:
        print('${fallback}')
except Exception:
    print('${fallback}')
" 2>/dev/null)
    if [[ -z "$result" ]]; then
        echo "$fallback"
    else
        echo "$result"
    fi
}

# _cli_adapter_is_valid_cli cli_type
# 許可されたCLI種別かチェック
_cli_adapter_is_valid_cli() {
    local cli_type="$1"
    local allowed
    for allowed in $CLI_ADAPTER_ALLOWED_CLIS; do
        [[ "$cli_type" == "$allowed" ]] && return 0
    done
    return 1
}

# _cli_adapter_pick_executable primary fallback
# primary が存在しなければ fallback を返す（どちらも無い場合は primary）
_cli_adapter_pick_executable() {
    local primary="$1"
    local fallback="$2"

    if command -v "$primary" >/dev/null 2>&1; then
        echo "$primary"
        return 0
    fi
    if command -v "$fallback" >/dev/null 2>&1; then
        echo "$fallback"
        return 0
    fi
    echo "$primary"
}

# --- 公開API ---

# get_cli_type(agent_id)
# 指定エージェントが使用すべきCLI種別を返す
# フォールバック: cli.agents.{id}.type → cli.agents.{id}(文字列) → cli.default → "claude"
get_cli_type() {
    local agent_id="$1"
    if [[ -z "$agent_id" ]]; then
        echo "claude"
        return 0
    fi

    local result
    result=$(python3 -c "
import yaml, sys
try:
    with open('${CLI_ADAPTER_SETTINGS}') as f:
        cfg = yaml.safe_load(f) or {}
    cli = cfg.get('cli', {})
    if not isinstance(cli, dict):
        print('claude'); sys.exit(0)
    agents = cli.get('agents', {})
    if not isinstance(agents, dict):
        print(cli.get('default', 'claude') if cli.get('default', 'claude') in ('claude','codex','copilot','kimi','gemini','localapi') else 'claude')
        sys.exit(0)
    agent_cfg = agents.get('${agent_id}')
    if isinstance(agent_cfg, dict):
        t = agent_cfg.get('type', '')
        if t in ('claude', 'codex', 'copilot', 'kimi', 'gemini', 'localapi'):
            print(t); sys.exit(0)
    elif isinstance(agent_cfg, str):
        if agent_cfg in ('claude', 'codex', 'copilot', 'kimi', 'gemini', 'localapi'):
            print(agent_cfg); sys.exit(0)
    default = cli.get('default', 'claude')
    if default in ('claude', 'codex', 'copilot', 'kimi', 'gemini', 'localapi'):
        print(default)
    else:
        print('claude', file=sys.stderr)
        print('claude')
except Exception as e:
    print('claude', file=sys.stderr)
    print('claude')
" 2>/dev/null)

    if [[ -z "$result" ]]; then
        echo "claude"
    else
        if ! _cli_adapter_is_valid_cli "$result"; then
            echo "[WARN] Invalid CLI type '$result' for agent '$agent_id'. Falling back to 'claude'." >&2
            echo "claude"
        else
            echo "$result"
        fi
    fi
}

# build_cli_command(agent_id)
# エージェントを起動するための完全なコマンド文字列を返す
build_cli_command() {
    local agent_id="$1"
    local cli_type
    cli_type=$(get_cli_type "$agent_id")
    build_cli_command_with_type "$agent_id" "$cli_type"
}

# build_cli_command_with_type(agent_id, cli_type)
# 指定CLI種別でエージェント起動コマンドを返す
build_cli_command_with_type() {
    local agent_id="$1"
    local cli_type="$2"
    local model
    model=$(get_agent_model "$agent_id")

    case "$cli_type" in
        claude)
            local cmd="claude"
            if [[ -n "$model" ]]; then
                cmd="$cmd --model $model"
            fi
            cmd="$cmd --dangerously-skip-permissions"
            echo "$cmd"
            ;;
        codex)
            echo "codex --dangerously-bypass-approvals-and-sandbox --no-alt-screen"
            ;;
        copilot)
            echo "copilot --yolo"
            ;;
        kimi)
            local kimi_bin
            kimi_bin=$(_cli_adapter_pick_executable "kimi" "kimi-cli")
            local cmd="${kimi_bin} --yolo"
            if [[ -n "$model" ]]; then
                cmd="$cmd --model $model"
            fi
            echo "$cmd"
            ;;
        gemini)
            local gemini_bin
            gemini_bin=$(_cli_adapter_pick_executable "gemini" "gemini-cli")
            local cmd
            cmd=$(_cli_adapter_read_yaml "cli.commands.gemini" "${gemini_bin} --yolo")
            if [[ -n "$model" && "$model" != "auto" && "$model" != "default" ]]; then
                cmd="$cmd --model $model"
            fi
            echo "$cmd"
            ;;
        localapi)
            # OpenAI互換ローカルAPI向けの軽量REPLクライアント（設定で上書き可）
            _cli_adapter_read_yaml "cli.commands.localapi" "python3 scripts/localapi_repl.py"
            ;;
        *)
            echo "claude --dangerously-skip-permissions"
            ;;
    esac
}

# get_first_available_cli()
# 現在の環境で利用可能なCLIを優先順で1つ返す
get_first_available_cli() {
    local c
    for c in codex gemini localapi claude copilot kimi; do
        case "$c" in
            claude)
                command -v claude &>/dev/null && { echo "claude"; return 0; }
                ;;
            codex)
                command -v codex &>/dev/null && { echo "codex"; return 0; }
                ;;
            copilot)
                command -v copilot &>/dev/null && { echo "copilot"; return 0; }
                ;;
            kimi)
                (command -v kimi &>/dev/null || command -v kimi-cli &>/dev/null) && { echo "kimi"; return 0; }
                ;;
            gemini)
                (command -v gemini &>/dev/null || command -v gemini-cli &>/dev/null) && { echo "gemini"; return 0; }
                ;;
            localapi)
                command -v python3 &>/dev/null && { echo "localapi"; return 0; }
                ;;
        esac
    done
    return 1
}

# resolve_cli_type_for_agent(agent_id)
# 設定上のCLIが未導入なら利用可能なCLIにフォールバックする
resolve_cli_type_for_agent() {
    local agent_id="$1"
    local requested
    requested=$(get_cli_type "$agent_id")

    if validate_cli_availability "$requested" >/dev/null 2>&1; then
        echo "$requested"
        return 0
    fi

    local fallback
    fallback=$(get_first_available_cli 2>/dev/null || true)
    if [[ -n "$fallback" ]]; then
        echo "[WARN] CLI '$requested' for agent '$agent_id' is unavailable. Falling back to '$fallback'." >&2
        echo "$fallback"
        return 0
    fi

    echo "$requested"
    return 0
}

# get_role_instruction_file(agent_id)
# 役職共通（CLI非依存）の正本指示書パスを返す
get_role_instruction_file() {
    local agent_id="$1"
    local role

    case "$agent_id" in
        shogun)    role="shogun" ;;
        karo|karo[1-9]*|karo_gashira) role="karo" ;;
        ashigaru*) role="ashigaru" ;;
        *)
            echo "" >&2
            return 1
            ;;
    esac

    echo "instructions/${role}.md"
}

# get_instruction_file(agent_id [,cli_type])
# CLI最適化済みの指示書ファイルのパスを返す
get_instruction_file() {
    local agent_id="$1"
    local cli_type="${2:-$(get_cli_type "$agent_id")}"
    local role

    case "$agent_id" in
        shogun)    role="shogun" ;;
        karo|karo[1-9]*|karo_gashira) role="karo" ;;
        ashigaru*) role="ashigaru" ;;
        *)
            echo "" >&2
            return 1
            ;;
    esac

    case "$cli_type" in
        claude)   echo "instructions/generated/${role}.md" ;;
        codex)    echo "instructions/generated/codex-${role}.md" ;;
        copilot)  echo "instructions/generated/copilot-${role}.md" ;;
        kimi)     echo "instructions/generated/kimi-${role}.md" ;;
        gemini)   echo "instructions/generated/gemini-${role}.md" ;;
        localapi) echo "instructions/generated/localapi-${role}.md" ;;
        *)        echo "instructions/generated/${role}.md" ;;
    esac
}

# validate_cli_availability(cli_type)
# 指定CLIがシステムにインストールされているか確認
# 0=利用可能, 1=利用不可
validate_cli_availability() {
    local cli_type="$1"
    case "$cli_type" in
        claude)
            command -v claude &>/dev/null || {
                echo "[ERROR] Claude Code CLI not found. Install from https://claude.ai/download" >&2
                return 1
            }
            ;;
        codex)
            command -v codex &>/dev/null || {
                echo "[ERROR] OpenAI Codex CLI not found. Install with: npm install -g @openai/codex" >&2
                return 1
            }
            ;;
        copilot)
            command -v copilot &>/dev/null || {
                echo "[ERROR] GitHub Copilot CLI not found. Install with: brew install copilot-cli" >&2
                return 1
            }
            ;;
        kimi)
            if ! command -v kimi-cli &>/dev/null && ! command -v kimi &>/dev/null; then
                echo "[ERROR] Kimi CLI not found. Install from https://platform.moonshot.cn/" >&2
                return 1
            fi
            ;;
        gemini)
            if ! command -v gemini &>/dev/null && ! command -v gemini-cli &>/dev/null; then
                echo "[ERROR] Gemini CLI not found. Install Gemini CLI and ensure 'gemini' or 'gemini-cli' is in PATH." >&2
                return 1
            fi
            ;;
        localapi)
            if ! command -v python3 &>/dev/null; then
                echo "[ERROR] python3 not found. localapi mode requires python3." >&2
                return 1
            fi
            ;;
        *)
            echo "[ERROR] Unknown CLI type: '$cli_type'. Allowed: $CLI_ADAPTER_ALLOWED_CLIS" >&2
            return 1
            ;;
    esac
    return 0
}

# get_agent_model(agent_id)
# エージェントが使用すべきモデル名を返す
get_agent_model() {
    local agent_id="$1"

    # まずsettings.yamlのcli.agents.{id}.modelを確認
    local model_from_yaml
    model_from_yaml=$(_cli_adapter_read_yaml "cli.agents.${agent_id}.model" "")

    if [[ -n "$model_from_yaml" ]]; then
        echo "$model_from_yaml"
        return 0
    fi

    # 既存のmodelsセクションを確認
    local model_from_models
    model_from_models=$(_cli_adapter_read_yaml "models.${agent_id}" "")

    if [[ -n "$model_from_models" ]]; then
        echo "$model_from_models"
        return 0
    fi

    # デフォルトロジック（CLI種別に応じた初期値）
    local cli_type
    cli_type=$(get_cli_type "$agent_id")

    case "$cli_type" in
        kimi)
            # Kimi CLI用デフォルトモデル
            case "$agent_id" in
                shogun|karo|karo[1-9]*|karo_gashira) echo "k2.5" ;;
                ashigaru*)      echo "k2.5" ;;
                *)              echo "k2.5" ;;
            esac
            ;;
        gemini)
            case "$agent_id" in
                shogun|karo|karo[1-9]*|karo_gashira) echo "auto" ;;
                ashigaru*)      echo "auto" ;;
                *)              echo "auto" ;;
            esac
            ;;
        localapi)
            case "$agent_id" in
                shogun|karo|karo[1-9]*|karo_gashira) echo "local-model" ;;
                ashigaru*)      echo "local-model" ;;
                *)              echo "local-model" ;;
            esac
            ;;
        *)
            # Claude Code/Codex/Copilot用デフォルトモデル（kessen/heiji互換）
            case "$agent_id" in
                shogun|karo|karo[1-9]*|karo_gashira) echo "opus" ;;
                ashigaru[1-4])  echo "sonnet" ;;
                ashigaru[5-8])  echo "opus" ;;
                *)              echo "sonnet" ;;
            esac
            ;;
    esac
}
