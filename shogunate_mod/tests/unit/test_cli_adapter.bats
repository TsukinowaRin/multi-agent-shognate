#!/usr/bin/env bats
# test_cli_adapter.bats — cli_adapter.sh ユニットテスト
# Multi-CLI統合設計書 §4.1 準拠

# --- セットアップ ---

setup() {
    unset PERMISSION_FLAG
    unset NVM_BIN
    unset PNPM_HOME

    # テスト用のtmpディレクトリ
    TEST_TMP="$(mktemp -d)"
    export HOME="${TEST_TMP}/home"
    export CLI_ADAPTER_HOST_HOME="${TEST_TMP}/host-home"
    mkdir -p "$HOME" "$CLI_ADAPTER_HOST_HOME"

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

    # antigravity settings
    cat > "${TEST_TMP}/settings_antigravity.yaml" << 'YAML'
cli:
  default: claude
  agents:
    ashigaru2:
      type: antigravity
      model: auto
YAML

    cat > "${TEST_TMP}/settings_antigravity_command_without_permission.yaml" << 'YAML'
cli:
  default: antigravity
  agents:
    ashigaru2:
      type: antigravity
      model: auto
  commands:
    antigravity: "agy"
YAML

    # antigravity model settings
    cat > "${TEST_TMP}/settings_antigravity_model.yaml" << 'YAML'
cli:
  default: antigravity
  agents:
    gunshi:
      type: antigravity
      model: gemini-3-pro-preview
    ashigaru1:
      type: antigravity
      model: gemini-3-flash-preview
    ashigaru2:
      type: antigravity
      model: gemini-2.5-flash
    ashigaru3:
      type: antigravity
      model: auto
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
      type: antigravity
    ashigaru2:
      type: claude
YAML

    cat > "${TEST_TMP}/settings_shogun_antigravity_default.yaml" << 'YAML'
cli:
  default: antigravity
  agents:
    shogun:
      type: antigravity
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
    localapi: "python3 shogunate_mod/localapi/repl.py"
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

    cat > "${TEST_TMP}/settings_opencode_variant.yaml" << 'YAML'
cli:
  default: opencode
  agents:
    ashigaru1:
      type: opencode
      model: sonnet
      variant: high
  commands:
    opencode: "opencode"
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
    [[ "$result" == *"mkdir -p ${PROJECT_ROOT}/.shogunate/codex/agents/${agent_id} && if [ -f ${CLI_ADAPTER_HOST_HOME}/.codex/auth.json ]; then ln -sfn ${CLI_ADAPTER_HOST_HOME}/.codex/auth.json ${PROJECT_ROOT}/.shogunate/codex/agents/${agent_id}/auth.json; else"* ]]
    [[ "$result" == *"mkdir -p ${PROJECT_ROOT}/.shogunate/codex/agents/${agent_id} ${PROJECT_ROOT}/.shogunate/codex/shared"* ]]
    [[ "$result" == *"if [ -f ${PROJECT_ROOT}/.shogunate/codex/agents/${agent_id}/auth.json ] && [ ! -e ${PROJECT_ROOT}/.shogunate/codex/shared/auth.json ]; then cp ${PROJECT_ROOT}/.shogunate/codex/agents/${agent_id}/auth.json ${PROJECT_ROOT}/.shogunate/codex/shared/auth.json; fi"* ]]
    [[ "$result" == *"ln -sfn ${PROJECT_ROOT}/.shogunate/codex/shared/auth.json ${PROJECT_ROOT}/.shogunate/codex/agents/${agent_id}/auth.json"* ]]
    [[ "$result" == *"AGENT_ID=${agent_id} CODEX_HOME=${PROJECT_ROOT}/.shogunate/codex/agents/${agent_id} NO_UPDATE_NOTIFIER=1 "*codex* ]]
    [[ "$result" == *"; fi && AGENT_ID=${agent_id} CODEX_HOME="* ]]
}

assert_codex_shared_auth_custom_bootstrap() {
    local result="$1"
    local agent_id="$2"
    [[ "$result" == *"if [ -f ${CLI_ADAPTER_HOST_HOME}/.codex/auth.json ]; then ln -sfn ${CLI_ADAPTER_HOST_HOME}/.codex/auth.json ${PROJECT_ROOT}/.shogunate/codex/agents/${agent_id}/auth.json; else"* ]]
    [[ "$result" == *"mkdir -p ${PROJECT_ROOT}/.shogunate/codex/agents/${agent_id} ${PROJECT_ROOT}/context/local/codex-auth"* ]]
    [[ "$result" == *"cp ${PROJECT_ROOT}/.shogunate/codex/agents/${agent_id}/auth.json ${PROJECT_ROOT}/context/local/codex-auth/auth.json"* ]]
    [[ "$result" == *"ln -sfn ${PROJECT_ROOT}/context/local/codex-auth/auth.json ${PROJECT_ROOT}/.shogunate/codex/agents/${agent_id}/auth.json"* ]]
}

assert_cli_state_isolated() {
    local result="$1"
    local cli_type="$2"
    local agent_id="$3"
    local state_home="${PROJECT_ROOT}/.shogunate/cli-state/${cli_type}/agents/${agent_id}/home"
    [[ "$result" == *"mkdir -p ${state_home} ${state_home}/.config ${state_home}/.local/share ${state_home}/.cache ${state_home}/.local/state"* ]]
    [[ "$result" == *"HOME=${state_home}"* ]]
    [[ "$result" == *"XDG_CONFIG_HOME=${state_home}/.config"* ]]
    [[ "$result" == *"XDG_DATA_HOME=${state_home}/.local/share"* ]]
    [[ "$result" == *"XDG_CACHE_HOME=${state_home}/.cache"* ]]
    [[ "$result" == *"XDG_STATE_HOME=${state_home}/.local/state"* ]]
}

assert_cli_host_auth_link() {
    local result="$1"
    local rel_path="$2"
    local cli_type="$3"
    local agent_id="$4"
    local state_home="${PROJECT_ROOT}/.shogunate/cli-state/${cli_type}/agents/${agent_id}/home"
    [[ "$result" == *"if [ -f ${CLI_ADAPTER_HOST_HOME}/${rel_path} ]; then ln -sfn ${CLI_ADAPTER_HOST_HOME}/${rel_path} ${state_home}/${rel_path}; fi"* ]]
}

assert_cli_host_dir_link() {
    local result="$1"
    local rel_path="$2"
    local cli_type="$3"
    local agent_id="$4"
    local state_home="${PROJECT_ROOT}/.shogunate/cli-state/${cli_type}/agents/${agent_id}/home"
    [[ "$result" == *"if [ -d ${CLI_ADAPTER_HOST_HOME}/${rel_path} ]; then ln -sfn ${CLI_ADAPTER_HOST_HOME}/${rel_path} ${state_home}/${rel_path}; fi"* ]]
}

assert_cli_state_symlink_removed() {
    local result="$1"
    local rel_path="$2"
    local cli_type="$3"
    local agent_id="$4"
    local state_home="${PROJECT_ROOT}/.shogunate/cli-state/${cli_type}/agents/${agent_id}/home"
    [[ "$result" == *"if [ -L ${state_home}/${rel_path} ]; then rm -f ${state_home}/${rel_path}; fi"* ]]
}

