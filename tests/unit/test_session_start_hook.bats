#!/usr/bin/env bats

SCRIPT_DIR="$(cd "$(dirname "$BATS_TEST_FILENAME")/../.." && pwd)"
HOOK_SCRIPT="$SCRIPT_DIR/scripts/session_start_hook.sh"

setup() {
    TEST_TMP="$(mktemp -d)"
    MOCK_BIN="$TEST_TMP/bin"
    mkdir -p "$MOCK_BIN"
    cat > "$MOCK_BIN/tmux" <<'MOCK'
#!/usr/bin/env bash
if [ "$1" = "display-message" ]; then
    printf '%s\n' "${MOCK_AGENT_ID:-}"
    exit 0
fi
exit 1
MOCK
    chmod +x "$MOCK_BIN/tmux"
}

teardown() {
    rm -rf "$TEST_TMP"
}

run_session_hook() {
    local agent_id="$1"
    __SESSION_START_HOOK_SCRIPT_DIR="$TEST_TMP" \
    TMUX_PANE="%1" \
    MOCK_AGENT_ID="$agent_id" \
    PATH="$MOCK_BIN:$PATH" \
    run bash "$HOOK_SCRIPT"
}

@test "SessionStart hook exits silently outside Shogunate panes" {
    __SESSION_START_HOOK_SCRIPT_DIR="$TEST_TMP" \
    TMUX_PANE="%1" \
    MOCK_AGENT_ID="" \
    PATH="$MOCK_BIN:$PATH" \
    run bash "$HOOK_SCRIPT"

    [ "$status" -eq 0 ]
    [ -z "$output" ]
    [ ! -f "$TEST_TMP/logs/session_start_hook.log" ]
}

@test "SessionStart hook emits command-layer persona recovery context" {
    run_session_hook "karo"

    [ "$status" -eq 0 ]
    echo "$output" | grep -q "貴殿は \\*\\*karo\\*\\*"
    echo "$output" | grep -q "instructions/karo.md"
    [ -f "$TEST_TMP/logs/session_start_hook.log" ]
    grep -q "karo session_start_hook fired" "$TEST_TMP/logs/session_start_hook.log"
}

@test "SessionStart hook emits lightweight Ashigaru recovery context" {
    run_session_hook "ashigaru2"

    [ "$status" -eq 0 ]
    echo "$output" | grep -q "queue/tasks/ashigaru2.yaml"
    echo "$output" | grep -q "足軽用軽量手順"
}
