#!/usr/bin/env bats
# test_grok_build.bats — Grok Build CLI type (GB-002) の最小検証
# allowlist / model付きcommand / credential非混入 / 未知CLI拒否を独立に検証する。

setup() {
    unset PERMISSION_FLAG
    unset NVM_BIN
    unset PNPM_HOME

    TEST_TMP="$(mktemp -d)"
    export HOME="${TEST_TMP}/home"
    export CLI_ADAPTER_HOST_HOME="${TEST_TMP}/host-home"
    mkdir -p "$HOME" "$CLI_ADAPTER_HOST_HOME"

    PROJECT_ROOT="$(cd "$(dirname "$BATS_TEST_FILENAME")/../.." && pwd)"

    cat > "${TEST_TMP}/settings_grok.yaml" << 'YAML'
cli:
  default: grok
  agents:
    ashigaru1:
      type: grok
      model: grok-4.5
    ashigaru2:
      type: grok
YAML

    cat > "${TEST_TMP}/settings_none.yaml" << 'YAML'
language: ja
YAML
}

teardown() {
    rm -rf "$TEST_TMP"
}

load_adapter_with() {
    local settings_file="$1"
    export CLI_ADAPTER_SETTINGS="$settings_file"
    export CLI_ADAPTER_PROJECT_ROOT="$PROJECT_ROOT"
    # shellcheck source=/dev/null
    source "${PROJECT_ROOT}/lib/cli_adapter.sh"
}

make_fake_cli() {
    local name="$1"
    mkdir -p "${TEST_TMP}/bin"
    printf '#!/usr/bin/env bash\nexit 0\n' > "${TEST_TMP}/bin/${name}"
    chmod +x "${TEST_TMP}/bin/${name}"
}

# ---------------------------------------------------------------------------
# 1. allowlist
# ---------------------------------------------------------------------------

@test "grok allowlist: _cli_adapter_is_valid_cli grok → 0" {
    load_adapter_with "${TEST_TMP}/settings_none.yaml"
    run _cli_adapter_is_valid_cli "grok"
    [ "$status" -eq 0 ]
}

@test "grok allowlist: get_cli_type ashigaru1 (type: grok) → grok" {
    load_adapter_with "${TEST_TMP}/settings_grok.yaml"
    result=$(get_cli_type "ashigaru1")
    [ "$result" = "grok" ]
}

@test "grok allowlist: runtime_roles ALLOWED_CLIS に grok が含まれる" {
    run python3 -c "
from pathlib import Path
import runpy
mod = runpy.run_path('${PROJECT_ROOT}/shogunate_mod/configure/runtime_roles.py')
assert 'grok' in mod['ALLOWED_CLIS'], mod['ALLOWED_CLIS']
print('ok')
"
    [ "$status" -eq 0 ]
    [[ "$output" == *"ok"* ]]
}

@test "grok allowlist: role_failover ALLOWED_CLIS に grok が含まれる" {
    run python3 -c "
from pathlib import Path
import runpy
mod = runpy.run_path('${PROJECT_ROOT}/shogunate_mod/runtime/role_failover.py')
assert 'grok' in mod['ALLOWED_CLIS'], mod['ALLOWED_CLIS']
print('ok')
"
    [ "$status" -eq 0 ]
    [[ "$output" == *"ok"* ]]
}

# ---------------------------------------------------------------------------
# 2. model付きcommand
# ---------------------------------------------------------------------------

@test "grok command: model付き → grok --model grok-4.5 を別引数で生成" {
    load_adapter_with "${TEST_TMP}/settings_grok.yaml"
    make_fake_cli grok
    result=$(PATH="${TEST_TMP}/bin:/usr/bin:/bin" HOME="${TEST_TMP}/home" \
        build_cli_command_with_type "ashigaru1" "grok")
    [[ "$result" == *"AGENT_ID=ashigaru1 "* ]]
    [[ "$result" == *"${TEST_TMP}/bin/grok --model grok-4.5"* ]] || \
        [[ "$result" == *" grok --model grok-4.5"* ]] || \
        [[ "$result" == *"/grok --model grok-4.5"* ]]
    # 結合形 --model= は使わない（固定flagと値を別argv）
    [[ "$result" != *"--model="* ]]
}

