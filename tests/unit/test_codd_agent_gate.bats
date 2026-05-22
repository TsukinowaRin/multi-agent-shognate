#!/usr/bin/env bats

setup() {
    PROJECT_ROOT="$(cd "$(dirname "$BATS_TEST_FILENAME")/../.." && pwd)"
    TEST_TMP="$(mktemp -d)"
    REPORT_DIR="$TEST_TMP/reports"
    LOG_DIR="$TEST_TMP/logs"
    RUNNER="$TEST_TMP/fake_codd_runner.sh"
}

teardown() {
    rm -rf "$TEST_TMP"
}

write_runner() {
    local exit_code="$1"
    cat > "$RUNNER" <<SH
#!/usr/bin/env bash
echo "fake codd \$1 output"
exit ${exit_code}
SH
    chmod +x "$RUNNER"
}

@test "agent_codd_gate: writes pass report and log" {
    write_runner 0

    run env CODD_AGENT_REPORT_DIR="$REPORT_DIR" CODD_AGENT_LOG_DIR="$LOG_DIR" CODD_AGENT_RUNNER="$RUNNER" \
        bash "$PROJECT_ROOT/scripts/agent_codd_gate.sh" ashigaru1 subtask_001 verify

    [ "$status" -eq 0 ]
    [ -f "$REPORT_DIR/ashigaru1_subtask_001_verify.yaml" ]
    [ -f "$LOG_DIR/ashigaru1_subtask_001_verify.log" ]
    grep -q 'agent_id: "ashigaru1"' "$REPORT_DIR/ashigaru1_subtask_001_verify.yaml"
    grep -q 'task_id: "subtask_001"' "$REPORT_DIR/ashigaru1_subtask_001_verify.yaml"
    grep -q 'status: "pass"' "$REPORT_DIR/ashigaru1_subtask_001_verify.yaml"
    grep -q 'codd_command: "verify"' "$REPORT_DIR/ashigaru1_subtask_001_verify.yaml"
    grep -q 'fake codd verify output' "$LOG_DIR/ashigaru1_subtask_001_verify.log"
}

@test "agent_codd_gate: failure still writes failed report" {
    write_runner 7

    run env CODD_AGENT_REPORT_DIR="$REPORT_DIR" CODD_AGENT_LOG_DIR="$LOG_DIR" CODD_AGENT_RUNNER="$RUNNER" \
        bash "$PROJECT_ROOT/scripts/agent_codd_gate.sh" karo cmd_123 verify

    [ "$status" -eq 7 ]
    [ -f "$REPORT_DIR/karo_cmd_123_verify.yaml" ]
    grep -q 'status: "failed"' "$REPORT_DIR/karo_cmd_123_verify.yaml"
    grep -q 'exit_code: 7' "$REPORT_DIR/karo_cmd_123_verify.yaml"
}

@test "agent_codd_gate: rejects invalid ids and commands" {
    write_runner 0

    run env CODD_AGENT_RUNNER="$RUNNER" bash "$PROJECT_ROOT/scripts/agent_codd_gate.sh" "../bad" subtask_001 verify
    [ "$status" -eq 2 ]

    run env CODD_AGENT_RUNNER="$RUNNER" bash "$PROJECT_ROOT/scripts/agent_codd_gate.sh" ashigaru1 subtask_001 badcmd
    [ "$status" -eq 2 ]
}
