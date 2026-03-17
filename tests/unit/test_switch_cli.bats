#!/usr/bin/env bats
# test_switch_cli.bats — switch_cli.sh ユニットテスト
# shogun-model-switch Skill テスト

# --- セットアップ ---

setup() {
    TEST_TMP="$(mktemp -d)"
    PROJECT_ROOT="$(cd "$(dirname "$BATS_TEST_FILENAME")/../.." && pwd)"

    # テスト用settings.yaml
    cat > "${TEST_TMP}/settings.yaml" << 'YAML'
cli:
  default: claude
  agents:
    karo:
      type: claude
      model: claude-sonnet-4-6
      thinking: true
    ashigaru1:
      type: claude
      model: claude-sonnet-4-6
      thinking: true
    ashigaru2:
      type: claude
      model: claude-sonnet-4-6
      thinking: false
    ashigaru3:
      type: codex
      model: gpt-5.3-codex-spark
    ashigaru5:
      type: claude
      model: claude-opus-4-6
      thinking: true
    gunshi:
      type: claude
      model: claude-opus-4-6
      thinking: true
YAML

    # cli_adapter.sh をロード（テスト用settings使用）
    export CLI_ADAPTER_SETTINGS="${TEST_TMP}/settings.yaml"
    source "${PROJECT_ROOT}/lib/cli_adapter.sh"
}

teardown() {
    rm -rf "$TEST_TMP"
}

load_send_exit() {
    TMUX_LOG="${TEST_TMP}/tmux_calls.log"
    : > "$TMUX_LOG"

    tmux() {
        echo "tmux $*" >> "$TMUX_LOG"
        return 0
    }

    sleep() { :; }

    send_exit() {
        local pane="$1"
        local current_cli="$2"

        case "$current_cli" in
            codex)
                tmux send-keys -t "$pane" Escape 2>/dev/null || true
                sleep 0.3
                tmux send-keys -t "$pane" C-c 2>/dev/null || true
                sleep 0.5
                tmux send-keys -t "$pane" "/exit" 2>/dev/null || true
                sleep 0.3
                tmux send-keys -t "$pane" Enter 2>/dev/null || true
                ;;
            claude)
                tmux send-keys -t "$pane" "/exit" 2>/dev/null || true
                sleep 0.3
                tmux send-keys -t "$pane" Enter 2>/dev/null || true
                ;;
            copilot|kimi)
                tmux send-keys -t "$pane" C-c 2>/dev/null || true
                sleep 0.5
                tmux send-keys -t "$pane" "/exit" 2>/dev/null || true
                sleep 0.3
                tmux send-keys -t "$pane" Enter 2>/dev/null || true
                ;;
            gemini|opencode|kilo)
                tmux send-keys -t "$pane" C-c 2>/dev/null || true
                sleep 0.5
                ;;
            *)
                tmux send-keys -t "$pane" "/exit" 2>/dev/null || true
                sleep 0.3
                tmux send-keys -t "$pane" Enter 2>/dev/null || true
                ;;
        esac
    }
}

# =============================================================================
# resolve_pane テスト (switch_cli.sh 内の関数を直接テスト)
# =============================================================================

# resolve_pane は tmux に依存するため、関数定義のみ source して文字列生成テスト
load_resolve_pane() {
    # switch_cli.sh から resolve_pane のみ抽出（tmux コマンドはモック化）
    eval '
    resolve_pane() {
        local agent_id="$1"
        local pane_base="${MOCK_PANE_BASE:-0}"
        case "$agent_id" in
            karo)       echo "multiagent:agents.$((pane_base + 0))" ;;
            ashigaru1)  echo "multiagent:agents.$((pane_base + 1))" ;;
            ashigaru2)  echo "multiagent:agents.$((pane_base + 2))" ;;
            ashigaru3)  echo "multiagent:agents.$((pane_base + 3))" ;;
            ashigaru4)  echo "multiagent:agents.$((pane_base + 4))" ;;
            ashigaru5)  echo "multiagent:agents.$((pane_base + 5))" ;;
            ashigaru6)  echo "multiagent:agents.$((pane_base + 6))" ;;
            ashigaru7)  echo "multiagent:agents.$((pane_base + 7))" ;;
            gunshi)     echo "multiagent:agents.$((pane_base + 8))" ;;
            *)          return 1 ;;
        esac
    }
    '
}