assert_cli_host_state_seed() {
    local result="$1"
    local rel_path="$2"
    local cli_type="$3"
    local agent_id="$4"
    local state_home="${PROJECT_ROOT}/.shogunate/cli-state/${cli_type}/agents/${agent_id}/home"
    [[ "$result" == *"if [ -L ${state_home}/${rel_path} ]; then rm -f ${state_home}/${rel_path}; fi"* ]]
    [[ "$result" == *"if [ -f ${CLI_ADAPTER_HOST_HOME}/${rel_path} ] && [ ! -e ${state_home}/${rel_path} ]; then cp ${CLI_ADAPTER_HOST_HOME}/${rel_path} ${state_home}/${rel_path}; fi"* ]]
}

assert_cli_host_state_seed_json_default() {
    local result="$1"
    local rel_path="$2"
    local cli_type="$3"
    local agent_id="$4"
    local state_home="${PROJECT_ROOT}/.shogunate/cli-state/${cli_type}/agents/${agent_id}/home"
    [[ "$result" == *"${CLI_ADAPTER_HOST_HOME}/${rel_path}"* ]]
    [[ "$result" == *"${state_home}/${rel_path}"* ]]
    [[ "$result" == *"not data.get(\"recent\") and not data.get(\"favorite\")"* ]]
}

assert_antigravity_settings_seed() {
    local result="$1"
    local agent_id="$2"
    local state_home="${PROJECT_ROOT}/.shogunate/cli-state/antigravity/agents/${agent_id}/home"
    [[ "$result" == *"${CLI_ADAPTER_HOST_HOME}/.gemini/antigravity-cli/settings.json"* ]]
    [[ "$result" == *"${state_home}/.gemini/antigravity-cli/settings.json"* ]]
    [[ "$result" == *"data[\"toolPermission\"] = \"always-proceed\""* ]]
    [[ "$result" == *"data[\"allowNonWorkspaceAccess\"] = True"* ]]
    [[ "$result" == *"trustedWorkspaces"* ]]
}

assert_antigravity_auth_links() {
    local result="$1"
    local agent_id="$2"
    [[ "$result" == *"${PROJECT_ROOT}/shogunate_mod/cli/antigravity_keyring.sh && mkdir -p"* ]]
    assert_cli_host_auth_link "$result" ".gemini/antigravity-cli/auth.json" "antigravity" "$agent_id"
    assert_cli_host_auth_link "$result" ".gemini/antigravity-cli/antigravity-oauth-token" "antigravity" "$agent_id"
    assert_cli_host_auth_link "$result" ".gemini/antigravity-cli/oauth_creds.json" "antigravity" "$agent_id"
    assert_cli_host_auth_link "$result" ".gemini/antigravity-cli/google_accounts.json" "antigravity" "$agent_id"
    [[ "$result" != *"ln -sfn ${CLI_ADAPTER_HOST_HOME}/.gemini/antigravity-cli/settings.json"* ]]
    assert_cli_host_auth_link "$result" ".gemini/oauth_creds.json" "antigravity" "$agent_id"
    assert_cli_host_auth_link "$result" ".gemini/google_accounts.json" "antigravity" "$agent_id"
    assert_cli_host_state_seed "$result" ".gemini/antigravity-cli/cache/onboarding.json" "antigravity" "$agent_id"
    assert_antigravity_settings_seed "$result" "$agent_id"
}

assert_antigravity_launch_base() {
    local result="$1"
    local agent_id="$2"
    [[ "$result" == *"AGENT_ID=${agent_id} "*agy* ]]
    [[ "$result" == *"--dangerously-skip-permissions"* ]]
    [[ "$result" == *"--add-dir ${PROJECT_ROOT}"* ]]
}

make_fake_cli() {
    local name="$1"
    mkdir -p "${TEST_TMP}/bin"
    printf '#!/usr/bin/env bash\nexit 0\n' > "${TEST_TMP}/bin/${name}"
    chmod +x "${TEST_TMP}/bin/${name}"
}

@test "_cli_adapter_find_executable: PATHよりHOME配下のnative CLIを優先する" {
    load_adapter_with "${TEST_TMP}/settings_none.yaml"
    mkdir -p "${TEST_TMP}/path-bin" "${TEST_TMP}/home/.nvm/versions/node/v22.22.0/bin"
    printf '#!/usr/bin/env bash\nexit 0\n' > "${TEST_TMP}/path-bin/codex"
    printf '#!/usr/bin/env bash\nexit 0\n' > "${TEST_TMP}/home/.nvm/versions/node/v22.22.0/bin/codex"
    chmod +x "${TEST_TMP}/path-bin/codex" "${TEST_TMP}/home/.nvm/versions/node/v22.22.0/bin/codex"

    result=$(HOME="${TEST_TMP}/home" PATH="${TEST_TMP}/path-bin:/usr/bin:/bin" _cli_adapter_find_executable "codex")

    [ "$result" = "${TEST_TMP}/home/.nvm/versions/node/v22.22.0/bin/codex" ]
}