@test "grok command: model無し → --model を付けない" {
    load_adapter_with "${TEST_TMP}/settings_grok.yaml"
    make_fake_cli grok
    result=$(PATH="${TEST_TMP}/bin:/usr/bin:/bin" HOME="${TEST_TMP}/home" \
        build_cli_command_with_type "ashigaru2" "grok")
    [[ "$result" == *"AGENT_ID=ashigaru2 "* ]]
    [[ "$result" == *"/grok"* ]] || [[ "$result" == *" grok"* ]]
    [[ "$result" != *"--model"* ]]
}

# ---------------------------------------------------------------------------
# 3. credential非混入
# ---------------------------------------------------------------------------

@test "grok command: token/credential/api-key を command へ埋め込まない" {
    load_adapter_with "${TEST_TMP}/settings_grok.yaml"
    make_fake_cli grok
    # 環境に認証らしき値があっても command builder はそれを取り込まない
    result=$(
        PATH="${TEST_TMP}/bin:/usr/bin:/bin" HOME="${TEST_TMP}/home" \
        GROK_API_KEY="secret-should-not-appear" \
        XAI_API_KEY="xai-secret-should-not-appear" \
        API_TOKEN="token-should-not-appear" \
        build_cli_command_with_type "ashigaru1" "grok"
    )
    [[ "$result" != *"secret-should-not-appear"* ]]
    [[ "$result" != *"xai-secret-should-not-appear"* ]]
    [[ "$result" != *"token-should-not-appear"* ]]
    [[ "$result" != *"--api-key"* ]]
    [[ "$result" != *"--token"* ]]
    [[ "$result" != *"GROK_API_KEY="* ]]
    [[ "$result" != *"XAI_API_KEY="* ]]
    [[ "$result" != *"API_TOKEN="* ]]
    [[ "$result" != *"Bearer "* ]]
    [[ "$result" != *"authorization"* ]]
}

# ---------------------------------------------------------------------------
# 4. 未知CLI拒否
# ---------------------------------------------------------------------------

@test "未知CLI拒否: validate_cli_availability invalid_type → 1 + Unknown" {
    load_adapter_with "${TEST_TMP}/settings_none.yaml"
    run validate_cli_availability "invalid_type"
    [ "$status" -eq 1 ]
    [[ "$output" == *"Unknown CLI type"* ]]
}

@test "未知CLI拒否: _cli_adapter_is_valid_cli not-a-cli → 1" {
    load_adapter_with "${TEST_TMP}/settings_none.yaml"
    run _cli_adapter_is_valid_cli "not-a-cli"
    [ "$status" -ne 0 ]
}

@test "未知CLI拒否: runtime_roles は grok以外の未知CLIを拒否する" {
    run python3 -c "
import runpy, sys
mod = runpy.run_path('${PROJECT_ROOT}/shogunate_mod/configure/runtime_roles.py')
normalize = mod['normalize_cli']
try:
    normalize('not-a-real-cli', field='--cli')
except SystemExit as exc:
    msg = str(exc)
    assert 'not-a-real-cli' in msg or 'unsupported' in msg.lower() or 'Allowed' in msg
    print('ok')
    sys.exit(0)
raise SystemExit('expected SystemExit for unknown CLI')
"
    [ "$status" -eq 0 ]
    [[ "$output" == *"ok"* ]]
}

# ---------------------------------------------------------------------------
# 5. configurator への grok 受け入れ（GB-003A）
# ---------------------------------------------------------------------------

@test "configure_runtime_roles: --shogun grok で type: grok を保存する" {
    mkdir -p "${TEST_TMP}/scripts" "${TEST_TMP}/config" "${TEST_TMP}/shogunate_mod/configure"
    cp "$PROJECT_ROOT/scripts/configure_runtime_roles.py" "${TEST_TMP}/scripts/configure_runtime_roles.py"
    cp "$PROJECT_ROOT/shogunate_mod/configure/runtime_roles.py" "${TEST_TMP}/shogunate_mod/configure/runtime_roles.py"
    chmod +x "${TEST_TMP}/scripts/configure_runtime_roles.py"

    cat > "${TEST_TMP}/config/settings.yaml" << 'YAML'
language: ja
cli:
  default: codex
  agents:
    shogun:
      type: codex
    karo:
      type: codex
    gunkan:
      type: codex
    gunshi:
      type: codex
    ashigaru1:
      type: codex
YAML

    run bash -lc "cd '${TEST_TMP}' && python3 scripts/configure_runtime_roles.py --ashigaru-count 1 --shogun grok --gunkan codex --karo grok --gunshi codex --ashigaru1 grok"
    [ "$status" -eq 0 ]

    run python3 - "${TEST_TMP}/config/settings.yaml" << 'PY'
import sys, yaml
cfg = yaml.safe_load(open(sys.argv[1], encoding='utf-8'))
agents = cfg["cli"]["agents"]
assert agents["shogun"] == {"type": "grok"}, agents["shogun"]
assert agents["karo"] == {"type": "grok"}, agents["karo"]
assert agents["ashigaru1"] == {"type": "grok"}, agents["ashigaru1"]
assert agents["gunkan"] == {"type": "codex"}
assert agents["gunshi"] == {"type": "codex"}
print("ok")
PY
    [ "$status" -eq 0 ]
    [[ "$output" == *"ok"* ]]
}

