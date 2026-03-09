#!/usr/bin/env bats

setup() {
    TEST_TMP="$(mktemp -d)"
    PROJECT_ROOT="$(cd "$(dirname "$BATS_TEST_FILENAME")/../.." && pwd)"
    mkdir -p "$TEST_TMP/queue/runtime"
}

teardown() {
    rm -rf "$TEST_TMP"
}

@test "interactive_agent_runner: codex update skip 後に ready を待って bootstrap を送る" {
    run python3 - <<'PY'
import pty
pty.openpty()
PY
    if [ "$status" -ne 0 ]; then
        skip "pty が確保できない環境"
    fi

    cat > "$TEST_TMP/mock_codex.sh" <<'SH'
#!/usr/bin/env bash
set -euo pipefail
printf 'Update available\n'
printf '1. Update now\n'
printf '2. Skip\n'
printf 'Press enter to continue\n'
IFS= read -r choice
printf 'choice:%s\n' "$choice"
printf '>_ OpenAI Codex\n'
printf '? for shortcuts\n'
IFS= read -r prompt
printf 'prompt:%s\n' "$prompt"
SH
    chmod +x "$TEST_TMP/mock_codex.sh"

    cat > "$TEST_TMP/queue/runtime/bootstrap.txt" <<'TXT'
【初動命令】ready:karo
TXT

    run python3 "$PROJECT_ROOT/scripts/interactive_agent_runner.py" \
        --root "$TEST_TMP" \
        --agent "karo" \
        --cli "codex" \
        --command "$TEST_TMP/mock_codex.sh" \
        --transcript "$TEST_TMP/queue/runtime/transcript.log" \
        --meta "$TEST_TMP/queue/runtime/meta.log" \
        --bootstrap "$TEST_TMP/queue/runtime/bootstrap.txt"

    [ "$status" -eq 0 ]
    run rg -nF 'choice:2' "$TEST_TMP/queue/runtime/transcript.log"
    [ "$status" -eq 0 ]
    run rg -nF 'prompt:【初動命令】ready:karo' "$TEST_TMP/queue/runtime/transcript.log"
    [ "$status" -eq 0 ]
    run rg -n 'codex update skipped agent=karo|bootstrap delivered agent=karo cli=codex' "$TEST_TMP/queue/runtime/meta.log"
    [ "$status" -eq 0 ]
}