@test "_cli_adapter_find_executable: OpenCode公式home binをnvm候補より優先する" {
    load_adapter_with "${TEST_TMP}/settings_none.yaml"
    mkdir -p "${TEST_TMP}/home/.opencode/bin" "${TEST_TMP}/home/.nvm/versions/node/v22.22.0/bin"
    printf '#!/usr/bin/env bash\nexit 0\n' > "${TEST_TMP}/home/.opencode/bin/opencode"
    printf '#!/usr/bin/env bash\nexit 0\n' > "${TEST_TMP}/home/.nvm/versions/node/v22.22.0/bin/opencode"
    chmod +x "${TEST_TMP}/home/.opencode/bin/opencode" "${TEST_TMP}/home/.nvm/versions/node/v22.22.0/bin/opencode"

    result=$(HOME="${TEST_TMP}/home" PATH="/usr/bin:/bin" _cli_adapter_find_executable "opencode")

    [ "$result" = "${TEST_TMP}/home/.opencode/bin/opencode" ]
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

@test "get_cli_type: antigravity設定 ashigaru2 → antigravity" {
    load_adapter_with "${TEST_TMP}/settings_antigravity.yaml"
    result=$(get_cli_type "ashigaru2")
    [ "$result" = "antigravity" ]
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

@test "get_cli_type: karo2 は karo 設定を継承する" {
    cat > "${TEST_TMP}/settings_karo_family.yaml" <<'YAML'
cli:
  default: codex
  agents:
    karo:
      type: antigravity
YAML
    load_adapter_with "${TEST_TMP}/settings_karo_family.yaml"
    result=$(get_cli_type "karo2")
    [ "$result" = "antigravity" ]
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

@test "build_cli_command: claude + model → claude --model opus --setting-sources local --permission-mode auto" {
    load_adapter_with "${TEST_TMP}/settings_mixed.yaml"
    result=$(build_cli_command "shogun")
    assert_cli_state_isolated "$result" "claude" "shogun"
    assert_cli_host_dir_link "$result" ".claude" "claude" "shogun"
    assert_cli_host_auth_link "$result" ".claude.json" "claude" "shogun"
    assert_cli_host_dir_link "$result" ".config/claude" "claude" "shogun"
    [[ "$result" == *"MAX_THINKING_TOKENS=0 AGENT_ID=shogun "*claude" --model opus --setting-sources local --permission-mode auto" ]]
}

@test "build_cli_command: claude は host PATH の実行ファイルを絶対パスで使う" {
    load_adapter_with "${TEST_TMP}/settings_mixed.yaml"
    make_fake_cli claude
    result=$(PATH="${TEST_TMP}/bin:/usr/bin:/bin" build_cli_command "shogun")
    assert_cli_state_isolated "$result" "claude" "shogun"
    [[ "$result" == *"MAX_THINKING_TOKENS=0 AGENT_ID=shogun ${TEST_TMP}/bin/claude --model opus --setting-sources local --permission-mode auto" ]]
}

@test "build_cli_command: claude は PERMISSION_FLAG を反映する" {
    load_adapter_with "${TEST_TMP}/settings_mixed.yaml"
    PERMISSION_FLAG="--setting-sources local --permission-mode plan"
    result=$(build_cli_command "shogun")
    assert_cli_state_isolated "$result" "claude" "shogun"
    [[ "$result" == *"MAX_THINKING_TOKENS=0 AGENT_ID=shogun "*claude" --model opus --setting-sources local --permission-mode plan" ]]
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
    assert_cli_state_isolated "$result" "claude" "shogun"
    [[ "$result" == *"MAX_THINKING_TOKENS=0 AGENT_ID=shogun "*claude" --setting-sources local --permission-mode auto" ]]
}

@test "build_cli_command: codex → NO_UPDATE_NOTIFIER=1 付きで起動" {
    load_adapter_with "${TEST_TMP}/settings_mixed.yaml"
    result=$(build_cli_command "ashigaru5")
    assert_codex_shared_auth_bootstrap "$result" "ashigaru5"
    [[ "$result" == *"--search --sandbox danger-full-access --ask-for-approval never" ]]
}

@test "build_cli_command: codex は host PATH の実行ファイルを絶対パスで使う" {
    load_adapter_with "${TEST_TMP}/settings_codex_default.yaml"
    make_fake_cli codex
    result=$(PATH="${TEST_TMP}/bin:/usr/bin:/bin" build_cli_command "shogun")
    assert_codex_shared_auth_bootstrap "$result" "shogun"
    [[ "$result" == *"NO_UPDATE_NOTIFIER=1 ${TEST_TMP}/bin/codex --search --sandbox danger-full-access --ask-for-approval never" ]]
}

@test "build_cli_command: codex + explicit model → codex --model ... --search --sandbox danger-full-access --ask-for-approval never" {
    load_adapter_with "${TEST_TMP}/settings_codex_model.yaml"
    result=$(build_cli_command "shogun")
    assert_codex_shared_auth_bootstrap "$result" "shogun"
    [[ "$result" == *codex" --model gpt-5.3-codex --search --sandbox danger-full-access --ask-for-approval never" ]]
}

@test "build_cli_command: codex + reasoning_effort → -c model_reasoning_effort を付与" {
    load_adapter_with "${TEST_TMP}/settings_codex_reasoning.yaml"
    result=$(build_cli_command "shogun")
    assert_codex_shared_auth_bootstrap "$result" "shogun"
    [[ "$result" == *codex" -c model_reasoning_effort='high' --search --sandbox danger-full-access --ask-for-approval never" ]]
}

@test "build_cli_command: codex + explicit model + reasoning_effort none を付与" {
    load_adapter_with "${TEST_TMP}/settings_codex_reasoning.yaml"
    result=$(build_cli_command "gunshi")
    assert_codex_shared_auth_bootstrap "$result" "gunshi"
    [[ "$result" == *codex" --model gpt-5.4 -c model_reasoning_effort='none' --search --sandbox danger-full-access --ask-for-approval never" ]]
}

@test "build_cli_command: shogun codex は未設定なら reasoning_effort を付けない" {
    load_adapter_with "${TEST_TMP}/settings_shogun_defaults.yaml"
    result=$(build_cli_command "shogun")
    assert_codex_shared_auth_bootstrap "$result" "shogun"
    [[ "$result" == *codex" --search --sandbox danger-full-access --ask-for-approval never" ]]
}

@test "build_cli_command: gunshi codex は未設定なら reasoning_effort を付けない" {
    load_adapter_with "${TEST_TMP}/settings_shogun_defaults.yaml"
    result=$(build_cli_command "gunshi")
    assert_codex_shared_auth_bootstrap "$result" "gunshi"
    [[ "$result" == *codex" --search --sandbox danger-full-access --ask-for-approval never" ]]
}

@test "build_cli_command: codex + model auto → --model を付けない" {
    load_adapter_with "${TEST_TMP}/settings_codex_auto.yaml"
    result=$(build_cli_command "shogun")
    assert_codex_shared_auth_bootstrap "$result" "shogun"
    [[ "$result" == *codex" --search --sandbox danger-full-access --ask-for-approval never" ]]
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
    [[ "$result" == *codex" --search --sandbox danger-full-access --ask-for-approval never" ]]
}

@test "build_cli_command: codex shared_auth false でも host auth を優先する" {
    load_adapter_with "${TEST_TMP}/settings_codex_shared_auth_off.yaml"
    result=$(build_cli_command "shogun")
    [[ "$result" == "mkdir -p ${PROJECT_ROOT}/.shogunate/codex/agents/shogun && if [ -f ${CLI_ADAPTER_HOST_HOME}/.codex/auth.json ]; then ln -sfn ${CLI_ADAPTER_HOST_HOME}/.codex/auth.json ${PROJECT_ROOT}/.shogunate/codex/agents/shogun/auth.json; else mkdir -p ${PROJECT_ROOT}/.shogunate/codex/agents/shogun; fi && AGENT_ID=shogun CODEX_HOME=${PROJECT_ROOT}/.shogunate/codex/agents/shogun NO_UPDATE_NOTIFIER=1 "*codex" --search --sandbox danger-full-access --ask-for-approval never" ]]
}

@test "build_cli_command: codex shared_auth_file を custom path へ変更できる" {
    load_adapter_with "${TEST_TMP}/settings_codex_shared_auth_custom.yaml"
    result=$(build_cli_command "shogun")
    assert_codex_shared_auth_custom_bootstrap "$result" "shogun"
    [[ "$result" == *"AGENT_ID=shogun CODEX_HOME=${PROJECT_ROOT}/.shogunate/codex/agents/shogun NO_UPDATE_NOTIFIER=1 "*codex" --search --sandbox danger-full-access --ask-for-approval never" ]]
}

@test "build_cli_command: copilot → copilot --yolo" {
    load_adapter_with "${TEST_TMP}/settings_mixed.yaml"
    result=$(build_cli_command "ashigaru7")
    assert_cli_state_isolated "$result" "copilot" "ashigaru7"
    assert_cli_host_auth_link "$result" ".copilot/auth.json" "copilot" "ashigaru7"
    assert_cli_host_auth_link "$result" ".config/copilot/auth.json" "copilot" "ashigaru7"
    [[ "$result" == *"AGENT_ID=ashigaru7 "*copilot" --yolo" ]]
}

@test "build_cli_command: copilot は host PATH の実行ファイルを絶対パスで使う" {
    load_adapter_with "${TEST_TMP}/settings_mixed.yaml"
    make_fake_cli copilot
    result=$(PATH="${TEST_TMP}/bin:/usr/bin:/bin" build_cli_command "ashigaru7")
    assert_cli_state_isolated "$result" "copilot" "ashigaru7"
    [[ "$result" == *"AGENT_ID=ashigaru7 ${TEST_TMP}/bin/copilot --yolo" ]]
}

@test "build_cli_command: kimi + model → kimi --yolo --model k2.5" {
    load_adapter_with "${TEST_TMP}/settings_kimi.yaml"
    result=$(build_cli_command "ashigaru3")
    assert_cli_state_isolated "$result" "kimi" "ashigaru3"
    assert_cli_host_auth_link "$result" ".kimi/auth.json" "kimi" "ashigaru3"
    assert_cli_host_auth_link "$result" ".config/kimi/auth.json" "kimi" "ashigaru3"
    [[ "$result" == *"AGENT_ID=ashigaru3 "*kimi" --yolo --model k2.5" ]]
}

@test "build_cli_command: kimi-cliのみ存在時は kimi-cli を使用" {
    load_adapter_with "${TEST_TMP}/settings_kimi.yaml"
    mkdir -p "${TEST_TMP}/bin"
    cat > "${TEST_TMP}/bin/kimi-cli" << 'SH'
#!/usr/bin/env bash
exit 0
SH
    chmod +x "${TEST_TMP}/bin/kimi-cli"
    result=$(PATH="${TEST_TMP}/bin:/usr/bin:/bin" build_cli_command "ashigaru3")
    assert_cli_state_isolated "$result" "kimi" "ashigaru3"
    [[ "$result" == *"AGENT_ID=ashigaru3 ${TEST_TMP}/bin/kimi-cli --yolo --model k2.5" ]]
}

@test "build_cli_command: kimi (モデル指定なし) → kimi --yolo" {
    load_adapter_with "${TEST_TMP}/settings_kimi.yaml"
    result=$(build_cli_command "ashigaru4")
    assert_cli_state_isolated "$result" "kimi" "ashigaru4"
    [[ "$result" == *"AGENT_ID=ashigaru4 "*kimi" --yolo" ]]
}

@test "build_cli_command: antigravity + model auto → agy --dangerously-skip-permissions" {
    load_adapter_with "${TEST_TMP}/settings_antigravity.yaml"
    mkdir -p "${TEST_TMP}/home-empty"
    result=$(HOME="${TEST_TMP}/home-empty" PATH="/usr/bin:/bin" build_cli_command "ashigaru2")
    assert_cli_state_isolated "$result" "antigravity" "ashigaru2"
    assert_antigravity_auth_links "$result" "ashigaru2"
    assert_antigravity_launch_base "$result" "ashigaru2"
}

@test "build_cli_command: antigravity はhost settingsを初期値にしつつrole-localに保持する" {
    load_adapter_with "${TEST_TMP}/settings_antigravity.yaml"
    mkdir -p "${TEST_TMP}/home-empty" "${CLI_ADAPTER_HOST_HOME}/.gemini/antigravity-cli"
    printf '{"model":"host-model"}\n' > "${CLI_ADAPTER_HOST_HOME}/.gemini/antigravity-cli/settings.json"
    result=$(HOME="${TEST_TMP}/home-empty" PATH="/usr/bin:/bin" build_cli_command "ashigaru2")
    assert_antigravity_auth_links "$result" "ashigaru2"
    [[ "$result" != *"ln -sfn ${CLI_ADAPTER_HOST_HOME}/.gemini/antigravity-cli/settings.json"* ]]
    [[ "$result" == *"${CLI_ADAPTER_HOST_HOME}/.gemini/antigravity-cli/settings.json"* ]]
}

@test "build_cli_command: antigravity custom command に permission flag が無ければ補完する" {
    load_adapter_with "${TEST_TMP}/settings_antigravity_command_without_permission.yaml"
    mkdir -p "${TEST_TMP}/home-empty"
    result=$(HOME="${TEST_TMP}/home-empty" PATH="/usr/bin:/bin" build_cli_command "ashigaru2")
    assert_cli_state_isolated "$result" "antigravity" "ashigaru2"
    assert_antigravity_launch_base "$result" "ashigaru2"
}

@test "build_cli_command: antigravity は旧 gemini command を流用しない" {
    cat > "${TEST_TMP}/settings_antigravity_legacy_gemini_command.yaml" << 'YAML'
cli:
  default: antigravity
  agents:
    shogun:
      type: antigravity
      model: auto
  commands:
    gemini: "gemini --yolo"
YAML
    load_adapter_with "${TEST_TMP}/settings_antigravity_legacy_gemini_command.yaml"
    mkdir -p "${TEST_TMP}/home-empty"
    result=$(HOME="${TEST_TMP}/home-empty" PATH="/usr/bin:/bin" build_cli_command "shogun")
    assert_cli_state_isolated "$result" "antigravity" "shogun"
    assert_antigravity_launch_base "$result" "shogun"
    [[ "$result" != *"gemini --yolo"* ]]
}

@test "build_cli_command: antigravity explicit model → --model を付与" {
    load_adapter_with "${TEST_TMP}/settings_antigravity_model.yaml"
    mkdir -p "${TEST_TMP}/home-empty"
    result=$(HOME="${TEST_TMP}/home-empty" PATH="/usr/bin:/bin" build_cli_command "gunshi")
    assert_cli_state_isolated "$result" "antigravity" "gunshi"
    assert_antigravity_launch_base "$result" "gunshi"
    [[ "$result" == *"--model gemini-3-pro-preview"* ]]
}

@test "build_cli_command: shogun antigravity は未設定なら model を付けない" {
    load_adapter_with "${TEST_TMP}/settings_shogun_antigravity_default.yaml"
    mkdir -p "${TEST_TMP}/home-empty"
    result=$(HOME="${TEST_TMP}/home-empty" PATH="/usr/bin:/bin" build_cli_command "shogun")
    assert_cli_state_isolated "$result" "antigravity" "shogun"
    assert_antigravity_launch_base "$result" "shogun"
}

@test "build_cli_command: antigravity に gpt 系 model が入っていても auto に丸める" {
    cat > "${TEST_TMP}/settings_antigravity_invalid_model.yaml" << 'YAML'
cli:
  default: antigravity
  agents:
    shogun:
      type: antigravity
      model: gpt-5.4
YAML
    load_adapter_with "${TEST_TMP}/settings_antigravity_invalid_model.yaml"
    mkdir -p "${TEST_TMP}/home-empty"
    result=$(HOME="${TEST_TMP}/home-empty" PATH="/usr/bin:/bin" build_cli_command "shogun")
    assert_cli_state_isolated "$result" "antigravity" "shogun"
    assert_antigravity_launch_base "$result" "shogun"
}

@test "build_cli_command: shogun claude は未設定でも thinking無効を既定適用" {
    load_adapter_with "${TEST_TMP}/settings_shogun_claude_default.yaml"
    result=$(build_cli_command "shogun")
    assert_cli_state_isolated "$result" "claude" "shogun"
    [[ "$result" == *"MAX_THINKING_TOKENS=0 AGENT_ID=shogun "*claude" --model opus --setting-sources local --permission-mode auto" ]]
}

@test "build_cli_command: antigravity executable の agy を使用" {
    load_adapter_with "${TEST_TMP}/settings_antigravity.yaml"
    mkdir -p "${TEST_TMP}/bin"
    cat > "${TEST_TMP}/bin/agy" << 'SH'
#!/usr/bin/env bash
exit 0
SH
    chmod +x "${TEST_TMP}/bin/agy"
    mkdir -p "${TEST_TMP}/home-empty"
    result=$(HOME="${TEST_TMP}/home-empty" PATH="${TEST_TMP}/bin:/usr/bin:/bin" build_cli_command "ashigaru2")
    assert_cli_state_isolated "$result" "antigravity" "ashigaru2"
    [[ "$result" == *"AGENT_ID=ashigaru2 ${TEST_TMP}/bin/agy"* ]]
    [[ "$result" == *"--dangerously-skip-permissions"* ]]
    [[ "$result" == *"--add-dir ${PROJECT_ROOT}"* ]]
}

@test "build_cli_command: localapi → python3 shogunate_mod/localapi/repl.py" {
    load_adapter_with "${TEST_TMP}/settings_localapi.yaml"
    result=$(build_cli_command "ashigaru6")
    # model が指定されている場合は LOCALAI_MODEL= が前置される
    [[ "$result" == *"python3 shogunate_mod/localapi/repl.py"* ]]
    [[ "$result" == *"LOCALAI_MODEL=qwen2.5-coder"* ]]
}

@test "build_cli_command: opencode + provider/model → opencode --model ..." {
    load_adapter_with "${TEST_TMP}/settings_opencode.yaml"
    result=$(build_cli_command "shogun")
    assert_cli_state_isolated "$result" "opencode" "shogun"
    assert_cli_host_auth_link "$result" ".local/share/opencode/auth.json" "opencode" "shogun"
    assert_cli_state_symlink_removed "$result" ".local/share/opencode/opencode.db" "opencode" "shogun"
    assert_cli_state_symlink_removed "$result" ".local/share/opencode/opencode.db-shm" "opencode" "shogun"
    assert_cli_state_symlink_removed "$result" ".local/share/opencode/opencode.db-wal" "opencode" "shogun"
    assert_cli_host_state_seed_json_default "$result" ".local/state/opencode/model.json" "opencode" "shogun"
    assert_cli_state_symlink_removed "$result" ".local/state/opencode/prompt-history.jsonl" "opencode" "shogun"
    assert_cli_host_state_seed "$result" ".config/opencode/package.json" "opencode" "shogun"
    assert_cli_host_dir_link "$result" ".config/opencode/node_modules" "opencode" "shogun"
    [[ "$result" != *"ln -sfn ${CLI_ADAPTER_HOST_HOME}/.local/share/opencode/opencode.db"* ]]
    [[ "$result" == *"AGENT_ID=shogun OPENCODE_AGENT_ID=shogun OPENCODE_TUI_CONFIG="*"/shogunate_mod/configure/opencode-tui.json "*opencode" --model ollama/qwen3-coder:30b --agent shogun" ]]
}

@test "build_cli_command: opencode bare command は host PATH の実行ファイルへ解決する" {
    load_adapter_with "${TEST_TMP}/settings_opencode.yaml"
    make_fake_cli opencode
    result=$(PATH="${TEST_TMP}/bin:/usr/bin:/bin" build_cli_command "shogun")
    assert_cli_state_isolated "$result" "opencode" "shogun"
    [[ "$result" == *"AGENT_ID=shogun OPENCODE_AGENT_ID=shogun OPENCODE_TUI_CONFIG="*"/shogunate_mod/configure/opencode-tui.json ${TEST_TMP}/bin/opencode --model ollama/qwen3-coder:30b --agent shogun" ]]
}

@test "build_cli_command: opencode variant は runtime agent と provider正規化を使う" {
    load_adapter_with "${TEST_TMP}/settings_opencode_variant.yaml"
    make_fake_cli opencode
    result=$(PATH="${TEST_TMP}/bin:/usr/bin:/bin" build_cli_command "ashigaru1")
    assert_cli_state_isolated "$result" "opencode" "ashigaru1"
    [[ "$result" == *"${TEST_TMP}/bin/opencode --model anthropic/claude-sonnet-4-6 --agent ashigaru1-runtime" ]]
    [[ "$result" == *"OPENCODE_AGENT_ID=ashigaru1"* ]]
}

@test "role failover: Fallbackのtype/model/reasoning/thinking/variantを同じgenerationから使う" {
    cat > "${TEST_TMP}/settings_failover.yaml" <<'YAML'
cli:
  default: codex
  agents:
    ashigaru1:
      type: codex
      model: primary-model
      reasoning_effort: high
      fallback:
        type: opencode
        model: sonnet
        reasoning_effort: medium
        thinking: false
        variant: high
  commands:
    opencode: opencode
YAML
    python3 "${PROJECT_ROOT}/shogunate_mod/runtime/role_failover.py" --root "$TEST_TMP" init-role \
      --role ashigaru1 --settings "${TEST_TMP}/settings_failover.yaml" --event-id init --reset >/dev/null
    python3 "${PROJECT_ROOT}/shogunate_mod/runtime/role_failover.py" --root "$TEST_TMP" apply-event \
      --event-json '{"event_id":"fail","type":"explicit_failure","role":"ashigaru1","expected_generation":1,"reason":"rate_limit"}' >/dev/null

    export CLI_ADAPTER_FAILOVER_ROOT="$TEST_TMP"
    load_adapter_with "${TEST_TMP}/settings_failover.yaml"
    load_active_role_profile ashigaru1
    [ "$CLI_ACTIVE_PROFILE_SLOT" = "fallback" ]
    [ "$CLI_ACTIVE_PROFILE_GENERATION" = "2" ]
    [ "$(get_cli_type ashigaru1)" = "opencode" ]
    [ "$(get_agent_model ashigaru1)" = "sonnet" ]
    [ "$(get_agent_reasoning_effort ashigaru1)" = "medium" ]
    [ "$CLI_ACTIVE_PROFILE_THINKING" = "false" ]
    [ "$CLI_ACTIVE_PROFILE_VARIANT" = "high" ]
}

@test "role failover: 指定CLIが無ければ別CLIへ置換せず失敗する" {
    cat > "${TEST_TMP}/settings_failover_unavailable.yaml" <<'YAML'
cli:
  default: cursor
  agents:
    karo:
      type: cursor
      fallback: null
YAML
    python3 "${PROJECT_ROOT}/shogunate_mod/runtime/role_failover.py" --root "$TEST_TMP" init-role \
      --role karo --settings "${TEST_TMP}/settings_failover_unavailable.yaml" --event-id init --reset >/dev/null
    export CLI_ADAPTER_FAILOVER_ROOT="$TEST_TMP"
    load_adapter_with "${TEST_TMP}/settings_failover_unavailable.yaml"
    make_fake_cli opencode
    run env HOME="${TEST_TMP}/no-home" PATH="${TEST_TMP}/bin:/usr/bin:/bin" bash -lc \
      "export CLI_ADAPTER_PROJECT_ROOT='$PROJECT_ROOT' CLI_ADAPTER_FAILOVER_ROOT='$TEST_TMP' CLI_ADAPTER_SETTINGS='${TEST_TMP}/settings_failover_unavailable.yaml'; source '$PROJECT_ROOT/shogunate_mod/cli/adapter.sh'; load_active_role_profile karo; resolve_cli_type_for_agent karo"
    [ "$status" -ne 0 ]
    [[ "$output" != *"opencode"* ]]
}

@test "role failover: 同じshellでも切替後に明示reloadすればPrimary snapshotを残さない" {
    cat > "${TEST_TMP}/settings_failover_reload.yaml" <<'YAML'
cli:
  agents:
    karo:
      type: codex
      model: primary
      fallback:
        type: opencode
        model: fallback
YAML
    python3 "${PROJECT_ROOT}/shogunate_mod/runtime/role_failover.py" --root "$TEST_TMP" init-role \
      --role karo --settings "${TEST_TMP}/settings_failover_reload.yaml" --event-id init --reset >/dev/null
    export CLI_ADAPTER_FAILOVER_ROOT="$TEST_TMP"
    load_adapter_with "${TEST_TMP}/settings_failover_reload.yaml"
    load_active_role_profile karo
    [ "$CLI_ACTIVE_PROFILE_MODEL" = "primary" ]
    python3 "${PROJECT_ROOT}/shogunate_mod/runtime/role_failover.py" --root "$TEST_TMP" apply-event \
      --event-json '{"event_id":"switch","type":"explicit_failure","role":"karo","expected_generation":1,"reason":"rate_limit"}' >/dev/null
    load_active_role_profile karo
    [ "$CLI_ACTIVE_PROFILE_SLOT" = "fallback" ]
    [ "$CLI_ACTIVE_PROFILE_GENERATION" = "2" ]
    [ "$CLI_ACTIVE_PROFILE_MODEL" = "fallback" ]
}

@test "build_cli_command: kilo + provider/model → kilo --model ..." {
    load_adapter_with "${TEST_TMP}/settings_kilo.yaml"
    result=$(build_cli_command "gunshi")
    assert_cli_state_isolated "$result" "kilo" "gunshi"
    assert_cli_host_auth_link "$result" ".local/share/kilo/auth.json" "kilo" "gunshi"
    assert_cli_state_symlink_removed "$result" ".local/share/kilo/kilo.db" "kilo" "gunshi"
    assert_cli_state_symlink_removed "$result" ".local/share/kilo/kilo.db-shm" "kilo" "gunshi"
    assert_cli_state_symlink_removed "$result" ".local/share/kilo/kilo.db-wal" "kilo" "gunshi"
    assert_cli_host_state_seed "$result" ".local/state/kilo/model.json" "kilo" "gunshi"
    assert_cli_state_symlink_removed "$result" ".local/state/kilo/prompt-history.jsonl" "kilo" "gunshi"
    assert_cli_host_state_seed "$result" ".config/kilo/package.json" "kilo" "gunshi"
    assert_cli_host_dir_link "$result" ".config/kilo/node_modules" "kilo" "gunshi"
    [[ "$result" != *"ln -sfn ${CLI_ADAPTER_HOST_HOME}/.local/share/kilo/kilo.db"* ]]
    [[ "$result" == *"AGENT_ID=gunshi "*kilo" --model lmstudio/codellama-7b.Q4_0.gguf" ]]
}

@test "build_cli_command: kilo bare command は host PATH の実行ファイルへ解決する" {
    load_adapter_with "${TEST_TMP}/settings_kilo.yaml"
    make_fake_cli kilo
    result=$(PATH="${TEST_TMP}/bin:/usr/bin:/bin" build_cli_command "gunshi")
    assert_cli_state_isolated "$result" "kilo" "gunshi"
    [[ "$result" == *"AGENT_ID=gunshi ${TEST_TMP}/bin/kilo --model lmstudio/codellama-7b.Q4_0.gguf" ]]
}

@test "build_cli_command: opencode global bin設定でも --agent とTUI configを付与する" {
    load_adapter_with "${TEST_TMP}/settings_opencode_global_bin.yaml"
    mkdir -p "${TEST_TMP}/home/.nvm/versions/node/v22.22.0/bin"
    cat > "${TEST_TMP}/home/.nvm/versions/node/v22.22.0/bin/node" << 'SH'
#!/usr/bin/env bash
exit 0
SH
    chmod +x "${TEST_TMP}/home/.nvm/versions/node/v22.22.0/bin/node"
    python3 - "${TEST_TMP}/settings_opencode_global_bin.yaml" "${TEST_TMP}/home" <<'PY'
from pathlib import Path
import sys

path = Path(sys.argv[1])
path.write_text(path.read_text().replace("/tmp/test-home", sys.argv[2]))
PY
    result=$(build_cli_command "ashigaru1")
    assert_cli_state_isolated "$result" "opencode" "ashigaru1"
    [[ "$result" == *"AGENT_ID=ashigaru1 OPENCODE_AGENT_ID=ashigaru1 OPENCODE_TUI_CONFIG="*"/shogunate_mod/configure/opencode-tui.json"* ]]
    [[ "$result" == *"--model lmstudio/openai/gpt-oss-20b --agent ashigaru1"* ]]
}

@test "build_cli_command_with_type: 任意の役職に任意CLIを割り当てても役職別stateになる" {
    load_adapter_with "${TEST_TMP}/settings_none.yaml"
    for cli in claude codex copilot kimi agy opencode kilo; do
        make_fake_cli "$cli"
    done

    local roles=(shogun gunkan gunshi karo karo2 ashigaru1 ashigaru9)
    local clis=(claude codex copilot kimi antigravity opencode kilo localapi)
    local role
    local cli
    local result

    for role in "${roles[@]}"; do
        for cli in "${clis[@]}"; do
            result=$(PATH="${TEST_TMP}/bin:/usr/bin:/bin" build_cli_command_with_type "$role" "$cli")
            [[ "$result" == *"AGENT_ID=${role}"* ]]
            case "$cli" in
                codex)
                    [[ "$result" == *"CODEX_HOME=${PROJECT_ROOT}/.shogunate/codex/agents/${role}"* ]]
                    ;;
                claude|copilot|kimi|antigravity|opencode|kilo)
                    assert_cli_state_isolated "$result" "$cli" "$role"
                    ;;
                localapi)
                    [[ "$result" == *"python3 shogunate_mod/localapi/repl.py"* ]]
                    ;;
            esac
        done
    done
}

