#!/usr/bin/env bats
# Isolated Grok runtime E2E: real tmux with an in-test fake CLI.

# bats file_tags=e2e

setup() {
    PROJECT_ROOT="$(cd "$(dirname "$BATS_TEST_FILENAME")/../.." && pwd)"
    TMUX_REAL="$(command -v tmux)"
    E2E_ROOT="$BATS_TEST_TMPDIR/project"
    E2E_BIN="$E2E_ROOT/bin"
    E2E_HOME="$E2E_ROOT/home"
    E2E_TMUX_TMP="$E2E_ROOT/tmux"
    E2E_SOCKET="gb005-runtime-${BATS_TEST_NUMBER}-$$-$RANDOM"
    CONTROL_SOCKET="gb005-control-${BATS_TEST_NUMBER}-$$-$RANDOM"
    SETTINGS="$E2E_ROOT/config/settings.yaml"
    STATE="$E2E_ROOT/queue/runtime/role_failover.yaml"
    ARGV_LOG="$E2E_ROOT/argv.log"
    COUNT_FILE="$E2E_ROOT/invocation.count"
    RUNTIME_PANE=""
    CONTROL_PANE=""

    mkdir -p \
        "$E2E_BIN" \
        "$E2E_HOME" \
        "$E2E_TMUX_TMP" \
        "$E2E_ROOT/host-home" \
        "$E2E_ROOT/config" \
        "$E2E_ROOT/queue/runtime" \
        "$E2E_ROOT/shogunate_mod/runtime"
    chmod 700 "$E2E_TMUX_TMP"

    ln -s "$PROJECT_ROOT/shogunate_mod/runtime/role_failover.py" \
        "$E2E_ROOT/shogunate_mod/runtime/role_failover.py"
    ln -s "$PROJECT_ROOT/shogunate_mod/runtime/role_failover_runner.sh" \
        "$E2E_ROOT/shogunate_mod/runtime/role_failover_runner.sh"

    cat > "$SETTINGS" <<'YAML'
cli:
  agents:
    ashigaru1:
      type: grok
      model: grok-4.5
      fallback:
        type: grok
        model: grok-4.5
YAML

    cat > "$E2E_BIN/tmux" <<'SH'
#!/usr/bin/env bash
if [[ -z "${TMUX_REAL_BIN:-}" || -z "${TMUX_SOCKET_NAME:-}" ]]; then
    exit 97
fi
exec "$TMUX_REAL_BIN" -L "$TMUX_SOCKET_NAME" "$@"
SH
    chmod +x "$E2E_BIN/tmux"

    cat > "$E2E_BIN/grok" <<'SH'
#!/usr/bin/env bash
count=0
if [[ -f "$GROK_E2E_COUNT" ]]; then
    read -r count < "$GROK_E2E_COUNT" || count=0
fi
count=$((count + 1))
printf '%s\n' "$count" > "$GROK_E2E_COUNT"
{
    printf 'invocation=%s\n' "$count"
    printf 'argc=%s\n' "$#"
    index=1
    for arg in "$@"; do
        printf 'arg%s=%s\n' "$index" "$arg"
        index=$((index + 1))
    done
    printf 'end\n'
} >> "$GROK_E2E_ARGV"

case "$count" in
    1)
        printf 'fake grok startup\n'
        exit 17
        ;;
    2)
        printf 'You are not authenticated.\n'
        ;;
    *)
        printf 'Rate limit exceeded. Retry later.\n'
        ;;
esac

while IFS= read -r line; do
    [[ "$line" == "exit" ]] && exit 0
done
SH
    chmod +x "$E2E_BIN/grok"

    cat > "$E2E_ROOT/queue/runtime/launch_ashigaru1.sh" <<'SH'
#!/usr/bin/env bash
set -uo pipefail

source "$PRODUCTION_ROOT/shogunate_mod/cli/adapter.sh"
load_active_role_profile ashigaru1 || exit 31
generation="$CLI_ACTIVE_PROFILE_GENERATION"
slot="$CLI_ACTIVE_PROFILE_SLOT"
tmux set-option -p -t "$TMUX_PANE" @agent_id ashigaru1
tmux set-option -p -t "$TMUX_PANE" @agent_cli grok
tmux set-option -p -t "$TMUX_PANE" @role_generation "$generation"
tmux set-option -p -t "$TMUX_PANE" @role_slot "$slot"
runtime_launch_cmd="$(build_cli_command_with_type ashigaru1 grok)" || exit 32
printf 'launch generation=%s slot=%s\n' "$generation" "$slot"
bash -lc "$runtime_launch_cmd"
status=$?
printf 'fake grok exited status=%s generation=%s\n' "$status" "$generation"
if [[ -f "$SHOGUNATE_RUNTIME_DIR/queue/runtime/intentional_stop" ]]; then
    bash "$SHOGUNATE_RUNTIME_DIR/shogunate_mod/runtime/role_failover_runner.sh" \
        user_stop ashigaru1 "$generation" intentional_stop "$TMUX_PANE" || true