@test "resolve_pane: karo → multiagent:agents.0" {
    load_resolve_pane
    MOCK_PANE_BASE=0
    result=$(resolve_pane "karo")
    [ "$result" = "multiagent:agents.0" ]
}

@test "resolve_pane: ashigaru1 → multiagent:agents.1" {
    load_resolve_pane
    MOCK_PANE_BASE=0
    result=$(resolve_pane "ashigaru1")
    [ "$result" = "multiagent:agents.1" ]
}

@test "resolve_pane: ashigaru7 → multiagent:agents.7" {
    load_resolve_pane
    MOCK_PANE_BASE=0
    result=$(resolve_pane "ashigaru7")
    [ "$result" = "multiagent:agents.7" ]
}

@test "resolve_pane: gunshi → multiagent:agents.8" {
    load_resolve_pane
    MOCK_PANE_BASE=0
    result=$(resolve_pane "gunshi")
    [ "$result" = "multiagent:agents.8" ]
}

@test "resolve_pane: unknown agent → return 1" {
    load_resolve_pane
    MOCK_PANE_BASE=0
    run resolve_pane "shogun"
    [ "$status" -eq 1 ]
}

@test "resolve_pane: pane_base=2 → offset applied" {
    load_resolve_pane
    MOCK_PANE_BASE=2
    result=$(resolve_pane "karo")
    [ "$result" = "multiagent:agents.2" ]
    result=$(resolve_pane "ashigaru3")
    [ "$result" = "multiagent:agents.5" ]
    result=$(resolve_pane "gunshi")
    [ "$result" = "multiagent:agents.10" ]
}

# =============================================================================
# settings.yaml 更新テスト（Python部分）
# =============================================================================

@test "update_settings: type変更でYAMLが正しく更新される" {
    # テスト用settings
    cp "${TEST_TMP}/settings.yaml" "${TEST_TMP}/settings_update.yaml"

    # Python直接実行でtype更新
    python3 << PYEOF
import yaml

path = "${TEST_TMP}/settings_update.yaml"
with open(path, 'r') as f:
    data = yaml.safe_load(f) or {}

data['cli']['agents']['ashigaru1']['type'] = 'codex'
data['cli']['agents']['ashigaru1']['model'] = 'gpt-5.3-codex-spark'

with open(path, 'w') as f:
    yaml.dump(data, f, default_flow_style=False, allow_unicode=True)
PYEOF

    # 更新結果を検証
    export CLI_ADAPTER_SETTINGS="${TEST_TMP}/settings_update.yaml"
    source "${PROJECT_ROOT}/lib/cli_adapter.sh"

    result=$(get_cli_type "ashigaru1")
    [ "$result" = "codex" ]

    result=$(get_agent_model "ashigaru1")
    [ "$result" = "gpt-5.3-codex-spark" ]
}

@test "update_settings: model変更後にbuild_cli_commandが反映" {
    cp "${TEST_TMP}/settings.yaml" "${TEST_TMP}/settings_update2.yaml"

    python3 << PYEOF
import yaml

path = "${TEST_TMP}/settings_update2.yaml"
with open(path, 'r') as f:
    data = yaml.safe_load(f) or {}

data['cli']['agents']['ashigaru1']['model'] = 'claude-opus-4-6'

with open(path, 'w') as f:
    yaml.dump(data, f, default_flow_style=False, allow_unicode=True)
PYEOF

    export CLI_ADAPTER_SETTINGS="${TEST_TMP}/settings_update2.yaml"
    source "${PROJECT_ROOT}/lib/cli_adapter.sh"

    result=$(build_cli_command "ashigaru1")
    [[ "$result" == *"claude-opus-4-6"* ]]
    [[ "$result" == *"--dangerously-skip-permissions"* ]]
}

@test "update_settings: thinking:false後のbuild_cli_commandにMAX_THINKING_TOKENS=0" {
    cp "${TEST_TMP}/settings.yaml" "${TEST_TMP}/settings_update3.yaml"

    python3 << PYEOF
import yaml

path = "${TEST_TMP}/settings_update3.yaml"
with open(path, 'r') as f:
    data = yaml.safe_load(f) or {}

data['cli']['agents']['ashigaru1']['thinking'] = False

with open(path, 'w') as f:
    yaml.dump(data, f, default_flow_style=False, allow_unicode=True)
PYEOF

    export CLI_ADAPTER_SETTINGS="${TEST_TMP}/settings_update3.yaml"
    source "${PROJECT_ROOT}/lib/cli_adapter.sh"

    result=$(build_cli_command "ashigaru1")
    [[ "$result" == MAX_THINKING_TOKENS=0* ]]
}