@test "configure_runtime_roles: --preserve-model-prefs で grok+model を残す" {
    mkdir -p "${TEST_TMP}/scripts" "${TEST_TMP}/config" "${TEST_TMP}/shogunate_mod/configure"
    cp "$PROJECT_ROOT/scripts/configure_runtime_roles.py" "${TEST_TMP}/scripts/configure_runtime_roles.py"
    cp "$PROJECT_ROOT/shogunate_mod/configure/runtime_roles.py" "${TEST_TMP}/shogunate_mod/configure/runtime_roles.py"
    chmod +x "${TEST_TMP}/scripts/configure_runtime_roles.py"

    cat > "${TEST_TMP}/config/settings.yaml" << 'YAML'
language: ja
cli:
  default: grok
  agents:
    shogun:
      type: grok
      model: grok-4.5
      thinking: false
    karo:
      type: grok
    gunkan:
      type: grok
    gunshi:
      type: grok
    ashigaru1:
      type: grok
YAML

    run bash -lc "cd '${TEST_TMP}' && python3 scripts/configure_runtime_roles.py --preserve-model-prefs --ashigaru-count 1 --shogun grok --gunkan grok --karo grok --gunshi grok --ashigaru1 grok"
    [ "$status" -eq 0 ]

    run python3 - "${TEST_TMP}/config/settings.yaml" << 'PY'
import sys, yaml
cfg = yaml.safe_load(open(sys.argv[1], encoding='utf-8'))
agents = cfg["cli"]["agents"]
assert agents["shogun"]["type"] == "grok"
assert agents["shogun"]["model"] == "grok-4.5"
assert agents["shogun"]["thinking"] is False
print("ok")
PY
    [ "$status" -eq 0 ]
    [[ "$output" == *"ok"* ]]
}

# ---------------------------------------------------------------------------
# 6. validate_cli_availability grok
# ---------------------------------------------------------------------------

@test "validate_cli_availability grok: PATH に grok があれば 0" {
    load_adapter_with "${TEST_TMP}/settings_none.yaml"
    mkdir -p "${TEST_TMP}/bin"
    printf '#!/usr/bin/env bash\nexit 0\n' > "${TEST_TMP}/bin/grok"
    chmod +x "${TEST_TMP}/bin/grok"
    PATH="${TEST_TMP}/bin:/usr/bin:/bin" HOME="${TEST_TMP}/home" run validate_cli_availability "grok"
    [ "$status" -eq 0 ]
}

@test "validate_cli_availability grok: 未インストールなら 1 + Grok Build CLI not found" {
    load_adapter_with "${TEST_TMP}/settings_none.yaml"
    HOME="${TEST_TMP}/home-empty" PATH="/usr/bin:/bin" run validate_cli_availability "grok"
    [ "$status" -eq 1 ]
    [[ "$output" == *"Grok Build CLI not found"* ]]
}

# ---------------------------------------------------------------------------
# 7. instruction 解決と generated file（GB-003A）
# ---------------------------------------------------------------------------

@test "get_instruction_file: grok role → instructions/generated/grok-<role>.md" {
    load_adapter_with "${TEST_TMP}/settings_grok.yaml"
    [ "$(get_instruction_file shogun grok)" = "instructions/generated/grok-shogun.md" ]
    [ "$(get_instruction_file gunkan grok)" = "instructions/generated/grok-gunkan.md" ]
    [ "$(get_instruction_file gunshi grok)" = "instructions/generated/grok-gunshi.md" ]
    [ "$(get_instruction_file karo grok)" = "instructions/generated/grok-karo.md" ]
    [ "$(get_instruction_file ashigaru1 grok)" = "instructions/generated/grok-ashigaru.md" ]
}