@test "build_cli_command_with_type: OpenCode/Kilo auth共有とmodel初期seedは全役職で同じ規則になる" {
    load_adapter_with "${TEST_TMP}/settings_none.yaml"
    make_fake_cli opencode
    make_fake_cli kilo

    local roles=(shogun gunkan gunshi karo karo2 ashigaru1 ashigaru9)
    local role
    local result

    for role in "${roles[@]}"; do
        result=$(PATH="${TEST_TMP}/bin:/usr/bin:/bin" build_cli_command_with_type "$role" "opencode")
        assert_cli_host_auth_link "$result" ".local/share/opencode/auth.json" "opencode" "$role"
        assert_cli_state_symlink_removed "$result" ".local/share/opencode/opencode.db" "opencode" "$role"
        assert_cli_host_state_seed_json_default "$result" ".local/state/opencode/model.json" "opencode" "$role"
        assert_cli_state_symlink_removed "$result" ".local/state/opencode/prompt-history.jsonl" "opencode" "$role"
        [[ "$result" != *"ln -sfn ${CLI_ADAPTER_HOST_HOME}/.local/share/opencode/opencode.db"* ]]
        [[ "$result" == *"AGENT_ID=${role} OPENCODE_AGENT_ID=${role} OPENCODE_TUI_CONFIG="*"/shogunate_mod/configure/opencode-tui.json ${TEST_TMP}/bin/opencode --agent ${role}"* ]]

        result=$(PATH="${TEST_TMP}/bin:/usr/bin:/bin" build_cli_command_with_type "$role" "kilo")
        assert_cli_host_auth_link "$result" ".local/share/kilo/auth.json" "kilo" "$role"
        assert_cli_state_symlink_removed "$result" ".local/share/kilo/kilo.db" "kilo" "$role"
        assert_cli_host_state_seed "$result" ".local/state/kilo/model.json" "kilo" "$role"
        assert_cli_state_symlink_removed "$result" ".local/state/kilo/prompt-history.jsonl" "kilo" "$role"
        [[ "$result" != *"ln -sfn ${CLI_ADAPTER_HOST_HOME}/.local/share/kilo/kilo.db"* ]]
        [[ "$result" == *"AGENT_ID=${role} ${TEST_TMP}/bin/kilo"* ]]
    done
}