else
    bash "$SHOGUNATE_RUNTIME_DIR/shogunate_mod/runtime/role_failover_runner.sh" \
        process_exit ashigaru1 "$generation" process_exit "$TMUX_PANE" || true
fi
exit 0
SH
    chmod +x "$E2E_ROOT/queue/runtime/launch_ashigaru1.sh"

    python3 "$PROJECT_ROOT/shogunate_mod/runtime/role_failover.py" \
        --root "$E2E_ROOT" init-role --role ashigaru1 --event-id gb005-init \
        --settings "$SETTINGS" --reset >/dev/null

    control_tmux new-session -d -s preexisting -n untouched "/bin/bash --noprofile --norc"
    CONTROL_PANE="$(control_tmux display-message -p -t preexisting:untouched '#{pane_id}')"
    CONTROL_PID="$(control_tmux display-message -p -t "$CONTROL_PANE" '#{pane_pid}')"
    control_tmux set-option -p -t "$CONTROL_PANE" @gb005_sentinel unchanged

    main_tmux new-session -d -s runtime -n grok \
        "bash '$E2E_ROOT/queue/runtime/launch_ashigaru1.sh'"
    RUNTIME_PANE="$(main_tmux display-message -p -t runtime:grok '#{pane_id}')"
}

teardown() {
    if [[ -n "${RUNTIME_PANE:-}" ]] && main_tmux display-message -p -t "$RUNTIME_PANE" '#{pane_id}' >/dev/null 2>&1; then
        : > "$E2E_ROOT/queue/runtime/intentional_stop"
        main_tmux send-keys -l -t "$RUNTIME_PANE" exit >/dev/null 2>&1 || true
        main_tmux send-keys -t "$RUNTIME_PANE" Enter >/dev/null 2>&1 || true
        wait_for 80 runtime_server_gone || return 1
    fi
    if [[ -n "${CONTROL_PANE:-}" ]] && control_tmux display-message -p -t "$CONTROL_PANE" '#{pane_id}' >/dev/null 2>&1; then
        control_tmux send-keys -l -t "$CONTROL_PANE" exit >/dev/null 2>&1 || true
        control_tmux send-keys -t "$CONTROL_PANE" Enter >/dev/null 2>&1 || true
        wait_for 80 control_server_gone || return 1
    fi
}

main_tmux() {
    env -i \
        HOME="$E2E_HOME" \
        LANG=C.UTF-8 \
        PATH="$E2E_BIN:/usr/bin:/bin" \
        PRODUCTION_ROOT="$PROJECT_ROOT" \
        SHOGUNATE_RUNTIME_DIR="$E2E_ROOT" \
        CLI_ADAPTER_PROJECT_ROOT="$PROJECT_ROOT" \
        CLI_ADAPTER_SETTINGS="$SETTINGS" \
        CLI_ADAPTER_FAILOVER_ROOT="$E2E_ROOT" \
        CLI_ADAPTER_HOST_HOME="$E2E_ROOT/host-home" \
        SHOGUNATE_ROLE_RESTART_COOLDOWN_SECONDS=0 \
        GROK_E2E_ARGV="$ARGV_LOG" \
        GROK_E2E_COUNT="$COUNT_FILE" \
        TMUX_REAL_BIN="$TMUX_REAL" \
        TMUX_SOCKET_NAME="$E2E_SOCKET" \
        TMUX_TMPDIR="$E2E_TMUX_TMP" \
        TERM=xterm-256color \
        "$E2E_BIN/tmux" "$@"
}

control_tmux() {
    env -i HOME="$E2E_HOME" LANG=C.UTF-8 PATH=/usr/bin:/bin TERM=xterm-256color \
        TMUX_TMPDIR="$E2E_TMUX_TMP" \
        "$TMUX_REAL" -L "$CONTROL_SOCKET" "$@"
}

wait_for() {
    local attempts="$1"
    shift
    local index
    for ((index = 0; index < attempts; index++)); do
        "$@" && return 0
        sleep 0.1
    done
    "$@"
}

invocation_count_is() {
    [[ -f "$COUNT_FILE" ]] || return 1
    [[ "$(tr -d '\r\n' < "$COUNT_FILE")" == "$1" ]]
}

pane_has_text() {
    main_tmux capture-pane -p -t "$RUNTIME_PANE" -S -40 2>/dev/null | grep -Fq "$1"
}

role_state_is() {
    python3 - "$STATE" "$1" "$2" "$3" "$4" <<'PY'
import sys
import yaml

path, generation, slot, reason, restart_count = sys.argv[1:]
role = yaml.safe_load(open(path, encoding="utf-8"))["roles"]["ashigaru1"]
assert role["generation"] == int(generation), role
assert role["active_slot"] == slot, role
assert role.get("failure_reason") == (None if reason == "none" else reason), role
assert role["primary_restart_count"] == int(restart_count), role
PY
}