@test "instructions/generated/grok-<role>.md が build.sh で生成済みで Grok Build 部を含む" {
    for role in shogun gunkan karo gunshi ashigaru; do
        [ -f "$PROJECT_ROOT/instructions/generated/grok-${role}.md" ]
        grep -q "Grok Build CLI" "$PROJECT_ROOT/instructions/generated/grok-${role}.md"
        # harness section も含む
        grep -q "CLI Harness: Grok" "$PROJECT_ROOT/instructions/generated/grok-${role}.md"
    done
}

@test "ensure_generated.sh に grok target が列挙されている" {
    grep -q 'instructions/generated/grok-shogun.md' "$PROJECT_ROOT/shogunate_mod/instructions/ensure_generated.sh"
    grep -q 'instructions/generated/grok-ashigaru.md' "$PROJECT_ROOT/shogunate_mod/instructions/ensure_generated.sh"
}

# ---------------------------------------------------------------------------
# 8. GB-003B attempt 3: pure classifier / watcher wiring / marker design
# ---------------------------------------------------------------------------

@test "grok_classify_failure_text: 'You are not authenticated' → auth_error" {
    source "${PROJECT_ROOT}/shogunate_mod/runtime/grok_failure.sh"
    [ "$(grok_classify_failure_text "You are not authenticated")" = "auth_error" ]
}

@test "grok_classify_failure_text: 'Authentication failed' → auth_error" {
    source "${PROJECT_ROOT}/shogunate_mod/runtime/grok_failure.sh"
    [ "$(grok_classify_failure_text "Authentication failed")" = "auth_error" ]
}

@test "grok_classify_failure_text: 'Authentication required' → auth_error" {
    source "${PROJECT_ROOT}/shogunate_mod/runtime/grok_failure.sh"
    [ "$(grok_classify_failure_text "Authentication required")" = "auth_error" ]
}

@test "grok_classify_failure_text: 'Rate limit exceeded. Retry later.' → rate_limit" {
    source "${PROJECT_ROOT}/shogunate_mod/runtime/grok_failure.sh"
    [ "$(grok_classify_failure_text "Rate limit exceeded. Retry later.")" = "rate_limit" ]
}

@test "grok_classify_failure_text: 'Too many requests, slow down.' → rate_limit" {
    source "${PROJECT_ROOT}/shogunate_mod/runtime/grok_failure.sh"
    [ "$(grok_classify_failure_text "Too many requests, slow down.")" = "rate_limit" ]
}

@test "grok_classify_failure_text: 行認識 — auth 行が multiline snapshot の中心行にあっても auth_error" {
    source "${PROJECT_ROOT}/shogunate_mod/runtime/grok_failure.sh"
    result=$(grok_classify_failure_text "$(printf 'setting up TUI\nAuthentication required\nBreak here')")
    [ "$result" = "auth_error" ]
}

@test "grok_classify_failure_text: 未知 text → 空" {
    source "${PROJECT_ROOT}/shogunate_mod/runtime/grok_failure.sh"
    [ -z "$(grok_classify_failure_text "Some random assembly output")" ]
}

@test "grok_classify_failure_text: 空 input → 空" {
    source "${PROJECT_ROOT}/shogunate_mod/runtime/grok_failure.sh"
    [ -z "$(grok_classify_failure_text "")" ]
}

@test "grok_classify_failure_text: 行末の CRLF は除去されてから比較される" {
    source "${PROJECT_ROOT}/shogunate_mod/runtime/grok_failure.sh"
    [ "$(grok_classify_failure_text $'Authentication failed\r')" = "auth_error" ]
}

@test "grok_classify_failure_text: false-positive 拒否 — 'please sign in' を含む narrative は空" {
    source "${PROJECT_ROOT}/shogunate_mod/runtime/grok_failure.sh"
    [ -z "$(grok_classify_failure_text "We need you to please sign in to continue")" ]
}

@test "grok_classify_failure_text: false-positive 拒否 — 'rate limit を実装する' は空" {
    source "${PROJECT_ROOT}/shogunate_mod/runtime/grok_failure.sh"
    [ -z "$(grok_classify_failure_text "今度 rate limit を実装する必要がある")" ]
}