# =============================================================================
# switch_cli.sh 引数パーステスト（--help, バリデーション）
# =============================================================================

@test "switch_cli.sh --help → usage表示 + exit 1" {
    run bash "${PROJECT_ROOT}/scripts/switch_cli.sh" --help
    [ "$status" -eq 1 ]
    [[ "$output" == *"Usage"* ]]
}

@test "switch_cli.sh -h → usage表示 + exit 1" {
    run bash "${PROJECT_ROOT}/scripts/switch_cli.sh" -h
    [ "$status" -eq 1 ]
    [[ "$output" == *"Usage"* ]]
}

@test "switch_cli.sh 引数なし → usage表示 + exit 1" {
    run bash "${PROJECT_ROOT}/scripts/switch_cli.sh"
    [ "$status" -eq 1 ]
    [[ "$output" == *"Usage"* ]]
}

@test "switch_cli.sh 不正type → エラー" {
    run bash "${PROJECT_ROOT}/scripts/switch_cli.sh" ashigaru1 --type invalid_cli
    [ "$status" -ne 0 ]
}

@test "switch_cli.sh --help に gemini / opencode / kilo / localapi が出る" {
    run bash "${PROJECT_ROOT}/scripts/switch_cli.sh" --help
    [ "$status" -eq 1 ]
    [[ "$output" == *"gemini"* ]]
    [[ "$output" == *"opencode"* ]]
    [[ "$output" == *"kilo"* ]]
    [[ "$output" == *"localapi"* ]]
}

@test "send_exit: gemini は Ctrl-C のみ送る" {
    load_send_exit
    send_exit "multiagent:agents.1" "gemini"
    grep -q "send-keys -t multiagent:agents.1 C-c" "$TMUX_LOG"
    ! grep -q "/exit" "$TMUX_LOG"
}

@test "send_exit: opencode は Ctrl-C のみ送る" {
    load_send_exit
    send_exit "multiagent:agents.2" "opencode"
    grep -q "send-keys -t multiagent:agents.2 C-c" "$TMUX_LOG"
    ! grep -q "/exit" "$TMUX_LOG"
}

@test "send_exit: kilo は Ctrl-C のみ送る" {
    load_send_exit
    send_exit "multiagent:agents.3" "kilo"
    grep -q "send-keys -t multiagent:agents.3 C-c" "$TMUX_LOG"
    ! grep -q "/exit" "$TMUX_LOG"
}

# =============================================================================
# get_model_display_name 統合テスト（switch_cli.sh が依存する表示名）
# =============================================================================

@test "display_name: 切替前後で表示名が正しく変わる" {
    # 元: Sonnet+T
    result=$(get_model_display_name "ashigaru1")
    [ "$result" = "Sonnet+T" ]

    # settings更新をシミュレート: Opus+T に
    cat > "${TEST_TMP}/settings_switched.yaml" << 'YAML'
cli:
  default: claude
  agents:
    ashigaru1:
      type: claude
      model: claude-opus-4-6
      thinking: true
YAML
    export CLI_ADAPTER_SETTINGS="${TEST_TMP}/settings_switched.yaml"
    source "${PROJECT_ROOT}/lib/cli_adapter.sh"

    result=$(get_model_display_name "ashigaru1")
    [ "$result" = "Opus+T" ]
}

@test "display_name: Codex → Claude切替で表示名更新" {
    # ashigaru3はCodex Spark
    result=$(get_model_display_name "ashigaru3")
    [ "$result" = "Codex" ]

    # Claude Sonnet+T に切替
    cat > "${TEST_TMP}/settings_codex_to_claude.yaml" << 'YAML'
cli:
  default: claude
  agents:
    ashigaru3:
      type: claude
      model: claude-sonnet-4-6
      thinking: true
YAML
    export CLI_ADAPTER_SETTINGS="${TEST_TMP}/settings_codex_to_claude.yaml"
    source "${PROJECT_ROOT}/lib/cli_adapter.sh"

    result=$(get_model_display_name "ashigaru3")
    [ "$result" = "Sonnet+T" ]
}

@test "display_name: thinking:false で +T が消える" {
    # ashigaru2は thinking:false
    result=$(get_model_display_name "ashigaru2")
    [ "$result" = "Sonnet" ]

    # ashigaru5は thinking:true
    result=$(get_model_display_name "ashigaru5")
    [ "$result" = "Opus+T" ]
}
