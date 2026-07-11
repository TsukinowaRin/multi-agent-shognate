#!/usr/bin/env bats

setup_file() {
    local search_dir
    search_dir="$(cd "$(dirname "$BATS_TEST_FILENAME")" && pwd)"
    while [ "$search_dir" != "/" ]; do
        if [ -f "$search_dir/shogunate_mod/manifest.yaml" ]; then
            export PROJECT_ROOT="$search_dir"
            break
        fi
        search_dir="$(dirname "$search_dir")"
    done
    [ -n "${PROJECT_ROOT:-}" ] || return 1
    [ -f "$PROJECT_ROOT/shogunate_mod/app/reply.sh" ] || return 1
    command -v python3 >/dev/null 2>&1 || return 1
}

setup() {
    export TEST_TMPDIR="$(mktemp -d "$BATS_TMPDIR/app_reply_test.XXXXXX")"
    mkdir -p "$TEST_TMPDIR/shogunate_mod/app"
    cp "$PROJECT_ROOT/shogunate_mod/app/reply.sh" "$TEST_TMPDIR/shogunate_mod/app/reply.sh"
    chmod +x "$TEST_TMPDIR/shogunate_mod/app/reply.sh"
    export TEST_REPLY="$TEST_TMPDIR/shogunate_mod/app/reply.sh"
}

teardown() {
    [ -n "$TEST_TMPDIR" ] && [ -d "$TEST_TMPDIR" ] && rm -rf "$TEST_TMPDIR"
}

make_session() {
    mkdir -p "$TEST_TMPDIR/queue/app/sessions/$1"
}

@test "reply.sh appends role_message transcript entry" {
    make_session "chat-001"

    run bash "$TEST_REPLY" "chat-001" "ashigaru1" "承知つかまつった"
    [ "$status" -eq 0 ]

    python3 - "$TEST_TMPDIR/queue/app/sessions/chat-001/messages.jsonl" <<'PY'
import json
import sys

path = sys.argv[1]
lines = open(path, encoding="utf-8").read().splitlines()
assert len(lines) == 1
entry = json.loads(lines[0])
assert entry["id"].startswith("msg-")
assert entry["from"] == "ashigaru1"
assert entry["to"] == "lord"
assert entry["type"] == "role_message"
assert entry["content"] == "承知つかまつった"
assert "T" in entry["time"]
PY
}

@test "reply.sh safely encodes quotes newlines and Japanese" {
    make_session "chat-escape"
    reply_text=$'引用 "quote"\n次の行: 日本語'

    run bash "$TEST_REPLY" "chat-escape" "karo" "$reply_text"
    [ "$status" -eq 0 ]

    REPLY_TEXT="$reply_text" python3 - "$TEST_TMPDIR/queue/app/sessions/chat-escape/messages.jsonl" <<'PY'
import json
import os
import sys

entry = json.loads(open(sys.argv[1], encoding="utf-8").read())
assert entry["content"] == os.environ["REPLY_TEXT"]
PY
}

@test "reply.sh exits 1 when session does not exist" {
    run bash "$TEST_REPLY" "missing-session" "shogun" "返答"
    [ "$status" -eq 1 ]
    [[ "$output" =~ "app session not found" ]]
}

@test "reply.sh supports custom --type option" {
    make_session "chat-status"

    run bash "$TEST_REPLY" --type "status_notice" "chat-status" "gunkan" "検査中"
    [ "$status" -eq 0 ]

    python3 - "$TEST_TMPDIR/queue/app/sessions/chat-status/messages.jsonl" <<'PY'
import json
import sys

entry = json.loads(open(sys.argv[1], encoding="utf-8").read())
assert entry["type"] == "status_notice"
assert entry["from"] == "gunkan"
assert entry["to"] == "lord"
assert entry["content"] == "検査中"
PY
}