run_guard() {
    local log_file="$1"
    env -i \
        HOME="$E2E_HOME" \
        LANG=C.UTF-8 \
        PATH="$E2E_BIN:/usr/bin:/bin" \
        PRODUCTION_ROOT="$PROJECT_ROOT" \
        SCRIPT_DIR="$E2E_ROOT" \
        SHOGUNATE_RUNTIME_DIR="$E2E_ROOT" \
        SHOGUNATE_ROLE_RESTART_COOLDOWN_SECONDS=0 \
        AGENT_ID=ashigaru1 \
        PANE_TARGET="$RUNTIME_PANE" \
        TMUX_REAL_BIN="$TMUX_REAL" \
        TMUX_SOCKET_NAME="$E2E_SOCKET" \
        TMUX_TMPDIR="$E2E_TMUX_TMP" \
        TERM=xterm-256color \
        __INBOX_WATCHER_TESTING__=1 \
        bash -c 'source "$PRODUCTION_ROOT/shogunate_mod/watcher/inbox_watcher.sh"; maintain_grok_runtime_failure_guard grok' \
        >"$log_file" 2>&1
}

assert_control_untouched() {
    [[ "$(control_tmux display-message -p -t "$CONTROL_PANE" '#{pane_id}')" == "$CONTROL_PANE" ]]
    [[ "$(control_tmux display-message -p -t "$CONTROL_PANE" '#{pane_pid}')" == "$CONTROL_PID" ]]
    [[ "$(control_tmux show-options -p -t "$CONTROL_PANE" -v @gb005_sentinel)" == "unchanged" ]]
}

runtime_server_gone() {
    ! main_tmux has-session -t runtime >/dev/null 2>&1
}

control_server_gone() {
    ! control_tmux has-session -t preexisting >/dev/null 2>&1
}

assert_model_argv_blocks() {
    python3 - "$ARGV_LOG" "$1" <<'PY'
import sys

path, expected_count = sys.argv[1], int(sys.argv[2])
blocks = []
current = []
for line in open(path, encoding="utf-8"):
    line = line.rstrip("\n")
    if line == "end":
        blocks.append(current)
        current = []
    else:
        current.append(line)
assert len(blocks) == expected_count, blocks
for block in blocks:
    assert "argc=2" in block, block
    assert "arg1=--model" in block, block
    assert "arg2=grok-4.5" in block, block
    assert not any("--model=" in line for line in block), block
PY
}

advance_to_fallback() {
    local auth_log="$1"
    wait_for 100 invocation_count_is 2
    wait_for 100 pane_has_text "You are not authenticated."
    role_state_is 2 primary process_exit 1
    run_guard "$auth_log"
    wait_for 100 invocation_count_is 3
    wait_for 100 pane_has_text "Rate limit exceeded. Retry later."
    role_state_is 3 fallback auth_error 0
}

@test "fake Grok startup forwards model argv, process exit restarts Primary once, then auth activates Fallback" {
    local auth_log="$E2E_ROOT/auth-guard.log"

    advance_to_fallback "$auth_log"
    assert_model_argv_blocks 3

    auth_marker="$E2E_ROOT/queue/runtime/runtime_blocked_relay/ashigaru1__grok-auth_error-generation2.sent"
    [[ -f "$auth_marker" ]]
    [[ ! -s "$auth_marker" ]]
    grep -Fq "grok auth_error classified for ashigaru1 (generation 2)" "$auth_log"
    ! grep -Fq "You are not authenticated." "$auth_log"
    ! grep -Fq "You are not authenticated." "$STATE"
    assert_control_untouched
}

@test "rate-limit guard stores only fixed reason and empty generation marker on the isolated server" {
    local auth_log="$E2E_ROOT/auth-guard.log"
    local rate_log="$E2E_ROOT/rate-guard.log"
    local rate_marker

    advance_to_fallback "$auth_log"
    run_guard "$rate_log"
    wait_for 100 role_state_is 4 fallback rate_limit 0

    rate_marker="$E2E_ROOT/queue/runtime/runtime_blocked_relay/ashigaru1__grok-rate_limit-generation3.sent"
    [[ -f "$rate_marker" ]]
    [[ ! -s "$rate_marker" ]]
    grep -Fq "grok rate_limit classified for ashigaru1 (generation 3)" "$rate_log"
    ! grep -Fq "Rate limit exceeded. Retry later." "$rate_log"
    ! grep -Fq "Rate limit exceeded. Retry later." "$STATE"
    ! grep -Fq "You are not authenticated." "$STATE"
    assert_model_argv_blocks 3
    assert_control_untouched
}
