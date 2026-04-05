#!/usr/bin/env bats
# test_cli_adapter.bats — cli_adapter.sh ユニットテスト
# Multi-CLI統合設計書 §4.1 準拠

# --- セットアップ ---

setup() {
    # テスト用のtmpディレクトリ
    TEST_TMP="$(mktemp -d)"

    # プロジェクトルート
    PROJECT_ROOT="$(cd "$(dirname "$BATS_TEST_FILENAME")/../.." && pwd)"

    # デフォルトsettings（cliセクションなし = 後方互換テスト）
    cat > "${TEST_TMP}/settings_none.yaml" << 'YAML'
language: ja
shell: bash
display_mode: shout
YAML

    # claude only settings
    cat > "${TEST_TMP}/settings_claude_only.yaml" << 'YAML'
cli:
  default: claude
YAML

    # mixed CLI settings (dict形式)
    cat > "${TEST_TMP}/settings_mixed.yaml" << 'YAML'
cli:
  default: claude
  agents:
    shogun:
      type: claude
      model: opus
    karo:
      type: claude
      model: opus
    ashigaru1:
      type: claude
      model: sonnet
    ashigaru2:
      type: claude
      model: sonnet
    ashigaru3:
      type: claude
      model: sonnet
    ashigaru4:
      type: claude
      model: sonnet
    ashigaru5:
      type: codex
    ashigaru6:
      type: codex
    ashigaru7:
      type: copilot
    ashigaru8:
      type: copilot
YAML

    # 文字列形式のagent設定
    cat > "${TEST_TMP}/settings_string_agents.yaml" << 'YAML'
cli:
  default: claude
  agents:
    ashigaru5: codex
    ashigaru7: copilot
YAML

    # 不正CLI名
    cat > "${TEST_TMP}/settings_invalid_cli.yaml" << 'YAML'
cli:
  default: claudee
  agents:
    ashigaru1: invalid_cli
YAML

    # codexデフォルト
    cat > "${TEST_TMP}/settings_codex_default.yaml" << 'YAML'
cli:
  default: codex
YAML

    cat > "${TEST_TMP}/settings_codex_shared_auth_off.yaml" << 'YAML'
cli:
  default: codex
  codex:
    shared_auth: false
YAML

    cat > "${TEST_TMP}/settings_codex_shared_auth_custom.yaml" << 'YAML'
cli:
  default: codex
  codex:
    shared_auth: true
    shared_auth_file: context/local/codex-auth/auth.json
YAML

    # 空ファイル
    cat > "${TEST_TMP}/settings_empty.yaml" << 'YAML'
YAML

    # YAML構文エラー
    cat > "${TEST_TMP}/settings_broken.yaml" << 'YAML'
cli:
  default: [broken yaml
  agents: {{invalid
YAML

    # モデル指定付き
    cat > "${TEST_TMP}/settings_with_models.yaml" << 'YAML'
cli:
  default: claude
  agents:
    ashigaru1:
      type: claude
      model: haiku
    ashigaru5:
      type: codex
      model: gpt-5
models:
  karo: sonnet
YAML

    # codex model指定
    cat > "${TEST_TMP}/settings_codex_model.yaml" << 'YAML'
cli:
  default: codex
  agents:
    shogun:
      type: codex
      model: gpt-5.3-codex
YAML

    # codex model auto指定（--modelは付与しない）
    cat > "${TEST_TMP}/settings_codex_auto.yaml" << 'YAML'
cli:
  default: codex
  agents:
    shogun:
      type: codex
      model: auto
YAML

    # kimi CLI settings
    cat > "${TEST_TMP}/settings_kimi.yaml" << 'YAML'
cli:
  default: claude
  agents:
    ashigaru3:
      type: kimi
      model: k2.5
    ashigaru4:
      type: kimi
YAML

    # kimi default settings
    cat > "${TEST_TMP}/settings_kimi_default.yaml" << 'YAML'
cli:
  default: kimi
YAML

    # gemini settings
    cat > "${TEST_TMP}/settings_gemini.yaml" << 'YAML'
cli:
  default: claude
  agents:
    ashigaru2:
      type: gemini
      model: auto
YAML

    # gemini thinking settings
    cat > "${TEST_TMP}/settings_gemini_thinking.yaml" << 'YAML'
cli:
  default: gemini
  agents:
    gunshi:
      type: gemini
      model: gemini-3-pro-preview
      thinking_level: low
    ashigaru1:
      type: gemini
      model: gemini-3-flash-preview
      thinking_level: minimal
    ashigaru2:
      type: gemini
      model: gemini-2.5-flash
      thinking_budget: 0
    ashigaru3:
      type: gemini
      model: auto
      thinking_level: high
YAML

    # codex reasoning settings
    cat > "${TEST_TMP}/settings_codex_reasoning.yaml" << 'YAML'
cli:
  default: codex
  agents:
    shogun:
      type: codex
      model: auto
      reasoning_effort: high
    gunshi:
      type: codex
      model: gpt-5.4
      reasoning_effort: none
YAML

    cat > "${TEST_TMP}/settings_shogun_defaults.yaml" << 'YAML'
cli:
  default: codex
  agents:
    shogun:
      type: codex
    gunshi:
      type: codex
    ashigaru1:
      type: gemini
    ashigaru2:
      type: claude
YAML

    cat > "${TEST_TMP}/settings_shogun_gemini_default.yaml" << 'YAML'
cli:
  default: gemini
  agents:
    shogun:
      type: gemini
      model: auto
YAML

    cat > "${TEST_TMP}/settings_shogun_claude_default.yaml" << 'YAML'
cli:
  default: claude
  agents:
    shogun:
      type: claude
      model: opus
YAML

    cat > "${TEST_TMP}/settings_claude_invalid_model.yaml" << 'YAML'
cli:
  default: claude
  agents:
    shogun:
      type: claude
      model: gpt-5.4
    gunshi:
      type: claude
      model: auto
YAML

    # localapi settings
    cat > "${TEST_TMP}/settings_localapi.yaml" << 'YAML'
cli:
  default: claude
  agents:
    ashigaru6:
      type: localapi
      model: qwen2.5-coder
  commands:
    localapi: "python3 scripts/localapi_repl.py"
YAML

    # opencode settings
    cat > "${TEST_TMP}/settings_opencode.yaml" << 'YAML'
cli:
  default: opencode
  agents:
    shogun:
      type: opencode
      model: ollama/qwen3-coder:30b
  commands:
    opencode: "opencode"
YAML

    # kilo settings
    cat > "${TEST_TMP}/settings_kilo.yaml" << 'YAML'
cli:
  default: kilo
  agents:
    gunshi:
      type: kilo
      model: lmstudio/codellama-7b.Q4_0.gguf
  commands:
    kilo: "kilo"
YAML

    cat > "${TEST_TMP}/settings_opencode_global_bin.yaml" << 'YAML'
cli:
  default: opencode
  agents:
    ashigaru1:
      type: opencode
      model: lmstudio/openai/gpt-oss-20b
  commands:
    opencode: "env XDG_DATA_HOME=/tmp/mas_xdg XDG_CACHE_HOME=/tmp/mas_cache /tmp/test-home/.nvm/versions/node/v22.22.0/lib/node_modules/opencode-ai/bin/opencode"
YAML
}

teardown() {
    rm -rf "$TEST_TMP"
}

# ヘルパー: 特定のsettings.yamlでcli_adapterをロード
load_adapter_with() {
    local settings_file="$1"
    export CLI_ADAPTER_SETTINGS="$settings_file"
    source "${PROJECT_ROOT}/lib/cli_adapter.sh"
}

assert_codex_shared_auth_bootstrap() {
    local result="$1"
    local agent_id="$2"
    [[ "$result" == *"mkdir -p ${PROJECT_ROOT}/.shogunate/codex/agents/${agent_id} ${PROJECT_ROOT}/.shogunate/codex/shared"* ]]
    [[ "$result" == *"if [ -f ${PROJECT_ROOT}/.shogunate/codex/agents/${agent_id}/auth.json ] && [ ! -e ${PROJECT_ROOT}/.shogunate/codex/shared/auth.json ]; then cp ${PROJECT_ROOT}/.shogunate/codex/agents/${agent_id}/auth.json ${PROJECT_ROOT}/.shogunate/codex/shared/auth.json; fi"* ]]
    [[ "$result" == *"ln -sfn ${PROJECT_ROOT}/.shogunate/codex/shared/auth.json ${PROJECT_ROOT}/.shogunate/codex/agents/${agent_id}/auth.json"* ]]
    [[ "$result" == *"CODEX_HOME=${PROJECT_ROOT}/.shogunate/codex/agents/${agent_id} NO_UPDATE_NOTIFIER=1 codex"* ]]
}

assert_codex_shared_auth_custom_bootstrap() {
    local result="$1"
    local agent_id="$2"
    [[ "$result" == *"mkdir -p ${PROJECT_ROOT}/.shogunate/codex/agents/${agent_id} ${PROJECT_ROOT}/context/local/codex-auth"* ]]
    [[ "$result" == *"cp ${PROJECT_ROOT}/.shogunate/codex/agents/${agent_id}/auth.json ${PROJECT_ROOT}/context/local/codex-auth/auth.json"* ]]
    [[ "$result" == *"ln -sfn ${PROJECT_ROOT}/context/local/codex-auth/auth.json ${PROJECT_ROOT}/.shogunate/codex/agents/${agent_id}/auth.json"* ]]
}

# =============================================================================
# get_cli_type テスト
# =============================================================================

# --- 正常系 ---

@test "get_cli_type: cliセクションなし → claude (後方互換)" {
    load_adapter_with "${TEST_TMP}/settings_none.yaml"
    result=$(get_cli_type "shogun")
    [ "$result" = "claude" ]
}

@test "get_cli_type: claude only設定 → claude" {
    load_adapter_with "${TEST_TMP}/settings_claude_only.yaml"
    result=$(get_cli_type "ashigaru1")
    [ "$result" = "claude" ]
}

@test "get_cli_type: mixed設定 shogun → claude" {
    load_adapter_with "${TEST_TMP}/settings_mixed.yaml"
    result=$(get_cli_type "shogun")
    [ "$result" = "claude" ]
}

@test "get_cli_type: mixed設定 ashigaru5 → codex" {
    load_adapter_with "${TEST_TMP}/settings_mixed.yaml"
    result=$(get_cli_type "ashigaru5")
    [ "$result" = "codex" ]
}

@test "get_cli_type: mixed設定 ashigaru7 → copilot" {
    load_adapter_with "${TEST_TMP}/settings_mixed.yaml"
    result=$(get_cli_type "ashigaru7")
    [ "$result" = "copilot" ]
}

@test "get_cli_type: mixed設定 ashigaru1 → claude (個別設定)" {
    load_adapter_with "${TEST_TMP}/settings_mixed.yaml"
    result=$(get_cli_type "ashigaru1")
    [ "$result" = "claude" ]
}

@test "get_cli_type: 文字列形式 ashigaru5 → codex" {
    load_adapter_with "${TEST_TMP}/settings_string_agents.yaml"
    result=$(get_cli_type "ashigaru5")
    [ "$result" = "codex" ]
}

@test "get_cli_type: 文字列形式 ashigaru7 → copilot" {
    load_adapter_with "${TEST_TMP}/settings_string_agents.yaml"
    result=$(get_cli_type "ashigaru7")
    [ "$result" = "copilot" ]
}

@test "get_cli_type: kimi設定 ashigaru3 → kimi" {
    load_adapter_with "${TEST_TMP}/settings_kimi.yaml"
    result=$(get_cli_type "ashigaru3")
    [ "$result" = "kimi" ]
}

@test "get_cli_type: kimi設定 ashigaru4 → kimi (モデル指定なし)" {
    load_adapter_with "${TEST_TMP}/settings_kimi.yaml"
    result=$(get_cli_type "ashigaru4")
    [ "$result" = "kimi" ]
}

@test "get_cli_type: kimiデフォルト設定 → kimi" {
    load_adapter_with "${TEST_TMP}/settings_kimi_default.yaml"
    result=$(get_cli_type "ashigaru1")
    [ "$result" = "kimi" ]
}

@test "get_cli_type: gemini設定 ashigaru2 → gemini" {
    load_adapter_with "${TEST_TMP}/settings_gemini.yaml"
    result=$(get_cli_type "ashigaru2")
    [ "$result" = "gemini" ]
}

@test "get_cli_type: localapi設定 ashigaru6 → localapi" {
    load_adapter_with "${TEST_TMP}/settings_localapi.yaml"
    result=$(get_cli_type "ashigaru6")
    [ "$result" = "localapi" ]
}

@test "get_cli_type: opencode設定 shogun → opencode" {
    load_adapter_with "${TEST_TMP}/settings_opencode.yaml"
    result=$(get_cli_type "shogun")
    [ "$result" = "opencode" ]
}

@test "get_cli_type: kilo設定 gunshi → kilo" {
    load_adapter_with "${TEST_TMP}/settings_kilo.yaml"
    result=$(get_cli_type "gunshi")
    [ "$result" = "kilo" ]
}

@test "get_cli_type: 未定義agent → default継承" {
    load_adapter_with "${TEST_TMP}/settings_codex_default.yaml"
    result=$(get_cli_type "ashigaru3")
    [ "$result" = "codex" ]
}

@test "get_cli_type: 空agent_id → claude" {
    load_adapter_with "${TEST_TMP}/settings_mixed.yaml"
    result=$(get_cli_type "")
    [ "$result" = "claude" ]
}

# --- 全ashigaru パターン ---

@test "get_cli_type: mixed設定 ashigaru1-8全パターン" {
    load_adapter_with "${TEST_TMP}/settings_mixed.yaml"
    [ "$(get_cli_type ashigaru1)" = "claude" ]
    [ "$(get_cli_type ashigaru2)" = "claude" ]
    [ "$(get_cli_type ashigaru3)" = "claude" ]
    [ "$(get_cli_type ashigaru4)" = "claude" ]
    [ "$(get_cli_type ashigaru5)" = "codex" ]
    [ "$(get_cli_type ashigaru6)" = "codex" ]
    [ "$(get_cli_type ashigaru7)" = "copilot" ]
    [ "$(get_cli_type ashigaru8)" = "copilot" ]
}

# --- エラー系 ---

@test "get_cli_type: 不正CLI名 → claude フォールバック" {
    load_adapter_with "${TEST_TMP}/settings_invalid_cli.yaml"
    result=$(get_cli_type "ashigaru1")
    [ "$result" = "claude" ]
}

@test "get_cli_type: 不正default → claude フォールバック" {
    load_adapter_with "${TEST_TMP}/settings_invalid_cli.yaml"
    result=$(get_cli_type "karo")
    [ "$result" = "claude" ]
}

@test "get_cli_type: 空YAMLファイル → claude" {
    load_adapter_with "${TEST_TMP}/settings_empty.yaml"
    result=$(get_cli_type "shogun")
    [ "$result" = "claude" ]
}

@test "get_cli_type: YAML構文エラー → claude" {
    load_adapter_with "${TEST_TMP}/settings_broken.yaml"
    result=$(get_cli_type "ashigaru1")
    [ "$result" = "claude" ]
}

@test "get_cli_type: 存在しないファイル → claude" {
    load_adapter_with "/nonexistent/path/settings.yaml"
    result=$(get_cli_type "shogun")
    [ "$result" = "claude" ]
}

# =============================================================================
# build_cli_command テスト
# =============================================================================

@test "build_cli_command: claude + model → claude --model opus --dangerously-skip-permissions" {
    load_adapter_with "${TEST_TMP}/settings_mixed.yaml"
    result=$(build_cli_command "shogun")
    [ "$result" = "MAX_THINKING_TOKENS=0 claude --model opus --dangerously-skip-permissions" ]
}

@test "build_cli_command: claude + model auto → --model を付けない" {
    cat > "${TEST_TMP}/settings_claude_auto.yaml" << 'YAML'
cli:
  default: claude
  agents:
    shogun:
      type: claude
      model: auto
YAML
    load_adapter_with "${TEST_TMP}/settings_claude_auto.yaml"
    result=$(build_cli_command "shogun")
    [ "$result" = "MAX_THINKING_TOKENS=0 claude --dangerously-skip-permissions" ]
}

@test "build_cli_command: codex → NO_UPDATE_NOTIFIER=1 付きで起動" {
    load_adapter_with "${TEST_TMP}/settings_mixed.yaml"
    result=$(build_cli_command "ashigaru5")
    assert_codex_shared_auth_bootstrap "$result" "ashigaru5"
    [[ "$result" == *"--search --dangerously-bypass-approvals-and-sandbox --no-alt-screen" ]]
}

@test "build_cli_command: codex + explicit model → codex --model ... --search --dangerously-bypass-approvals-and-sandbox --no-alt-screen" {
    load_adapter_with "${TEST_TMP}/settings_codex_model.yaml"
    result=$(build_cli_command "shogun")
    assert_codex_shared_auth_bootstrap "$result" "shogun"
    [[ "$result" == *"codex --model gpt-5.3-codex --search --dangerously-bypass-approvals-and-sandbox --no-alt-screen" ]]
}

@test "build_cli_command: codex + reasoning_effort → -c model_reasoning_effort を付与" {
    load_adapter_with "${TEST_TMP}/settings_codex_reasoning.yaml"
    result=$(build_cli_command "shogun")
    assert_codex_shared_auth_bootstrap "$result" "shogun"
    [[ "$result" == *"codex -c model_reasoning_effort='high' --search --dangerously-bypass-approvals-and-sandbox --no-alt-screen" ]]
}

@test "build_cli_command: codex + explicit model + reasoning_effort none を付与" {
    load_adapter_with "${TEST_TMP}/settings_codex_reasoning.yaml"
    result=$(build_cli_command "gunshi")
    assert_codex_shared_auth_bootstrap "$result" "gunshi"
    [[ "$result" == *"codex --model gpt-5.4 -c model_reasoning_effort='none' --search --dangerously-bypass-approvals-and-sandbox --no-alt-screen" ]]
}

@test "build_cli_command: shogun codex は未設定なら reasoning_effort を付けない" {
    load_adapter_with "${TEST_TMP}/settings_shogun_defaults.yaml"
    result=$(build_cli_command "shogun")
    assert_codex_shared_auth_bootstrap "$result" "shogun"
    [[ "$result" == *"codex --search --dangerously-bypass-approvals-and-sandbox --no-alt-screen" ]]
}

@test "build_cli_command: gunshi codex は未設定なら reasoning_effort を付けない" {
    load_adapter_with "${TEST_TMP}/settings_shogun_defaults.yaml"
    result=$(build_cli_command "gunshi")
    assert_codex_shared_auth_bootstrap "$result" "gunshi"
    [[ "$result" == *"codex --search --dangerously-bypass-approvals-and-sandbox --no-alt-screen" ]]
}

@test "build_cli_command: codex + model auto → --model を付けない" {
    load_adapter_with "${TEST_TMP}/settings_codex_auto.yaml"
    result=$(build_cli_command "shogun")
    assert_codex_shared_auth_bootstrap "$result" "shogun"
    [[ "$result" == *"codex --search --dangerously-bypass-approvals-and-sandbox --no-alt-screen" ]]
}

@test "build_cli_command: codex に UI 断片 left が入っていても --model を付けない" {
    cat > "${TEST_TMP}/settings_codex_invalid_model.yaml" << 'YAML'
cli:
  default: codex
  agents:
    ashigaru2:
      type: codex
      model: left
YAML
    load_adapter_with "${TEST_TMP}/settings_codex_invalid_model.yaml"
    result=$(build_cli_command "ashigaru2")
    assert_codex_shared_auth_bootstrap "$result" "ashigaru2"
    [[ "$result" == *"codex --search --dangerously-bypass-approvals-and-sandbox --no-alt-screen" ]]
}

@test "build_cli_command: codex shared_auth false なら agent local auth のみ使う" {
    load_adapter_with "${TEST_TMP}/settings_codex_shared_auth_off.yaml"
    result=$(build_cli_command "shogun")
    [ "$result" = "mkdir -p ${PROJECT_ROOT}/.shogunate/codex/agents/shogun && CODEX_HOME=${PROJECT_ROOT}/.shogunate/codex/agents/shogun NO_UPDATE_NOTIFIER=1 codex --search --dangerously-bypass-approvals-and-sandbox --no-alt-screen" ]
}

@test "build_cli_command: codex shared_auth_file を custom path へ変更できる" {
    load_adapter_with "${TEST_TMP}/settings_codex_shared_auth_custom.yaml"
    result=$(build_cli_command "shogun")
    assert_codex_shared_auth_custom_bootstrap "$result" "shogun"
    [[ "$result" == *"CODEX_HOME=${PROJECT_ROOT}/.shogunate/codex/agents/shogun NO_UPDATE_NOTIFIER=1 codex --search --dangerously-bypass-approvals-and-sandbox --no-alt-screen" ]]
}

@test "build_cli_command: copilot → copilot --yolo" {
    load_adapter_with "${TEST_TMP}/settings_mixed.yaml"
    result=$(build_cli_command "ashigaru7")
    [ "$result" = "copilot --yolo" ]
}

@test "build_cli_command: kimi + model → kimi --yolo --model k2.5" {
    load_adapter_with "${TEST_TMP}/settings_kimi.yaml"
    result=$(build_cli_command "ashigaru3")
    [ "$result" = "kimi --yolo --model k2.5" ]
}

@test "build_cli_command: kimi-cliのみ存在時は kimi-cli を使用" {
    load_adapter_with "${TEST_TMP}/settings_kimi.yaml"
    mkdir -p "${TEST_TMP}/bin"
    cat > "${TEST_TMP}/bin/kimi-cli" << 'SH'
#!/usr/bin/env bash
exit 0
SH
    chmod +x "${TEST_TMP}/bin/kimi-cli"
    PATH="${TEST_TMP}/bin:/usr/bin:/bin" result=$(build_cli_command "ashigaru3")
    [ "$result" = "${TEST_TMP}/bin/kimi-cli --yolo --model k2.5" ]
}

@test "build_cli_command: kimi (モデル指定なし) → kimi --yolo" {
    load_adapter_with "${TEST_TMP}/settings_kimi.yaml"
    result=$(build_cli_command "ashigaru4")
    [ "$result" = "kimi --yolo" ]
}

@test "build_cli_command: gemini + model auto → gemini --yolo" {
    load_adapter_with "${TEST_TMP}/settings_gemini.yaml"
    mkdir -p "${TEST_TMP}/home-empty"
    HOME="${TEST_TMP}/home-empty" PATH="/usr/bin:/bin" result=$(build_cli_command "ashigaru2")
    [ "$result" = "gemini --yolo" ]
}

@test "build_cli_command: gemini 3 pro + thinking_level → per-agent alias を使う" {
    load_adapter_with "${TEST_TMP}/settings_gemini_thinking.yaml"
    mkdir -p "${TEST_TMP}/home-empty"
    HOME="${TEST_TMP}/home-empty" PATH="/usr/bin:/bin" result=$(build_cli_command "gunshi")
    [ "$result" = "gemini --yolo --model mas-gunshi" ]
}

@test "build_cli_command: gemini 3 flash + thinking_level minimal → per-agent alias を使う" {
    load_adapter_with "${TEST_TMP}/settings_gemini_thinking.yaml"
    mkdir -p "${TEST_TMP}/home-empty"
    HOME="${TEST_TMP}/home-empty" PATH="/usr/bin:/bin" result=$(build_cli_command "ashigaru1")
    [ "$result" = "gemini --yolo --model mas-ashigaru1" ]
}

@test "build_cli_command: gemini 2.5 + thinking_budget → per-agent alias を使う" {
    load_adapter_with "${TEST_TMP}/settings_gemini_thinking.yaml"
    mkdir -p "${TEST_TMP}/home-empty"
    HOME="${TEST_TMP}/home-empty" PATH="/usr/bin:/bin" result=$(build_cli_command "ashigaru2")
    [ "$result" = "gemini --yolo --model mas-ashigaru2" ]
}

@test "build_cli_command: gemini auto + thinking_level → inferred alias を使う" {
    load_adapter_with "${TEST_TMP}/settings_gemini_thinking.yaml"
    mkdir -p "${TEST_TMP}/home-empty"
    HOME="${TEST_TMP}/home-empty" PATH="/usr/bin:/bin" result=$(build_cli_command "ashigaru3")
    [ "$result" = "gemini --yolo --model mas-ashigaru3" ]
}

@test "build_cli_command: shogun gemini は未設定なら alias を使わない" {
    load_adapter_with "${TEST_TMP}/settings_shogun_gemini_default.yaml"
    mkdir -p "${TEST_TMP}/home-empty"
    HOME="${TEST_TMP}/home-empty" PATH="/usr/bin:/bin" result=$(build_cli_command "shogun")
    [ "$result" = "gemini --yolo" ]
}

@test "build_cli_command: gemini に gpt 系 model が入っていても auto に丸める" {
    cat > "${TEST_TMP}/settings_gemini_invalid_model.yaml" << 'YAML'
cli:
  default: gemini
  agents:
    shogun:
      type: gemini
      model: gpt-5.4
YAML
    load_adapter_with "${TEST_TMP}/settings_gemini_invalid_model.yaml"
    mkdir -p "${TEST_TMP}/home-empty"
    HOME="${TEST_TMP}/home-empty" PATH="/usr/bin:/bin" result=$(build_cli_command "shogun")
    [ "$result" = "gemini --yolo" ]
}

@test "build_cli_command: shogun claude は未設定でも thinking無効を既定適用" {
    load_adapter_with "${TEST_TMP}/settings_shogun_claude_default.yaml"
    result=$(build_cli_command "shogun")
    [ "$result" = "MAX_THINKING_TOKENS=0 claude --model opus --dangerously-skip-permissions" ]
}

@test "build_cli_command: gemini-cliのみ存在時は gemini-cli を使用" {
    load_adapter_with "${TEST_TMP}/settings_gemini.yaml"
    mkdir -p "${TEST_TMP}/bin"
    cat > "${TEST_TMP}/bin/gemini-cli" << 'SH'
#!/usr/bin/env bash
exit 0
SH
    chmod +x "${TEST_TMP}/bin/gemini-cli"
    mkdir -p "${TEST_TMP}/home-empty"
    HOME="${TEST_TMP}/home-empty" PATH="${TEST_TMP}/bin:/usr/bin:/bin" result=$(build_cli_command "ashigaru2")
    [ "$result" = "${TEST_TMP}/bin/gemini-cli --yolo" ]
}

@test "build_cli_command: localapi → python3 scripts/localapi_repl.py" {
    load_adapter_with "${TEST_TMP}/settings_localapi.yaml"
    result=$(build_cli_command "ashigaru6")
    # model が指定されている場合は LOCALAI_MODEL= が前置される
    [[ "$result" == *"python3 scripts/localapi_repl.py"* ]]
    [[ "$result" == *"LOCALAI_MODEL=qwen2.5-coder"* ]]
}

@test "build_cli_command: opencode + provider/model → opencode --model ..." {
    load_adapter_with "${TEST_TMP}/settings_opencode.yaml"
    result=$(build_cli_command "shogun")
    [ "$result" = "opencode --model ollama/qwen3-coder:30b" ]
}

@test "build_cli_command: kilo + provider/model → kilo --model ..." {
    load_adapter_with "${TEST_TMP}/settings_kilo.yaml"
    result=$(build_cli_command "gunshi")
    [ "$result" = "kilo --model lmstudio/codellama-7b.Q4_0.gguf" ]
}

@test "build_cli_command: opencode global bin絶対パスには node PATH を自動付与する" {
    load_adapter_with "${TEST_TMP}/settings_opencode_global_bin.yaml"
    mkdir -p "${TEST_TMP}/home/.nvm/versions/node/v22.22.0/bin"
    cat > "${TEST_TMP}/home/.nvm/versions/node/v22.22.0/bin/node" << 'SH'
#!/usr/bin/env bash
exit 0
SH
    chmod +x "${TEST_TMP}/home/.nvm/versions/node/v22.22.0/bin/node"
    sed -i "s#/tmp/test-home#${TEST_TMP}/home#g" "${TEST_TMP}/settings_opencode_global_bin.yaml"
    result=$(build_cli_command "ashigaru1")
    [ "$result" = "env PATH=${TEST_TMP}/home/.nvm/versions/node/v22.22.0/bin:\$PATH env XDG_DATA_HOME=/tmp/mas_xdg XDG_CACHE_HOME=/tmp/mas_cache ${TEST_TMP}/home/.nvm/versions/node/v22.22.0/lib/node_modules/opencode-ai/bin/opencode --model lmstudio/openai/gpt-oss-20b" ]
}

@test "get_model_display_name: codex は opus/sonnet 既定値ではなく Codex を表示する" {
    load_adapter_with "${TEST_TMP}/settings_codex_default.yaml"
    result=$(get_model_display_name "shogun")
    [ "$result" = "Codex" ]
}

@test "get_model_display_name: gemini は旧Claude系デフォルトではなく Gemini を表示する" {
    load_adapter_with "${TEST_TMP}/settings_shogun_gemini_default.yaml"
    result=$(get_model_display_name "shogun")
    [ "$result" = "Gemini" ]
}

@test "get_model_display_name: claude で gpt系が混入しても Claude 表示へ丸める" {
    load_adapter_with "${TEST_TMP}/settings_claude_invalid_model.yaml"
    result=$(get_model_display_name "shogun")
    [ "$result" = "Claude+T" ]
}

@test "get_model_display_name: claude で auto は auto+T ではなく Claude+T を表示する" {
    load_adapter_with "${TEST_TMP}/settings_claude_invalid_model.yaml"
    result=$(get_model_display_name "gunshi")
    [ "$result" = "Claude+T" ]
}

@test "build_cli_command_with_startup_prompt: codex は positional prompt を付与する" {
    load_adapter_with "${TEST_TMP}/settings_codex_default.yaml"
    result=$(build_cli_command_with_startup_prompt "shogun" "codex" "ready:shogun")
    assert_codex_shared_auth_bootstrap "$result" "shogun"
    [[ "$result" == *"codex --search --dangerously-bypass-approvals-and-sandbox --no-alt-screen ready:shogun" ]]
}

@test "build_cli_command: codex は auth を共有しつつ agent ごとに CODEX_HOME を分離する" {
    load_adapter_with "${TEST_TMP}/settings_shogun_defaults.yaml"
    shogun_cmd=$(build_cli_command "shogun")
    gunshi_cmd=$(build_cli_command "gunshi")
    [[ "$shogun_cmd" == *"CODEX_HOME=${PROJECT_ROOT}/.shogunate/codex/agents/shogun"* ]]
    [[ "$gunshi_cmd" == *"CODEX_HOME=${PROJECT_ROOT}/.shogunate/codex/agents/gunshi"* ]]
    [[ "$shogun_cmd" == *"${PROJECT_ROOT}/.shogunate/codex/shared/auth.json"* ]]
    [[ "$gunshi_cmd" == *"${PROJECT_ROOT}/.shogunate/codex/shared/auth.json"* ]]
}

@test "build_cli_command_with_startup_prompt: claude は positional prompt を付与する" {
    load_adapter_with "${TEST_TMP}/settings_with_models.yaml"
    result=$(build_cli_command_with_startup_prompt "karo" "claude" "ready:karo")
    [ "$result" = "claude --model sonnet --dangerously-skip-permissions ready:karo" ]
}

@test "build_cli_command_with_startup_prompt: gemini は interactive prompt フラグを付与する" {
    load_adapter_with "${TEST_TMP}/settings_gemini.yaml"
    mkdir -p "${TEST_TMP}/home-empty"
    HOME="${TEST_TMP}/home-empty" PATH="/usr/bin:/bin" result=$(build_cli_command_with_startup_prompt "ashigaru2" "gemini" "ready:ashigaru2")
    [ "$result" = "gemini --yolo -i ready:ashigaru2" ]
}

@test "build_cli_command_with_startup_prompt: opencode は --prompt を付与する" {
    load_adapter_with "${TEST_TMP}/settings_opencode.yaml"
    result=$(build_cli_command_with_startup_prompt "shogun" "opencode" "ready:shogun")
    [ "$result" = "opencode --model ollama/qwen3-coder:30b --prompt ready:shogun" ]
}

@test "build_cli_command_with_startup_prompt: kilo は --prompt を付与する" {
    load_adapter_with "${TEST_TMP}/settings_kilo.yaml"
    result=$(build_cli_command_with_startup_prompt "gunshi" "kilo" "ready:gunshi")
    [ "$result" = "kilo --model lmstudio/codellama-7b.Q4_0.gguf --prompt ready:gunshi" ]
}

@test "build_cli_command: cliセクションなし → claude フォールバック" {
    load_adapter_with "${TEST_TMP}/settings_none.yaml"
    result=$(build_cli_command "ashigaru1")
    [[ "$result" == claude*--dangerously-skip-permissions ]]
}

@test "build_cli_command: settings読取失敗 → claude フォールバック" {
    load_adapter_with "/nonexistent/settings.yaml"
    result=$(build_cli_command "ashigaru1")
    [[ "$result" == claude*--dangerously-skip-permissions ]]
}

# =============================================================================
# get_instruction_file テスト
# =============================================================================

@test "get_instruction_file: shogun + claude → instructions/generated/shogun.md" {
    load_adapter_with "${TEST_TMP}/settings_mixed.yaml"
    result=$(get_instruction_file "shogun")
    [ "$result" = "instructions/generated/shogun.md" ]
}

@test "get_instruction_file: karo + claude → instructions/generated/karo.md" {
    load_adapter_with "${TEST_TMP}/settings_mixed.yaml"
    result=$(get_instruction_file "karo")
    [ "$result" = "instructions/generated/karo.md" ]
}

@test "get_instruction_file: ashigaru1 + claude → instructions/generated/ashigaru.md" {
    load_adapter_with "${TEST_TMP}/settings_mixed.yaml"
    result=$(get_instruction_file "ashigaru1")
    [ "$result" = "instructions/generated/ashigaru.md" ]
}

@test "get_instruction_file: ashigaru5 + codex → instructions/generated/codex-ashigaru.md" {
    load_adapter_with "${TEST_TMP}/settings_mixed.yaml"
    result=$(get_instruction_file "ashigaru5")
    [ "$result" = "instructions/generated/codex-ashigaru.md" ]
}

@test "get_instruction_file: ashigaru7 + copilot → instructions/generated/copilot-ashigaru.md" {
    load_adapter_with "${TEST_TMP}/settings_mixed.yaml"
    result=$(get_instruction_file "ashigaru7")
    [ "$result" = "instructions/generated/copilot-ashigaru.md" ]
}

@test "get_instruction_file: ashigaru3 + kimi → instructions/generated/kimi-ashigaru.md" {
    load_adapter_with "${TEST_TMP}/settings_kimi.yaml"
    result=$(get_instruction_file "ashigaru3")
    [ "$result" = "instructions/generated/kimi-ashigaru.md" ]
}

@test "get_instruction_file: shogun + kimi → instructions/generated/kimi-shogun.md" {
    load_adapter_with "${TEST_TMP}/settings_kimi_default.yaml"
    result=$(get_instruction_file "shogun")
    [ "$result" = "instructions/generated/kimi-shogun.md" ]
}

@test "get_instruction_file: ashigaru2 + gemini → instructions/generated/gemini-ashigaru.md" {
    load_adapter_with "${TEST_TMP}/settings_gemini.yaml"
    result=$(get_instruction_file "ashigaru2")
    [ "$result" = "instructions/generated/gemini-ashigaru.md" ]
}

@test "get_instruction_file: ashigaru6 + localapi → instructions/generated/localapi-ashigaru.md" {
    load_adapter_with "${TEST_TMP}/settings_localapi.yaml"
    result=$(get_instruction_file "ashigaru6")
    [ "$result" = "instructions/generated/localapi-ashigaru.md" ]
}

@test "get_instruction_file: shogun + opencode → instructions/generated/opencode-shogun.md" {
    load_adapter_with "${TEST_TMP}/settings_opencode.yaml"
    result=$(get_instruction_file "shogun")
    [ "$result" = "instructions/generated/opencode-shogun.md" ]
}

@test "get_instruction_file: gunshi + kilo → instructions/generated/kilo-gunshi.md" {
    load_adapter_with "${TEST_TMP}/settings_kilo.yaml"
    result=$(get_instruction_file "gunshi")
    [ "$result" = "instructions/generated/kilo-gunshi.md" ]
}

@test "get_instruction_file: cli_type引数で明示指定 (codex)" {
    load_adapter_with "${TEST_TMP}/settings_none.yaml"
    result=$(get_instruction_file "shogun" "codex")
    [ "$result" = "instructions/generated/codex-shogun.md" ]
}

@test "get_instruction_file: cli_type引数で明示指定 (copilot)" {
    load_adapter_with "${TEST_TMP}/settings_none.yaml"
    result=$(get_instruction_file "karo" "copilot")
    [ "$result" = "instructions/generated/copilot-karo.md" ]
}

@test "get_instruction_file: 全CLI × 全role組み合わせ" {
    load_adapter_with "${TEST_TMP}/settings_none.yaml"
    # claude
    [ "$(get_instruction_file shogun claude)" = "instructions/generated/shogun.md" ]
    [ "$(get_instruction_file karo claude)" = "instructions/generated/karo.md" ]
    [ "$(get_instruction_file ashigaru1 claude)" = "instructions/generated/ashigaru.md" ]
    # codex
    [ "$(get_instruction_file shogun codex)" = "instructions/generated/codex-shogun.md" ]
    [ "$(get_instruction_file karo codex)" = "instructions/generated/codex-karo.md" ]
    [ "$(get_instruction_file ashigaru3 codex)" = "instructions/generated/codex-ashigaru.md" ]
    # copilot
    [ "$(get_instruction_file shogun copilot)" = "instructions/generated/copilot-shogun.md" ]
    [ "$(get_instruction_file karo copilot)" = "instructions/generated/copilot-karo.md" ]
    [ "$(get_instruction_file ashigaru5 copilot)" = "instructions/generated/copilot-ashigaru.md" ]
    # kimi
    [ "$(get_instruction_file shogun kimi)" = "instructions/generated/kimi-shogun.md" ]
    [ "$(get_instruction_file karo kimi)" = "instructions/generated/kimi-karo.md" ]
    [ "$(get_instruction_file ashigaru7 kimi)" = "instructions/generated/kimi-ashigaru.md" ]
    # gemini
    [ "$(get_instruction_file shogun gemini)" = "instructions/generated/gemini-shogun.md" ]
    [ "$(get_instruction_file karo gemini)" = "instructions/generated/gemini-karo.md" ]
    [ "$(get_instruction_file ashigaru2 gemini)" = "instructions/generated/gemini-ashigaru.md" ]
    # localapi
    [ "$(get_instruction_file shogun localapi)" = "instructions/generated/localapi-shogun.md" ]
    [ "$(get_instruction_file karo localapi)" = "instructions/generated/localapi-karo.md" ]
    [ "$(get_instruction_file ashigaru6 localapi)" = "instructions/generated/localapi-ashigaru.md" ]
    # opencode
    [ "$(get_instruction_file shogun opencode)" = "instructions/generated/opencode-shogun.md" ]
    [ "$(get_instruction_file karo opencode)" = "instructions/generated/opencode-karo.md" ]
    [ "$(get_instruction_file ashigaru1 opencode)" = "instructions/generated/opencode-ashigaru.md" ]
    # kilo
    [ "$(get_instruction_file shogun kilo)" = "instructions/generated/kilo-shogun.md" ]
    [ "$(get_instruction_file gunshi kilo)" = "instructions/generated/kilo-gunshi.md" ]
    [ "$(get_instruction_file ashigaru1 kilo)" = "instructions/generated/kilo-ashigaru.md" ]
}

@test "get_instruction_file: 不明なagent_id → 空文字 + return 1" {
    load_adapter_with "${TEST_TMP}/settings_none.yaml"
    run get_instruction_file "unknown_agent"
    [ "$status" -eq 1 ]
}

@test "get_role_instruction_file: role共通mdを返す" {
    load_adapter_with "${TEST_TMP}/settings_none.yaml"
    [ "$(get_role_instruction_file shogun)" = "instructions/shogun.md" ]
    [ "$(get_role_instruction_file karo)" = "instructions/karo.md" ]
    [ "$(get_role_instruction_file ashigaru3)" = "instructions/ashigaru.md" ]
}

# =============================================================================
# validate_cli_availability テスト
# =============================================================================

@test "validate_cli_availability: claude → 0 (インストール済み)" {
    command -v claude >/dev/null 2>&1 || skip "claude not installed (CI environment)"
    load_adapter_with "${TEST_TMP}/settings_none.yaml"
    run validate_cli_availability "claude"
    [ "$status" -eq 0 ]
}

@test "validate_cli_availability: 不正CLI名 → 1 + エラーメッセージ" {
    load_adapter_with "${TEST_TMP}/settings_none.yaml"
    run validate_cli_availability "invalid_type"
    [ "$status" -eq 1 ]
    [[ "$output" == *"Unknown CLI type"* ]]
}

@test "validate_cli_availability: 空文字 → 1" {
    load_adapter_with "${TEST_TMP}/settings_none.yaml"
    run validate_cli_availability ""
    [ "$status" -eq 1 ]
}

@test "validate_cli_availability: codex mock (PATH操作)" {
    load_adapter_with "${TEST_TMP}/settings_none.yaml"
    # モックcodexコマンドを作成
    mkdir -p "${TEST_TMP}/bin"
    echo '#!/bin/bash' > "${TEST_TMP}/bin/codex"
    chmod +x "${TEST_TMP}/bin/codex"
    PATH="${TEST_TMP}/bin:$PATH" run validate_cli_availability "codex"
    [ "$status" -eq 0 ]
}

@test "validate_cli_availability: copilot mock (PATH操作)" {
    load_adapter_with "${TEST_TMP}/settings_none.yaml"
    mkdir -p "${TEST_TMP}/bin"
    echo '#!/bin/bash' > "${TEST_TMP}/bin/copilot"
    chmod +x "${TEST_TMP}/bin/copilot"
    PATH="${TEST_TMP}/bin:$PATH" run validate_cli_availability "copilot"
    [ "$status" -eq 0 ]
}

@test "validate_cli_availability: kimi-cli mock (PATH操作)" {
    load_adapter_with "${TEST_TMP}/settings_none.yaml"
    mkdir -p "${TEST_TMP}/bin"
    echo '#!/bin/bash' > "${TEST_TMP}/bin/kimi-cli"
    chmod +x "${TEST_TMP}/bin/kimi-cli"
    PATH="${TEST_TMP}/bin:$PATH" run validate_cli_availability "kimi"
    [ "$status" -eq 0 ]
}

@test "validate_cli_availability: kimi mock (PATH操作)" {
    load_adapter_with "${TEST_TMP}/settings_none.yaml"
    mkdir -p "${TEST_TMP}/bin"
    echo '#!/bin/bash' > "${TEST_TMP}/bin/kimi"
    chmod +x "${TEST_TMP}/bin/kimi"
    PATH="${TEST_TMP}/bin:$PATH" run validate_cli_availability "kimi"
    [ "$status" -eq 0 ]
}

@test "validate_cli_availability: gemini mock (PATH操作)" {
    load_adapter_with "${TEST_TMP}/settings_none.yaml"
    mkdir -p "${TEST_TMP}/bin"
    echo '#!/bin/bash' > "${TEST_TMP}/bin/gemini"
    chmod +x "${TEST_TMP}/bin/gemini"
    PATH="${TEST_TMP}/bin:$PATH" run validate_cli_availability "gemini"
    [ "$status" -eq 0 ]
}

@test "_cli_adapter_pick_executable: PATH外の ~/.local/bin も検出する" {
    load_adapter_with "${TEST_TMP}/settings_none.yaml"
    mkdir -p "${TEST_TMP}/home/.local/bin"
    echo '#!/bin/bash' > "${TEST_TMP}/home/.local/bin/gemini"
    chmod +x "${TEST_TMP}/home/.local/bin/gemini"
    HOME="${TEST_TMP}/home" PATH="/usr/bin:/bin" run _cli_adapter_pick_executable "gemini" "gemini-cli"
    [ "$status" -eq 0 ]
    [ "$output" = "${TEST_TMP}/home/.local/bin/gemini" ]
}

@test "_cli_adapter_pick_executable: PATH外の ~/.nvm 配下も検出する" {
    load_adapter_with "${TEST_TMP}/settings_none.yaml"
    mkdir -p "${TEST_TMP}/home/.nvm/versions/node/v22.22.0/bin"
    echo '#!/bin/bash' > "${TEST_TMP}/home/.nvm/versions/node/v22.22.0/bin/gemini"
    chmod +x "${TEST_TMP}/home/.nvm/versions/node/v22.22.0/bin/gemini"
    HOME="${TEST_TMP}/home" PATH="/usr/bin:/bin" run _cli_adapter_pick_executable "gemini" "gemini-cli"
    [ "$status" -eq 0 ]
    [ "$output" = "${TEST_TMP}/home/.nvm/versions/node/v22.22.0/bin/gemini" ]
}

@test "validate_cli_availability: localapi python3あり → 0" {
    load_adapter_with "${TEST_TMP}/settings_none.yaml"
    run validate_cli_availability "localapi"
    [ "$status" -eq 0 ]
}

@test "validate_cli_availability: opencode mock (PATH操作)" {
    load_adapter_with "${TEST_TMP}/settings_none.yaml"
    mkdir -p "${TEST_TMP}/bin"
    echo '#!/bin/bash' > "${TEST_TMP}/bin/opencode"
    chmod +x "${TEST_TMP}/bin/opencode"
    PATH="${TEST_TMP}/bin:$PATH" run validate_cli_availability "opencode"
    [ "$status" -eq 0 ]
}

@test "validate_cli_availability: kilo mock (PATH操作)" {
    load_adapter_with "${TEST_TMP}/settings_none.yaml"
    mkdir -p "${TEST_TMP}/bin"
    echo '#!/bin/bash' > "${TEST_TMP}/bin/kilo"
    chmod +x "${TEST_TMP}/bin/kilo"
    PATH="${TEST_TMP}/bin:$PATH" run validate_cli_availability "kilo"
    [ "$status" -eq 0 ]
}

@test "validate_cli_availability: codex未インストール → 1 + エラーメッセージ" {
    load_adapter_with "${TEST_TMP}/settings_none.yaml"
    # PATHからcodexを除外（空PATHは危険なのでminimal PATHを設定）
    mkdir -p "${TEST_TMP}/home-empty"
    HOME="${TEST_TMP}/home-empty" PATH="/usr/bin:/bin" run validate_cli_availability "codex"
    [ "$status" -eq 1 ]
    [[ "$output" == *"Codex CLI not found"* ]]
}

@test "validate_cli_availability: kimi未インストール → 1 + エラーメッセージ" {
    load_adapter_with "${TEST_TMP}/settings_none.yaml"
    mkdir -p "${TEST_TMP}/home-empty"
    HOME="${TEST_TMP}/home-empty" PATH="/usr/bin:/bin" run validate_cli_availability "kimi"
    [ "$status" -eq 1 ]
    [[ "$output" == *"Kimi CLI not found"* ]]
}

@test "validate_cli_availability: gemini未インストール → 1 + エラーメッセージ" {
    load_adapter_with "${TEST_TMP}/settings_none.yaml"
    mkdir -p "${TEST_TMP}/home-empty"
    HOME="${TEST_TMP}/home-empty" PATH="/usr/bin:/bin" run validate_cli_availability "gemini"
    [ "$status" -eq 1 ]
    [[ "$output" == *"Gemini CLI not found"* ]]
}

@test "validate_cli_availability: opencode未インストール → 1 + エラーメッセージ" {
    load_adapter_with "${TEST_TMP}/settings_none.yaml"
    mkdir -p "${TEST_TMP}/home-empty"
    HOME="${TEST_TMP}/home-empty" PATH="/usr/bin:/bin" run validate_cli_availability "opencode"
    [ "$status" -eq 1 ]
    [[ "$output" == *"OpenCode CLI not found"* ]]
}

@test "validate_cli_availability: kilo未インストール → 1 + エラーメッセージ" {
    load_adapter_with "${TEST_TMP}/settings_none.yaml"
    mkdir -p "${TEST_TMP}/home-empty"
    HOME="${TEST_TMP}/home-empty" PATH="/usr/bin:/bin" run validate_cli_availability "kilo"
    [ "$status" -eq 1 ]
    [[ "$output" == *"Kilo CLI not found"* ]]
}

# =============================================================================
# get_agent_model テスト
# =============================================================================

@test "get_agent_model: cliセクションなし shogun → auto (デフォルト)" {
    load_adapter_with "${TEST_TMP}/settings_none.yaml"
    result=$(get_agent_model "shogun")
    [ "$result" = "auto" ]
}

@test "get_agent_model: cliセクションなし karo → auto (デフォルト)" {
    load_adapter_with "${TEST_TMP}/settings_none.yaml"
    result=$(get_agent_model "karo")
    [ "$result" = "auto" ]
}

@test "get_agent_model: cliセクションなし ashigaru1 → auto (デフォルト)" {
    load_adapter_with "${TEST_TMP}/settings_none.yaml"
    result=$(get_agent_model "ashigaru1")
    [ "$result" = "auto" ]
}

@test "get_agent_model: cliセクションなし ashigaru5 → auto (デフォルト)" {
    load_adapter_with "${TEST_TMP}/settings_none.yaml"
    result=$(get_agent_model "ashigaru5")
    [ "$result" = "auto" ]
}

@test "get_agent_model: YAML指定 ashigaru1 → haiku (オーバーライド)" {
    load_adapter_with "${TEST_TMP}/settings_with_models.yaml"
    result=$(get_agent_model "ashigaru1")
    [ "$result" = "haiku" ]
}

@test "get_agent_model: modelsセクションから取得 karo → sonnet" {
    load_adapter_with "${TEST_TMP}/settings_with_models.yaml"
    result=$(get_agent_model "karo")
    [ "$result" = "sonnet" ]
}

@test "get_agent_model: codexエージェントのmodel ashigaru5 → gpt-5" {
    load_adapter_with "${TEST_TMP}/settings_with_models.yaml"
    result=$(get_agent_model "ashigaru5")
    [ "$result" = "gpt-5" ]
}

@test "get_agent_model: 未知agent → auto (デフォルト)" {
    load_adapter_with "${TEST_TMP}/settings_none.yaml"
    result=$(get_agent_model "unknown_agent")
    [ "$result" = "auto" ]
}

@test "get_agent_model: kimi CLI ashigaru3 → k2.5 (YAML指定)" {
    load_adapter_with "${TEST_TMP}/settings_kimi.yaml"
    result=$(get_agent_model "ashigaru3")
    [ "$result" = "k2.5" ]
}

@test "get_agent_model: kimi CLI ashigaru4 → auto (デフォルト)" {
    load_adapter_with "${TEST_TMP}/settings_kimi.yaml"
    result=$(get_agent_model "ashigaru4")
    [ "$result" = "auto" ]
}

@test "get_agent_model: kimi CLI shogun → auto (デフォルト)" {
    load_adapter_with "${TEST_TMP}/settings_kimi_default.yaml"
    result=$(get_agent_model "shogun")
    [ "$result" = "auto" ]
}

@test "get_agent_model: kimi CLI karo → auto (デフォルト)" {
    load_adapter_with "${TEST_TMP}/settings_kimi_default.yaml"
    result=$(get_agent_model "karo")
    [ "$result" = "auto" ]
}

@test "get_agent_model: gemini CLI ashigaru2 → auto (YAML指定)" {
    load_adapter_with "${TEST_TMP}/settings_gemini.yaml"
    result=$(get_agent_model "ashigaru2")
    [ "$result" = "auto" ]
}

@test "get_agent_model: gemini CLI に gpt 系 model が入っていても auto に丸める" {
    cat > "${TEST_TMP}/settings_gemini_invalid_model2.yaml" << 'YAML'
cli:
  default: gemini
  agents:
    shogun:
      type: gemini
      model: gpt-5.4
YAML
    load_adapter_with "${TEST_TMP}/settings_gemini_invalid_model2.yaml"
    result=$(get_agent_model "shogun")
    [ "$result" = "auto" ]
}

@test "get_agent_model: localapi CLI ashigaru6 → qwen2.5-coder (YAML指定)" {
    load_adapter_with "${TEST_TMP}/settings_localapi.yaml"
    result=$(get_agent_model "ashigaru6")
    [ "$result" = "qwen2.5-coder" ]
}