@test "grok_classify_failure_text: false-positive 拒否 — 'Authentication failed but ignored' は空（行全体不一致）" {
    source "${PROJECT_ROOT}/shogunate_mod/runtime/grok_failure.sh"
    [ -z "$(grok_classify_failure_text "The prompt said Authentication failed but we ignored it")" ]
}

@test "grok_classify_failure_text: false-positive 拒否 — 'rate limit' 単独語句は空" {
    source "${PROJECT_ROOT}/shogunate_mod/runtime/grok_failure.sh"
    [ -z "$(grok_classify_failure_text "rate limit")" ]
}

@test "grok_classify_failure_text: false-positive 拒否 — 'authentication error' は空（既知行でない）" {
    source "${PROJECT_ROOT}/shogunate_mod/runtime/grok_failure.sh"
    [ -z "$(grok_classify_failure_text "authentication error")" ]
}

@test "grok_classify_failure_text: false-positive 拒否 — rate-limit prefix で始まる一般説明は空" {
    source "${PROJECT_ROOT}/shogunate_mod/runtime/grok_failure.sh"
    [ -z "$(grok_classify_failure_text "Rate limit exceeded errors are described in this documentation")" ]
    [ -z "$(grok_classify_failure_text "Too many requests can reduce system throughput")" ]
}

@test "inbox_watcher helper path: BASH_SOURCE から解決し MOD_WATCHER_DIR を信頼しない" {
    [ -f "$PROJECT_ROOT/shogunate_mod/runtime/grok_failure.sh" ]
    local fake_dir
    fake_dir="$(mktemp -d)"
    # MOD_WATCHER_DIR を無効 dir へ偽装しても BASH_SOURCE 経由で本物の
    # runtime/grok_failure.sh が読まれ grok_classify_failure_text が定義される。
    # もし環境変数を信頼すると、偽装 dir 配下に helper は存在せず定義されず、
    # declare -F が非0になり test が fail する。
    MOD_WATCHER_DIR="$fake_dir" __INBOX_WATCHER_TESTING__=1 run bash -c "
        source '${PROJECT_ROOT}/shogunate_mod/watcher/inbox_watcher.sh'
        declare -F grok_classify_failure_text >/dev/null
    "
    [ "$status" -eq 0 ]
    rm -rf "$fake_dir"
}

@test "inbox_watcher helper path: symlink の BASH_SOURCE は実 target へ解決する" {
    local fake_root="${TEST_TMP}/external-watcher"
    mkdir -p "${fake_root}/watcher" "${fake_root}/runtime"
    ln -s "${PROJECT_ROOT}/shogunate_mod/watcher/inbox_watcher.sh" \
        "${fake_root}/watcher/inbox_watcher.sh"
    printf '%s\n' 'grok_classify_failure_text() { printf external_helper; }' \
        > "${fake_root}/runtime/grok_failure.sh"

    __INBOX_WATCHER_TESTING__=1 run bash -c "
        source '${fake_root}/watcher/inbox_watcher.sh'
        [ \"\$(grok_classify_failure_text 'Authentication required')\" = auth_error ]
    "
    [ "$status" -eq 0 ]
}

@test "maintain_grok_runtime_failure_guard: grok + auth_error pane → explicit_failure with fixed reason" {
    local fake_root fake_bin fake_runner fake_state
    fake_root="$(mktemp -d)"
    fake_bin="${fake_root}/bin"
    mkdir -p "${fake_root}/queue/runtime" "${fake_root}/shogunate_mod/runtime" "$fake_bin"
    : > "${fake_root}/queue/runtime/role_failover.yaml"

    fake_runner="${fake_root}/shogunate_mod/runtime/role_failover_runner.sh"
    cat > "$fake_runner" << 'SH'
#!/usr/bin/env bash
printf '%s\n' "$*" >> "$RUNNER_RECORD_PATH"
SH
    chmod +x "$fake_runner"

    fake_state="${fake_root}/gen_state.txt"
    printf '5\n' > "$fake_state"

    cat > "${fake_bin}/tmux" << 'SH'
#!/usr/bin/env bash
case "$1" in
    capture-pane)
        printf '%s\n' 'Some harmless log line' 'You are not authenticated' ''
        ;;
    show-options)
        if [[ "$6" == "@role_generation" ]]; then
            cat "$GEN_STATE_FILE"
        fi
        ;;
