#!/usr/bin/env bats

setup_file() {
    export PROJECT_ROOT
    PROJECT_ROOT="$(cd "$(dirname "$BATS_TEST_FILENAME")/.." && pwd)"

    [ -f "$PROJECT_ROOT/shogunate_mod/inbox/write.sh" ] || return 1
    [ -f "$PROJECT_ROOT/shogunate_mod/transport/agmsg_bridge.sh" ] || return 1
    [ -f "$PROJECT_ROOT/tests/helpers/agmsg_send_stub.bash" ] || return 1
    python3 -c "import yaml" 2>/dev/null || return 1
}

setup() {
    export TEST_ROOT="$BATS_TEST_TMPDIR/repo"
    export AGMSG_SKILL_DIR="$TEST_ROOT/agmsg-skill"
    export AGMSG_CALL_LOG="$TEST_ROOT/agmsg-calls.tsv"
    unset AGMSG_STUB_EXIT_CODE

    mkdir -p \
        "$TEST_ROOT/config" \
        "$TEST_ROOT/queue/inbox" \
        "$TEST_ROOT/shogunate_mod/inbox" \
        "$TEST_ROOT/shogunate_mod/transport" \
        "$AGMSG_SKILL_DIR/scripts"

    cp "$PROJECT_ROOT/shogunate_mod/inbox/write.sh" \
        "$TEST_ROOT/shogunate_mod/inbox/write.sh"
    cp "$PROJECT_ROOT/shogunate_mod/transport/agmsg_bridge.sh" \
        "$TEST_ROOT/shogunate_mod/transport/agmsg_bridge.sh"
    cp "$PROJECT_ROOT/tests/helpers/agmsg_send_stub.bash" \
        "$AGMSG_SKILL_DIR/scripts/send.sh"
    : > "$AGMSG_CALL_LOG"
}

write_message() {
    local target="$1"
    run env \
        AGMSG_SKILL_DIR="$AGMSG_SKILL_DIR" \
        AGMSG_CALL_LOG="$AGMSG_CALL_LOG" \
        AGMSG_STUB_EXIT_CODE="${AGMSG_STUB_EXIT_CODE:-0}" \
        bash "$TEST_ROOT/shogunate_mod/inbox/write.sh" \
        "$target" "bridge test for $target" task_assigned shogun
}

assert_yaml_message() {
    local target="$1"
    python3 - "$TEST_ROOT/queue/inbox/${target}.yaml" "$target" <<'PY'
import sys

import yaml

path, target = sys.argv[1:]
with open(path, encoding="utf-8") as stream:
    data = yaml.safe_load(stream) or {}

messages = data.get("messages") or []
assert len(messages) == 1, messages
message = messages[0]
assert message["from"] == "shogun", message
assert message["type"] == "task_assigned", message
assert message["content"] == f"bridge test for {target}", message
assert message["read"] is False, message
PY
}

@test "mode missing disables agmsg and write.sh leaves the stub log empty" {
    cat > "$TEST_ROOT/config/settings.yaml" <<'YAML'
language: ja
YAML

    run bash -c \
        'source "$1"; agmsg_bridge_enabled ashigaru1' \
        _ "$TEST_ROOT/shogunate_mod/transport/agmsg_bridge.sh"
    [ "$status" -ne 0 ]

    write_message ashigaru1
    [ "$status" -eq 0 ]
    [ ! -s "$AGMSG_CALL_LOG" ]
    assert_yaml_message ashigaru1
}

@test "mode yaml sends only to agents listed in bridge_agents" {
    cat > "$TEST_ROOT/config/settings.yaml" <<'YAML'
transport:
  mode: yaml
  agmsg:
    team: shogunate
    skill_dir: ""
    bridge_agents:
      - ashigaru1
YAML

    write_message ashigaru1
    [ "$status" -eq 0 ]
    write_message karo
    [ "$status" -eq 0 ]

    [ "$(wc -l < "$AGMSG_CALL_LOG")" -eq 1 ]
    [ "$(cut -f3 "$AGMSG_CALL_LOG")" = "ashigaru1" ]
    grep -Fq \
        '[shogunate] inbox: unread message(s) waiting. Read queue/inbox/ashigaru1.yaml and process type=task_assigned from shogun.' \
        "$AGMSG_CALL_LOG"
    assert_yaml_message ashigaru1
    assert_yaml_message karo
}

@test "mode both sends every wake-up signal and preserves unread YAML messages" {
    cat > "$TEST_ROOT/config/settings.yaml" <<'YAML'
transport:
  mode: both
  agmsg:
    team: shogunate
    skill_dir: ""
    bridge_agents: []
YAML

    write_message ashigaru1
    [ "$status" -eq 0 ]
    write_message karo
    [ "$status" -eq 0 ]

    [ "$(wc -l < "$AGMSG_CALL_LOG")" -eq 2 ]
    grep -Eq $'^shogunate\tshogun\tashigaru1\t' "$AGMSG_CALL_LOG"
    grep -Eq $'^shogunate\tshogun\tkaro\t' "$AGMSG_CALL_LOG"
    assert_yaml_message ashigaru1
    assert_yaml_message karo
}

@test "mode agmsg sends a wake-up signal and still writes durable YAML" {
    cat > "$TEST_ROOT/config/settings.yaml" <<'YAML'
transport:
  mode: agmsg
  agmsg:
    team: shogunate
    skill_dir: ""
    bridge_agents: []
YAML

    write_message ashigaru1
    [ "$status" -eq 0 ]

    [ "$(wc -l < "$AGMSG_CALL_LOG")" -eq 1 ]
    [ "$(cut -f3 "$AGMSG_CALL_LOG")" = "ashigaru1" ]
    assert_yaml_message ashigaru1
}

@test "agmsg send failure is fail-open and leaves the YAML message unread" {
    cat > "$TEST_ROOT/config/settings.yaml" <<'YAML'
transport:
  mode: agmsg
  agmsg:
    team: shogunate
    skill_dir: ""
    bridge_agents: []
YAML
    export AGMSG_STUB_EXIT_CODE=1

    write_message ashigaru1
    [ "$status" -eq 0 ]

    [ "$(wc -l < "$AGMSG_CALL_LOG")" -eq 1 ]
    assert_yaml_message ashigaru1
}