@test "get_model_display_name: codex は opus/sonnet 既定値ではなく Codex を表示する" {
    load_adapter_with "${TEST_TMP}/settings_codex_default.yaml"
    result=$(get_model_display_name "shogun")
    [ "$result" = "Codex" ]
}

@test "get_model_display_name: antigravity は旧Claude系デフォルトではなく Antigravity を表示する" {
    load_adapter_with "${TEST_TMP}/settings_shogun_antigravity_default.yaml"
    result=$(get_model_display_name "shogun")
    [ "$result" = "Antigravity" ]
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
    [[ "$result" == *codex" --search --sandbox danger-full-access --ask-for-approval never ready:shogun" ]]
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
    assert_cli_state_isolated "$result" "claude" "karo"
    [[ "$result" == *"AGENT_ID=karo "*claude" --model sonnet --setting-sources local --permission-mode auto ready:karo" ]]
}

@test "build_cli_command_with_startup_prompt: antigravity は startup prompt を起動引数に畳み込まない" {
    load_adapter_with "${TEST_TMP}/settings_antigravity.yaml"
    mkdir -p "${TEST_TMP}/home-empty"
    result=$(HOME="${TEST_TMP}/home-empty" PATH="/usr/bin:/bin" build_cli_command_with_startup_prompt "ashigaru2" "antigravity" "ready:ashigaru2")
    assert_cli_state_isolated "$result" "antigravity" "ashigaru2"
    assert_antigravity_launch_base "$result" "ashigaru2"
    [[ "$result" != *"ready:ashigaru2"* ]]
}