esac
SH
    chmod +x "${fake_bin}/tmux"

    local runner_record="${fake_root}/runner_args.txt"
    : > "$runner_record"

    AGENT_ID="ashigaru1" PANE_TARGET="multi:0.1" SCRIPT_DIR="$fake_root" \
        PATH="${fake_bin}:${PATH}" __INBOX_WATCHER_TESTING__=1 \
        RUNNER_RECORD_PATH="$runner_record" GEN_STATE_FILE="$fake_state" \
        run bash -c "
        source '${PROJECT_ROOT}/shogunate_mod/watcher/inbox_watcher.sh'
        maintain_grok_runtime_failure_guard 'grok'
    "
    [ "$status" -eq 0 ]
    [ -f "$runner_record" ]
    run cat "$runner_record"
    [[ "$output" == *"explicit_failure ashigaru1 5 auth_error multi:0.1"* ]]
    rm -rf "$fake_root"
}

@test "maintain_grok_runtime_failure_guard: 明白な非grok CLI なら呼出0回で即 return 0" {
    local fake_root fake_bin runner_record
    fake_root="$(mktemp -d)"
    fake_bin="${fake_root}/bin"
    mkdir -p "${fake_root}/queue/runtime" "${fake_root}/shogunate_mod/runtime" "$fake_bin"
    : > "${fake_root}/queue/runtime/role_failover.yaml"

    local fake_runner="${fake_root}/shogunate_mod/runtime/role_failover_runner.sh"
    cat > "$fake_runner" << 'SH'
#!/usr/bin/env bash
printf '%s\n' "$*" >> "$RUNNER_RECORD_PATH"
SH
    chmod +x "$fake_runner"

    cat > "${fake_bin}/tmux" << 'SH'
#!/usr/bin/env bash
case "$1" in
    capture-pane)
        printf '%s\n' 'You are not authenticated'
        ;;
    show-options)
        printf '5\n'
        ;;
esac
SH
    chmod +x "${fake_bin}/tmux"

    runner_record="${fake_root}/runner_args.txt"
    : > "$runner_record"

    # OpenCode 等、grok 以外の CLI では auth pane が見えても発火しない。
    AGENT_ID="ashigaru1" PANE_TARGET="multi:0.1" SCRIPT_DIR="$fake_root" \
        PATH="${fake_bin}:${PATH}" __INBOX_WATCHER_TESTING__=1 \
        RUNNER_RECORD_PATH="$runner_record" \
        run bash -c "
        source '${PROJECT_ROOT}/shogunate_mod/watcher/inbox_watcher.sh'
        maintain_grok_runtime_failure_guard 'opencode'
    "
    [ "$status" -eq 0 ]
    [ ! -s "$runner_record" ]
    rm -rf "$fake_root"
}

@test "maintain_grok_runtime_failure_guard: marker 名は generation を含み raw pane text を書かない" {
    local fake_root fake_bin fake_state runner_record
    fake_root="$(mktemp -d)"
    fake_bin="${fake_root}/bin"
    mkdir -p "${fake_root}/queue/runtime" "${fake_root}/shogunate_mod/runtime" "$fake_bin"
    : > "${fake_root}/queue/runtime/role_failover.yaml"

    local fake_runner="${fake_root}/shogunate_mod/runtime/role_failover_runner.sh"
    cat > "$fake_runner" << 'SH'
#!/usr/bin/env bash
printf '%s\n' "$*" >> "$RUNNER_RECORD_PATH"
SH
    chmod +x "$fake_runner"

    fake_state="${fake_root}/gen_state.txt"
    printf '7\n' > "$fake_state"

    cat > "${fake_bin}/tmux" << 'SH'
#!/usr/bin/env bash
case "$1" in
    capture-pane)
        printf '%s\n' 'Rate limit exceeded. Retry in 60s.' ''
        ;;
    show-options)
        if [[ "$6" == "@role_generation" ]]; then
            cat "$GEN_STATE_FILE"
        fi
        ;;