@test "build_cli_command_with_startup_prompt: opencode は --prompt を付与しない" {
    load_adapter_with "${TEST_TMP}/settings_opencode.yaml"
    result=$(build_cli_command_with_startup_prompt "shogun" "opencode" "ready:shogun")
    assert_cli_state_isolated "$result" "opencode" "shogun"
    [[ "$result" == *"AGENT_ID=shogun OPENCODE_AGENT_ID=shogun OPENCODE_TUI_CONFIG="*"/shogunate_mod/configure/opencode-tui.json "*opencode" --model ollama/qwen3-coder:30b --agent shogun" ]]
    [[ "$result" != *"--prompt"* ]]
    [[ "$result" != *"ready:shogun"* ]]
}

@test "build_cli_command_with_startup_prompt: kilo は --prompt を付与する" {
    load_adapter_with "${TEST_TMP}/settings_kilo.yaml"
    result=$(build_cli_command_with_startup_prompt "gunshi" "kilo" "ready:gunshi")
    assert_cli_state_isolated "$result" "kilo" "gunshi"
    [[ "$result" == *"AGENT_ID=gunshi "*kilo" --model lmstudio/codellama-7b.Q4_0.gguf --prompt ready:gunshi" ]]
}

@test "build_cli_command: cliセクションなし → claude フォールバック" {
    load_adapter_with "${TEST_TMP}/settings_none.yaml"
    result=$(build_cli_command "ashigaru1")
    assert_cli_state_isolated "$result" "claude" "ashigaru1"
    [[ "$result" == *"AGENT_ID=ashigaru1 "*claude*"--setting-sources local --permission-mode auto"* ]]
}

@test "build_cli_command: settings読取失敗 → claude フォールバック" {
    load_adapter_with "/nonexistent/settings.yaml"
    result=$(build_cli_command "ashigaru1")
    assert_cli_state_isolated "$result" "claude" "ashigaru1"
    [[ "$result" == *"AGENT_ID=ashigaru1 "*claude*"--setting-sources local --permission-mode auto"* ]]
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

@test "get_instruction_file: ashigaru2 + antigravity → instructions/generated/antigravity-ashigaru.md" {
    load_adapter_with "${TEST_TMP}/settings_antigravity.yaml"
    result=$(get_instruction_file "ashigaru2")
    [ "$result" = "instructions/generated/antigravity-ashigaru.md" ]
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

@test "get_instruction_file: gunkan + codex → instructions/generated/codex-gunkan.md" {
    load_adapter_with "${TEST_TMP}/settings_none.yaml"
    result=$(get_instruction_file "gunkan" "codex")
    [ "$result" = "instructions/generated/codex-gunkan.md" ]
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
    [ "$(get_instruction_file gunkan claude)" = "instructions/generated/gunkan.md" ]
    [ "$(get_instruction_file karo claude)" = "instructions/generated/karo.md" ]
    [ "$(get_instruction_file ashigaru1 claude)" = "instructions/generated/ashigaru.md" ]
    # codex
    [ "$(get_instruction_file shogun codex)" = "instructions/generated/codex-shogun.md" ]
    [ "$(get_instruction_file gunkan codex)" = "instructions/generated/codex-gunkan.md" ]
    [ "$(get_instruction_file karo codex)" = "instructions/generated/codex-karo.md" ]
    [ "$(get_instruction_file ashigaru3 codex)" = "instructions/generated/codex-ashigaru.md" ]
    # copilot
    [ "$(get_instruction_file shogun copilot)" = "instructions/generated/copilot-shogun.md" ]
    [ "$(get_instruction_file gunkan copilot)" = "instructions/generated/copilot-gunkan.md" ]
    [ "$(get_instruction_file karo copilot)" = "instructions/generated/copilot-karo.md" ]
    [ "$(get_instruction_file ashigaru5 copilot)" = "instructions/generated/copilot-ashigaru.md" ]
    # kimi
    [ "$(get_instruction_file shogun kimi)" = "instructions/generated/kimi-shogun.md" ]
    [ "$(get_instruction_file gunkan kimi)" = "instructions/generated/kimi-gunkan.md" ]
    [ "$(get_instruction_file karo kimi)" = "instructions/generated/kimi-karo.md" ]
    [ "$(get_instruction_file ashigaru7 kimi)" = "instructions/generated/kimi-ashigaru.md" ]
    # antigravity
    [ "$(get_instruction_file shogun antigravity)" = "instructions/generated/antigravity-shogun.md" ]
    [ "$(get_instruction_file gunkan antigravity)" = "instructions/generated/antigravity-gunkan.md" ]
    [ "$(get_instruction_file karo antigravity)" = "instructions/generated/antigravity-karo.md" ]
    [ "$(get_instruction_file ashigaru2 antigravity)" = "instructions/generated/antigravity-ashigaru.md" ]
    # localapi
    [ "$(get_instruction_file shogun localapi)" = "instructions/generated/localapi-shogun.md" ]
    [ "$(get_instruction_file gunkan localapi)" = "instructions/generated/localapi-gunkan.md" ]
    [ "$(get_instruction_file karo localapi)" = "instructions/generated/localapi-karo.md" ]
    [ "$(get_instruction_file ashigaru6 localapi)" = "instructions/generated/localapi-ashigaru.md" ]
    # opencode
    [ "$(get_instruction_file shogun opencode)" = "instructions/generated/opencode-shogun.md" ]
    [ "$(get_instruction_file gunkan opencode)" = "instructions/generated/opencode-gunkan.md" ]
    [ "$(get_instruction_file karo opencode)" = "instructions/generated/opencode-karo.md" ]
    [ "$(get_instruction_file ashigaru1 opencode)" = "instructions/generated/opencode-ashigaru.md" ]
    # kilo
    [ "$(get_instruction_file shogun kilo)" = "instructions/generated/kilo-shogun.md" ]
    [ "$(get_instruction_file gunkan kilo)" = "instructions/generated/kilo-gunkan.md" ]
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

@test "validate_cli_availability: antigravity mock (PATH操作)" {
    load_adapter_with "${TEST_TMP}/settings_none.yaml"
    mkdir -p "${TEST_TMP}/bin"
    echo '#!/bin/bash' > "${TEST_TMP}/bin/agy"
    chmod +x "${TEST_TMP}/bin/agy"
    PATH="${TEST_TMP}/bin:$PATH" run validate_cli_availability "antigravity"
    [ "$status" -eq 0 ]
}

@test "validate_cli_availability: antigravity はLinux keyring不足を警告する" {
    load_adapter_with "${TEST_TMP}/settings_none.yaml"
    mkdir -p "${TEST_TMP}/bin"
    cat > "${TEST_TMP}/bin/agy" << 'SH'
#!/bin/sh
exit 0
SH
    cat > "${TEST_TMP}/bin/uname" << 'SH'
#!/bin/sh
printf 'Linux\n'
SH
    chmod +x "${TEST_TMP}/bin/agy" "${TEST_TMP}/bin/uname"

    command() {
        if [ "${1:-}" = "-v" ] && [ "${2:-}" = "secret-tool" ]; then
            return 1
        fi
        builtin command "$@"
    }
    export -f command

    HOME="${TEST_TMP}/home" PATH="${TEST_TMP}/bin:/usr/bin:/bin" run validate_cli_availability "antigravity"
    [ "$status" -eq 0 ]
    [[ "$output" == *"Antigravity CLI may ask for login every time"* ]]
    [[ "$output" == *"secret-tool"* ]]
}

@test "_cli_adapter_pick_executable: PATH外の ~/.local/bin も検出する" {
    load_adapter_with "${TEST_TMP}/settings_none.yaml"
    mkdir -p "${TEST_TMP}/home/.local/bin"
    echo '#!/bin/bash' > "${TEST_TMP}/home/.local/bin/agy"
    chmod +x "${TEST_TMP}/home/.local/bin/agy"
    HOME="${TEST_TMP}/home" PATH="/usr/bin:/bin" run _cli_adapter_pick_executable "agy" "antigravity"
    [ "$status" -eq 0 ]
    [ "$output" = "${TEST_TMP}/home/.local/bin/agy" ]
}

@test "_cli_adapter_pick_executable: PATH外の ~/.nvm 配下も検出する" {
    load_adapter_with "${TEST_TMP}/settings_none.yaml"
    mkdir -p "${TEST_TMP}/home/.nvm/versions/node/v22.22.0/bin"
    echo '#!/bin/bash' > "${TEST_TMP}/home/.nvm/versions/node/v22.22.0/bin/agy"
    chmod +x "${TEST_TMP}/home/.nvm/versions/node/v22.22.0/bin/agy"
    HOME="${TEST_TMP}/home" PATH="/usr/bin:/bin" run _cli_adapter_pick_executable "agy" "antigravity"
    [ "$status" -eq 0 ]
    [ "$output" = "${TEST_TMP}/home/.nvm/versions/node/v22.22.0/bin/agy" ]
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

@test "validate_cli_availability: antigravity未インストール → 1 + エラーメッセージ" {
    load_adapter_with "${TEST_TMP}/settings_none.yaml"
    mkdir -p "${TEST_TMP}/home-empty"
    HOME="${TEST_TMP}/home-empty" PATH="/usr/bin:/bin" run validate_cli_availability "antigravity"
    [ "$status" -eq 1 ]
    [[ "$output" == *"Antigravity CLI not found"* ]]
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

@test "get_agent_model: karo2 は karo model 設定を継承する" {
    cat > "${TEST_TMP}/settings_karo_family_model.yaml" <<'YAML'
cli:
  default: codex
  agents:
    karo:
      type: codex
      model: gpt-5.5
YAML
    load_adapter_with "${TEST_TMP}/settings_karo_family_model.yaml"
    result=$(get_agent_model "karo2")
    [ "$result" = "gpt-5.5" ]
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

@test "get_agent_model: antigravity CLI ashigaru2 → auto (YAML指定)" {
    load_adapter_with "${TEST_TMP}/settings_antigravity.yaml"
    result=$(get_agent_model "ashigaru2")
    [ "$result" = "auto" ]
}

@test "get_agent_model: antigravity CLI に gpt 系 model が入っていても auto に丸める" {
    cat > "${TEST_TMP}/settings_antigravity_invalid_model2.yaml" << 'YAML'
cli:
  default: antigravity
  agents:
    shogun:
      type: antigravity
      model: gpt-5.4
YAML
    load_adapter_with "${TEST_TMP}/settings_antigravity_invalid_model2.yaml"
    result=$(get_agent_model "shogun")
    [ "$result" = "auto" ]
}

@test "get_agent_model: localapi CLI ashigaru6 → qwen2.5-coder (YAML指定)" {
    load_adapter_with "${TEST_TMP}/settings_localapi.yaml"
    result=$(get_agent_model "ashigaru6")
    [ "$result" = "qwen2.5-coder" ]
}