esac
SH
    chmod +x "${fake_bin}/tmux"

    runner_record="${fake_root}/runner_args.txt"
    : > "$runner_record"

    AGENT_ID="ashigaru2" PANE_TARGET="shogun:0.0" SCRIPT_DIR="$fake_root" \
        PATH="${fake_bin}:${PATH}" __INBOX_WATCHER_TESTING__=1 \
        RUNNER_RECORD_PATH="$runner_record" GEN_STATE_FILE="$fake_state" \
        run bash -c "
        source '${PROJECT_ROOT}/shogunate_mod/watcher/inbox_watcher.sh'
        maintain_grok_runtime_failure_guard 'grok'
    "
    [ "$status" -eq 0 ]
    [[ "$output" != *"Retry in 60s"* ]]

    local expected_marker="${fake_root}/queue/runtime/runtime_blocked_relay/ashigaru2__grok-rate_limit-generation7.sent"
    [ -f "$expected_marker" ]
    # marker is empty (no raw pane text)
    [ ! -s "$expected_marker" ]
    if grep -q "Rate limit" "$expected_marker" 2>/dev/null; then
        echo "raw pane text leaked into marker file" >&2
        false
    fi
    # runner was invoked with fixed reason
    [ -s "$runner_record" ]
    run cat "$runner_record"
    [[ "$output" == *"explicit_failure ashigaru2 7 rate_limit shogun:0.0"* ]]
    rm -rf "$fake_root"
}

@test "maintain_grok_runtime_failure_guard: 同一 generation は1回のみ・次 generation は再発火" {
    local fake_root fake_bin fake_state runner_record
    fake_root="$(mktemp -d)"
    fake_bin="${fake_root}/bin"
    mkdir -p "${fake_root}/queue/runtime" "${fake_root}/shogunate_mod/runtime" "$fake_bin"
    : > "${fake_root}/queue/runtime/role_failover.yaml"

    local fake_runner="${fake_root}/shogunate_mod/runtime/role_failover_runner.sh"
    cat > "$fake_runner" << 'SH'
#!/usr/bin/env bash
printf '%s\n' "$*" >> "$RUNNER_RECORD_PATH"
SH
    chmod +x "$fake_runner"

    fake_state="${fake_root}/gen_state.txt"
    printf '5\n' > "$fake_state"

    cat > "${fake_bin}/tmux" << 'SH'
#!/usr/bin/env bash
case "$1" in
    capture-pane)
        printf '%s\n' 'You are not authenticated'
        ;;
    show-options)
        if [[ "$6" == "@role_generation" ]]; then
            cat "$GEN_STATE_FILE"
        fi
        ;;
esac
SH
    chmod +x "${fake_bin}/tmux"

    runner_record="${fake_root}/runner_args.txt"
    : > "$runner_record"

    # 1回目: gen5 — marker 無 → 発火。2回目: gen5 — marker 在 → 抑止。
    AGENT_ID="ashigaru3" PANE_TARGET="multi:0.3" SCRIPT_DIR="$fake_root" \
        PATH="${fake_bin}:${PATH}" __INBOX_WATCHER_TESTING__=1 \
        RUNNER_RECORD_PATH="$runner_record" GEN_STATE_FILE="$fake_state" \
        run bash -c "
        source '${PROJECT_ROOT}/shogunate_mod/watcher/inbox_watcher.sh'
        maintain_grok_runtime_failure_guard 'grok'
        maintain_grok_runtime_failure_guard 'grok'
    "
    [ "$status" -eq 0 ]
    [ "$(wc -l < "$runner_record")" -eq 1 ]

    # generation を6へ進める。次の maintain は新 marker を作り再度1回発火。
    printf '6\n' > "$fake_state"

    AGENT_ID="ashigaru3" PANE_TARGET="multi:0.3" SCRIPT_DIR="$fake_root" \
        PATH="${fake_bin}:${PATH}" __INBOX_WATCHER_TESTING__=1 \
        RUNNER_RECORD_PATH="$runner_record" GEN_STATE_FILE="$fake_state" \
        run bash -c "
        source '${PROJECT_ROOT}/shogunate_mod/watcher/inbox_watcher.sh'
        maintain_grok_runtime_failure_guard 'grok'
    "
    [ "$status" -eq 0 ]
    [ "$(wc -l < "$runner_record")" -eq 2 ]

    # 両 generation の marker file が別物で存在する。
    local marker5="${fake_root}/queue/runtime/runtime_blocked_relay/ashigaru3__grok-auth_error-generation5.sent"
    local marker6="${fake_root}/queue/runtime/runtime_blocked_relay/ashigaru3__grok-auth_error-generation6.sent"
    [ -f "$marker5" ]
    [ -f "$marker6" ]
    [ ! -s "$marker5" ]
    [ ! -s "$marker6" ]
    rm -rf "$fake_root"
}
