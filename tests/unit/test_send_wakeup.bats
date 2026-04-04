#!/usr/bin/env bats
# test_send_wakeup.bats — send_wakeup() unit tests
# Sources the REAL inbox_watcher.sh with __INBOX_WATCHER_TESTING__=1
# to test actual production functions with mocked externals (tmux, pgrep, etc).
#
# テスト構成:
#   T-SW-001: send_wakeup — active self-watch → skip nudge
#   T-SW-002: send_wakeup — no self-watch → tmux send-keys
#   T-SW-003: send_wakeup — send-keys content is "inboxN" + Enter (separated)
#   T-SW-004: send_wakeup — send-keys failure → return 1
#   T-SW-005: send_wakeup — no paste-buffer or set-buffer used
#   T-SW-006: agent_has_self_watch — detects inotifywait process
#   T-SW-006b: agent_has_self_watch — queries exact INBOX path
#   T-SW-007: agent_has_self_watch — no inotifywait → returns 1
#   T-SW-008: send_cli_command — /clear uses send-keys
#   T-SW-009: send_cli_command — /model uses send-keys
#   T-SW-010: nudge content format — inboxN (backward compatible)
#   T-SW-011: inbox_watcher.sh uses send-keys, functions exist
#   T-ESC-001: escalation — no unread → FIRST_UNREAD_SEEN stays 0
#   T-ESC-002: escalation — unread < 2min → standard nudge
#   T-ESC-003: escalation — unread 2-4min → Escape+nudge
#   T-ESC-004: escalation — unread > 4min → /clear sent
#   T-ESC-005: escalation — /clear cooldown → falls back to Escape+nudge
#   T-BUSY-001: agent_is_busy — detects "Working" in pane
#   T-BUSY-002: agent_is_busy — idle pane returns 1
#   T-BUSY-003: send_wakeup — skips when agent is busy
#   T-BUSY-004: send_wakeup_with_escape — skips when agent is busy
#   T-CODEX-001: send_cli_command — codex /clear → /new conversion
#   T-CODEX-002: send_cli_command — codex /model → skip
#   T-CODEX-003: C-u sent when unread=0 and agent is idle
#   T-CODEX-004: C-u NOT sent when agent is busy
#   T-CODEX-005: send_cli_command — claude /clear passes through as-is
#   T-CODEX-006: inbox_watcher.sh has agent_is_busy and Codex/Copilot handlers
#   T-CODEX-007: pane @agent_cli=codex overrides stale CLI_TYPE (Phase2 C-c抑止)
#   T-CODEX-008: pane @agent_cli=codex overrides stale CLI_TYPE (/clear→/new)
#   T-CODEX-009: normalize_special_command rejects invalid model_switch payload
#   T-CODEX-010: unresolved CLI type falls back to codex-safe path
#   T-CODEX-010b2: rate-limit prompt dismiss failure aborts send_wakeup
#   T-CODEX-010c2: rate-limit prompt dismiss failure aborts send_wakeup_with_escape
#   T-CODEX-011: clear_command処理でauto-recovery task_assignedを自動投入
#   T-CODEX-012: auto-recovery task_assignedは重複投入しない
#   T-COPILOT-001: send_cli_command — copilot /clear → Ctrl-C + restart
#   T-COPILOT-002: send_cli_command — copilot /model → skip
#   T-EXTRA-CLI-001: is_valid_cli_type — opencode / kilo を受理
#   T-OPENCODE-001: send_cli_command — opencode /clear → Ctrl-C + restart
#   T-OPENCODE-002: send_cli_command — opencode /model → skip
#   T-KILO-001: send_cli_command — kilo /clear → Ctrl-C + restart
#   T-KILO-002: send_cli_command — kilo /model → skip

# --- セットアップ ---

setup_file() {
    export PROJECT_ROOT="$(cd "$(dirname "$BATS_TEST_FILENAME")/../.." && pwd)"
    export WATCHER_SCRIPT="$PROJECT_ROOT/scripts/inbox_watcher.sh"
    [ -f "$WATCHER_SCRIPT" ] || return 1
    python3 -c "import yaml" 2>/dev/null || return 1
}

setup() {
    export TEST_TMPDIR="$(mktemp -d "$BATS_TMPDIR/send_wakeup_test.XXXXXX")"

    # Log file for tmux mock calls (all tmux invocations recorded here)
    export MOCK_LOG="$TEST_TMPDIR/tmux_calls.log"
    > "$MOCK_LOG"

    # Create mock pgrep (default: no self-watch found)
    export MOCK_PGREP="$TEST_TMPDIR/mock_pgrep"
    cat > "$MOCK_PGREP" << 'MOCK'
#!/bin/bash
exit 1
MOCK
    chmod +x "$MOCK_PGREP"

    # Create test inbox directory
    export TEST_INBOX_DIR="$TEST_TMPDIR/queue/inbox"
    mkdir -p "$TEST_INBOX_DIR"

    # Default mock control variables
    export MOCK_CAPTURE_PANE=""
    export MOCK_SENDKEYS_RC=0
    export MOCK_SENDKEYS_TEXT_RC=""
    export MOCK_SENDKEYS_ENTER_RC=""
    export MOCK_PANE_CLI=""
    export MOCK_PANE_CURRENT_COMMAND="node"
    export MOCK_PGREP_LOG="$TEST_TMPDIR/pgrep_calls.log"
    > "$MOCK_PGREP_LOG"

    # Test harness: sets up mocks, then sources the REAL inbox_watcher.sh
    # __INBOX_WATCHER_TESTING__=1 skips arg parsing, inotifywait check, and main loop.
    # Only function definitions are loaded — testing actual production code.
    export TEST_HARNESS="$TEST_TMPDIR/test_harness.sh"
    cat > "$TEST_HARNESS" << HARNESS
#!/bin/bash
# Variables required by inbox_watcher.sh functions
AGENT_ID="test_agent"
PANE_TARGET="test:0.0"
CLI_TYPE="claude"
INBOX="$TEST_INBOX_DIR/test_agent.yaml"
LOCKFILE="\${INBOX}.lock"
SCRIPT_DIR="$PROJECT_ROOT"

# Mock external commands (defined before sourcing so they override real commands)
tmux() {
    echo "tmux \$*" >> "$MOCK_LOG"
    if echo "\$*" | grep -q "capture-pane"; then
        echo "\${MOCK_CAPTURE_PANE:-}"
        return 0
    fi
    if echo "\$*" | grep -q "send-keys"; then
        if echo "\$*" | grep -q " Enter"; then
            if [ -n "\${MOCK_SENDKEYS_ENTER_RC:-}" ]; then
                return "\${MOCK_SENDKEYS_ENTER_RC}"
            fi
        else
            if [ -n "\${MOCK_SENDKEYS_TEXT_RC:-}" ]; then
                return "\${MOCK_SENDKEYS_TEXT_RC}"
            fi
        fi
        return \${MOCK_SENDKEYS_RC:-0}
    fi
    if echo "\$*" | grep -q "show-options"; then
        echo "\${MOCK_PANE_CLI:-}"
        return 0
    fi
    if echo "\$*" | grep -q "display-message"; then
        if echo "\$*" | grep -q "pane_current_command"; then
            echo "\${MOCK_PANE_CURRENT_COMMAND:-node}"
        else
            echo "mock_pane"
        fi
        return 0
    fi
    return 0
}
timeout() { shift; "\$@"; }
pgrep() { "$MOCK_PGREP" "\$@"; }
sleep() { :; }
export -f tmux timeout pgrep sleep

# Source the REAL inbox_watcher.sh (testing guard skips startup & main loop)
export __INBOX_WATCHER_TESTING__=1
source "$WATCHER_SCRIPT"
HARNESS
    chmod +x "$TEST_HARNESS"
}

teardown() {
    rm -rf "$TEST_TMPDIR"
}

# --- T-SW-001: self-watch active → skip nudge ---

@test "T-SW-001: send_wakeup skips nudge when agent has active self-watch" {
    cat > "$MOCK_PGREP" << 'MOCK'
#!/bin/bash
echo "12345 inotifywait -q -t 120 -e modify inbox/test_agent.yaml"
exit 0
MOCK
    chmod +x "$MOCK_PGREP"

    run bash -c "source '$TEST_HARNESS' && send_wakeup 3"
    [ "$status" -eq 0 ]

    # No nudge send-keys should have occurred
    ! grep -q "send-keys.*inbox" "$MOCK_LOG"

    echo "$output" | grep -q "SKIP"
}

# --- T-SW-002: no self-watch → tmux send-keys ---

@test "T-SW-002: send_wakeup uses tmux send-keys when no self-watch" {
    run bash -c "source '$TEST_HARNESS' && send_wakeup 5"
    [ "$status" -eq 0 ]

    # Verify send-keys occurred with inbox5
    grep -q "send-keys.*inbox5" "$MOCK_LOG"
    # Verify Enter was sent (as separate call — Codex TUI compatibility)
    grep -q "send-keys.*Enter" "$MOCK_LOG"
}

# --- T-SW-003: send-keys content is "inboxN" + Enter (separated) ---

@test "T-SW-003: send-keys sends inboxN and Enter as separate calls" {
    run bash -c "source '$TEST_HARNESS' && send_wakeup 3"
    [ "$status" -eq 0 ]

    # Text and Enter are sent as separate send-keys calls (Codex TUI compatibility)
    grep -q "send-keys -t test:0.0 inbox3" "$MOCK_LOG"
    grep -q "send-keys -t test:0.0 Enter" "$MOCK_LOG"
}

# --- T-SW-004: send-keys failure → return 1 ---

@test "T-SW-004: send_wakeup returns 1 when send-keys fails" {
    run bash -c "MOCK_SENDKEYS_RC=1; source '$TEST_HARNESS' && send_wakeup 2"
    [ "$status" -eq 1 ]

    echo "$output" | grep -qi "WARNING\|failed"
}

@test "T-SW-004b: send_wakeup returns 1 when Enter send fails" {
    run bash -c "MOCK_SENDKEYS_ENTER_RC=1; source '$TEST_HARNESS' && send_wakeup 2"
    [ "$status" -eq 1 ]

    echo "$output" | grep -qi "Enter failed\|WARNING"
}

# --- T-SW-005: no paste-buffer or set-buffer used ---

@test "T-SW-005: nudge delivery does NOT use paste-buffer or set-buffer" {
    run bash -c "source '$TEST_HARNESS' && send_wakeup 3"
    [ "$status" -eq 0 ]

    # These should never be used
    ! grep -q "paste-buffer" "$MOCK_LOG"
    ! grep -q "set-buffer" "$MOCK_LOG"

    # send-keys IS expected
    grep -q "send-keys" "$MOCK_LOG"
}

# --- T-SW-006: agent_has_self_watch — detects inotifywait ---

@test "T-SW-006: agent_has_self_watch returns 0 when inotifywait running" {
    cat > "$MOCK_PGREP" << 'MOCK'
#!/bin/bash
echo "99999 inotifywait -q -t 120 -e modify inbox/test_agent.yaml"
exit 0
MOCK
    chmod +x "$MOCK_PGREP"

    run bash -c "source '$TEST_HARNESS' && agent_has_self_watch"
    [ "$status" -eq 0 ]
}

@test "T-SW-006b: agent_has_self_watch queries exact INBOX path" {
    run grep -nE 'escape_extended_regex|inbox_path=.*INBOX|pgrep -f "inotifywait\.\*\$\{inbox_pattern\}"' "$WATCHER_SCRIPT"
    [ "$status" -eq 0 ]
}

# --- T-SW-007: agent_has_self_watch — no inotifywait ---

@test "T-SW-007: agent_has_self_watch returns 1 when no inotifywait" {
    run bash -c "source '$TEST_HARNESS' && agent_has_self_watch"
    [ "$status" -eq 1 ]
}

# --- T-SW-007b: non-claudeはself-watch判定を使わない ---

@test "T-SW-007b: non-claude CLI ignores self-watch process and still nudges" {
    cat > "$MOCK_PGREP" << 'MOCK'
#!/bin/bash
echo "88888 inotifywait -q -t 120 -e modify inbox/test_agent.yaml"
exit 0
MOCK
    chmod +x "$MOCK_PGREP"

    run bash -c "MOCK_PANE_CLI=codex; source '$TEST_HARNESS' && send_wakeup 4"
    [ "$status" -eq 0 ]
    grep -q "send-keys.*inbox4" "$MOCK_LOG"
}

@test "T-EXTRA-CLI-001: is_valid_cli_type accepts opencode and kilo" {
    run bash -c "source '$TEST_HARNESS' && is_valid_cli_type opencode && is_valid_cli_type kilo"
    [ "$status" -eq 0 ]
}

# --- T-SW-008: /clear uses send-keys ---

@test "T-SW-008: send_cli_command /clear uses tmux send-keys" {
    run bash -c "source '$TEST_HARNESS' && send_cli_command /clear"
    [ "$status" -eq 0 ]

    # Verify send-keys was used with /clear
    grep -q "send-keys.*/clear" "$MOCK_LOG"
    # C-c was sent first (stale input clearing)
    grep -q "send-keys.*C-c" "$MOCK_LOG"
    # Enter was sent after /clear
    grep -q "send-keys.*Enter" "$MOCK_LOG"
}

# --- T-SW-009: /model uses send-keys ---

@test "T-SW-009: send_cli_command /model uses tmux send-keys" {
    run bash -c "source '$TEST_HARNESS' && send_cli_command '/model opus'"
    [ "$status" -eq 0 ]

    grep -q "send-keys.*/model opus" "$MOCK_LOG"
    grep -q "send-keys.*Enter" "$MOCK_LOG"
}

@test "T-SW-009b: send_cli_command returns 1 when Enter send fails" {
    run bash -c "MOCK_SENDKEYS_ENTER_RC=1; source '$TEST_HARNESS' && send_cli_command '/model opus'"
    [ "$status" -eq 1 ]

    echo "$output" | grep -qi "Enter failed\|WARNING"
}

# --- T-SW-010: nudge content format ---

@test "T-SW-010: nudge content format is inboxN (backward compatible)" {
    run bash -c "source '$TEST_HARNESS' && send_wakeup 7"
    [ "$status" -eq 0 ]

    grep -q "send-keys.*inbox7" "$MOCK_LOG"
}

@test "T-SW-010b: shogun cmd_done unread uses explicit wake-up text" {
    cat > "$TEST_INBOX_DIR/test_agent.yaml" <<'YAML'
messages:
  - id: msg_1
    from: karo
    type: cmd_done
    content: "cmd_200 が完了した。"
    read: false
YAML

    run bash -c '
        source "'"$TEST_HARNESS"'"
        AGENT_ID="shogun"
        send_wakeup 1
    '
    [ "$status" -eq 0 ]

    grep -q "queue/inbox/shogun.yaml に未読の cmd_done がある。dashboard.md を確認し、殿へ完了報告せよ。" "$MOCK_LOG"
    ! grep -q "send-keys.*inbox1" "$MOCK_LOG"
}

# --- T-SW-011: functions exist in inbox_watcher.sh ---

@test "T-SW-011: inbox_watcher.sh uses send-keys with required functions" {
    grep -q "send_wakeup()" "$WATCHER_SCRIPT"
    grep -q "agent_has_self_watch" "$WATCHER_SCRIPT"
    grep -q "send_wakeup_with_escape()" "$WATCHER_SCRIPT"
    grep -q "send_cli_command()" "$WATCHER_SCRIPT"

    # send-keys IS used in executable code
    local executable_lines
    executable_lines=$(grep -v '^\s*#' "$WATCHER_SCRIPT")
    echo "$executable_lines" | grep -q "send-keys"

    # paste-buffer and set-buffer are NOT used
    ! echo "$executable_lines" | grep -q "paste-buffer"
    ! echo "$executable_lines" | grep -q "set-buffer"
}

# --- T-ESC-001: no unread → FIRST_UNREAD_SEEN stays 0 ---

@test "T-ESC-001: escalation state resets when no unread messages" {
    run bash -c '
        source "'"$TEST_HARNESS"'"
        FIRST_UNREAD_SEEN=12345
        # Simulate no unread
        normal_count=0
        if [ "$normal_count" -gt 0 ] 2>/dev/null; then
            echo "SHOULD_NOT_REACH"
        else
            FIRST_UNREAD_SEEN=0
        fi
        echo "FIRST_UNREAD_SEEN=$FIRST_UNREAD_SEEN"
    '
    [ "$status" -eq 0 ]
    echo "$output" | grep -q "FIRST_UNREAD_SEEN=0"
}

# --- T-ESC-002: unread < 2min → standard nudge ---

@test "T-ESC-002: escalation Phase 1 — unread under 2min uses standard nudge" {
    run bash -c '
        source "'"$TEST_HARNESS"'"
        now=$(date +%s)
        FIRST_UNREAD_SEEN=$((now - 30))  # 30 seconds ago
        age=$((now - FIRST_UNREAD_SEEN))
        if [ "$age" -lt "$ESCALATE_PHASE1" ]; then
            send_wakeup 2
            echo "PHASE1_NUDGE"
        fi
    '
    [ "$status" -eq 0 ]
    echo "$output" | grep -q "PHASE1_NUDGE"
    grep -q "send-keys.*inbox2" "$MOCK_LOG"
    # No Escape-based nudge
    ! grep -q "send-keys.*Escape" "$MOCK_LOG"
}

# --- T-ESC-003: unread 2-4min → Escape+nudge ---

@test "T-ESC-003: escalation Phase 2 — unread 2-4min uses Escape+nudge" {
    run bash -c '
        MOCK_PANE_CLI=codex
        source "'"$TEST_HARNESS"'"
        now=$(date +%s)
        FIRST_UNREAD_SEEN=$((now - 180))  # 3 minutes ago
        age=$((now - FIRST_UNREAD_SEEN))
        if [ "$age" -ge "$ESCALATE_PHASE1" ] && [ "$age" -lt "$ESCALATE_PHASE2" ]; then
            send_wakeup_with_escape 3
            echo "PHASE2_ESCAPE_NUDGE"
        fi
    '
    [ "$status" -eq 0 ]
    echo "$output" | grep -q "PHASE2_ESCAPE_NUDGE"
    # Escape was sent
    grep -q "send-keys.*Escape" "$MOCK_LOG"
    # Nudge was also sent
    grep -q "send-keys.*inbox3" "$MOCK_LOG"
}

@test "T-ESC-003c: shogun cmd_done unread uses explicit wake-up text in phase2" {
    cat > "$TEST_INBOX_DIR/test_agent.yaml" <<'YAML'
messages:
  - id: msg_1
    from: karo
    type: cmd_done
    content: "cmd_200 が完了した。"
    read: false
YAML

    run bash -c '
        MOCK_PANE_CLI=codex
        source "'"$TEST_HARNESS"'"
        AGENT_ID="shogun"
        send_wakeup_with_escape 1
    '
    [ "$status" -eq 0 ]
    grep -q "send-keys.*Escape" "$MOCK_LOG"
    grep -q "queue/inbox/shogun.yaml に未読の cmd_done がある。dashboard.md を確認し、殿へ完了報告せよ。" "$MOCK_LOG"
    ! grep -q "send-keys.*inbox1" "$MOCK_LOG"
}

@test "T-ESC-003b: claudeはPhase2でEscapeを送らず通常nudgeにフォールバック" {
    run bash -c '
        MOCK_PANE_CLI=claude
        source "'"$TEST_HARNESS"'"
        send_wakeup_with_escape 6
    '
    [ "$status" -eq 0 ]
    ! grep -q "send-keys.*Escape" "$MOCK_LOG"
    grep -q "send-keys.*inbox6" "$MOCK_LOG"
}

# --- T-ESC-004: unread > 4min → /clear sent ---

@test "T-ESC-004: escalation Phase 3 — unread over 4min sends /clear" {
    run bash -c '
        source "'"$TEST_HARNESS"'"
        now=$(date +%s)
        FIRST_UNREAD_SEEN=$((now - 300))  # 5 minutes ago
        LAST_CLEAR_TS=0  # no recent /clear
        age=$((now - FIRST_UNREAD_SEEN))
        if [ "$age" -ge "$ESCALATE_PHASE2" ] && [ "$LAST_CLEAR_TS" -lt "$((now - ESCALATE_COOLDOWN))" ]; then
            send_cli_command "/clear"
            echo "PHASE3_CLEAR"
        fi
    '
    [ "$status" -eq 0 ]
    echo "$output" | grep -q "PHASE3_CLEAR"
    grep -q "send-keys.*/clear" "$MOCK_LOG"
}

# --- T-ESC-005: /clear cooldown → falls back to Escape+nudge ---

@test "T-ESC-005: escalation /clear cooldown — falls back to Escape+nudge" {
    run bash -c '
        MOCK_PANE_CLI=codex
        source "'"$TEST_HARNESS"'"
        now=$(date +%s)
        FIRST_UNREAD_SEEN=$((now - 300))  # 5 minutes ago
        LAST_CLEAR_TS=$((now - 60))  # /clear sent 1 min ago (within 5min cooldown)
        age=$((now - FIRST_UNREAD_SEEN))
        if [ "$age" -ge "$ESCALATE_PHASE2" ] && [ "$LAST_CLEAR_TS" -ge "$((now - ESCALATE_COOLDOWN))" ]; then
            send_wakeup_with_escape 4
            echo "COOLDOWN_FALLBACK"
        fi
    '
    [ "$status" -eq 0 ]
    echo "$output" | grep -q "COOLDOWN_FALLBACK"
    grep -q "send-keys.*Escape" "$MOCK_LOG"
    grep -q "send-keys.*inbox4" "$MOCK_LOG"
    ! grep -q "send-keys.*/clear" "$MOCK_LOG"
}

# --- T-BUSY-001: agent_is_busy detects "Working" ---

@test "T-BUSY-001: agent_is_busy returns 0 when pane shows Working" {
    run bash -c '
        MOCK_CAPTURE_PANE="◦ Working on task (12s • esc to interrupt)"
        source "'"$TEST_HARNESS"'"
        agent_is_busy
    '
    [ "$status" -eq 0 ]
}

# --- T-BUSY-002: agent_is_busy returns 1 when idle ---

@test "T-BUSY-002: agent_is_busy returns 1 when pane is idle" {
    run bash -c '
        MOCK_CAPTURE_PANE="› Summarize recent commits
  ? for shortcuts                100% context left"
        source "'"$TEST_HARNESS"'"
        agent_is_busy
    '
    [ "$status" -eq 1 ]
}

# --- T-BUSY-003: send_wakeup skips when agent is busy ---

@test "T-BUSY-003: send_wakeup skips nudge when agent is busy" {
    run bash -c '
        MOCK_CAPTURE_PANE="◦ Thinking about approach (5s • esc to interrupt)"
        source "'"$TEST_HARNESS"'"
        send_wakeup 3
    '
    [ "$status" -eq 0 ]
    echo "$output" | grep -qi "SKIP.*busy"

    # No nudge should have been sent
    ! grep -q "send-keys.*inbox" "$MOCK_LOG"
}

# --- T-BUSY-004: send_wakeup_with_escape skips when agent is busy ---

@test "T-BUSY-004: send_wakeup_with_escape skips when agent is busy" {
    run bash -c '
        MOCK_CAPTURE_PANE="◦ Sending request (2s • esc to interrupt)"
        source "'"$TEST_HARNESS"'"
        send_wakeup_with_escape 2
    '
    [ "$status" -eq 0 ]
    echo "$output" | grep -qi "SKIP.*busy"

    # No nudge should have been sent
    ! grep -q "send-keys.*inbox" "$MOCK_LOG"
}

# --- T-CODEX-001: codex /clear → /new conversion ---

@test "T-CODEX-001: send_cli_command converts /clear to /new for codex" {
    run bash -c '
        source "'"$TEST_HARNESS"'"
        CLI_TYPE="codex"
        send_cli_command "/clear"
    '
    [ "$status" -eq 0 ]

    # Should send /new, NOT /clear
    grep -q "send-keys.*/new" "$MOCK_LOG"
    ! grep -q "send-keys.*/clear" "$MOCK_LOG"
}

# --- T-CODEX-002: codex /model → skip ---

@test "T-CODEX-002: send_cli_command skips /model for codex" {
    run bash -c '
        source "'"$TEST_HARNESS"'"
        CLI_TYPE="codex"
        send_cli_command "/model opus"
    '
    [ "$status" -eq 0 ]

    # No tmux send-keys for /model
    ! grep -q "send-keys.*/model" "$MOCK_LOG"

    # Stderr indicates skip
    echo "$output" | grep -q "not supported on codex"
}

# --- T-CODEX-003: C-u sent when unread=0 and agent is idle ---

@test "T-CODEX-003: C-u cleanup sent when no unread and agent is idle" {
    run bash -c '
        MOCK_CAPTURE_PANE="› Summarize recent commits
  ? for shortcuts                100% context left"
        source "'"$TEST_HARNESS"'"
        # Simulate process_unread no-unread path
        FIRST_UNREAD_SEEN=12345
        normal_count=0
        if [ "$normal_count" -gt 0 ] 2>/dev/null; then
            echo "SHOULD_NOT_REACH"
        else
            FIRST_UNREAD_SEEN=0
            if ! agent_is_busy; then
                timeout 2 tmux send-keys -t "$PANE_TARGET" C-u 2>/dev/null
                echo "C_U_SENT"
            fi
        fi
    '
    [ "$status" -eq 0 ]
    echo "$output" | grep -q "C_U_SENT"
    grep -q "send-keys.*C-u" "$MOCK_LOG"
}

# --- T-CODEX-004: C-u NOT sent when agent is busy ---

@test "T-CODEX-004: C-u cleanup NOT sent when agent is busy" {
    run bash -c '
        MOCK_CAPTURE_PANE="◦ Working on request (10s • esc to interrupt)"
        source "'"$TEST_HARNESS"'"
        FIRST_UNREAD_SEEN=12345
        normal_count=0
        if [ "$normal_count" -gt 0 ] 2>/dev/null; then
            echo "SHOULD_NOT_REACH"
        else
            FIRST_UNREAD_SEEN=0
            if ! agent_is_busy; then
                timeout 2 tmux send-keys -t "$PANE_TARGET" C-u 2>/dev/null
                echo "C_U_SENT"
            else
                echo "C_U_SKIPPED"
            fi
        fi
    '
    [ "$status" -eq 0 ]
    echo "$output" | grep -q "C_U_SKIPPED"
    ! grep -q "C-u" "$MOCK_LOG"
}

# --- T-CODEX-005: claude /clear passes through as-is ---

@test "T-CODEX-005: send_cli_command sends /clear as-is for claude" {
    run bash -c '
        source "'"$TEST_HARNESS"'"
        CLI_TYPE="claude"
        send_cli_command "/clear"
    '
    [ "$status" -eq 0 ]

    # Should send /clear directly (not /new)
    grep -q "send-keys.*/clear" "$MOCK_LOG"
    ! grep -q "/new" "$MOCK_LOG"
}

# --- T-CODEX-006: inbox_watcher.sh has agent_is_busy and Codex/Copilot handlers ---

@test "T-CODEX-006: inbox_watcher.sh contains agent_is_busy and Codex/Copilot handlers" {
    grep -q "agent_is_busy()" "$WATCHER_SCRIPT"
    grep -q 'Working|Thinking|Planning|Sending' "$WATCHER_SCRIPT"

    # Codex /clear → /new conversion exists
    grep -q '/new' "$WATCHER_SCRIPT"

    # Codex /model skip exists
    grep -q 'not supported on codex' "$WATCHER_SCRIPT"

    # C-u cleanup exists
    grep -q 'C-u' "$WATCHER_SCRIPT"

    # Copilot handler exists
    grep -q 'copilot --yolo' "$WATCHER_SCRIPT"
    grep -q 'not supported on copilot' "$WATCHER_SCRIPT"
}

# --- T-CODEX-007: pane cli overrides stale CLI_TYPE in Phase2 ---

@test "T-CODEX-007: pane @agent_cli=codex overrides stale CLI_TYPE for Phase2 (no C-c)" {
    run bash -c '
        MOCK_PANE_CLI="codex"
        source "'"$TEST_HARNESS"'"
        CLI_TYPE="claude"
        send_wakeup_with_escape 2
    '
    [ "$status" -eq 0 ]

    grep -q "send-keys.*Escape" "$MOCK_LOG"
    grep -q "send-keys.*inbox2" "$MOCK_LOG"
    ! grep -q "send-keys.*C-c" "$MOCK_LOG"
}

# --- T-CODEX-008: pane cli overrides stale CLI_TYPE in /clear path ---

@test "T-CODEX-008: pane @agent_cli=codex overrides stale CLI_TYPE for /clear (uses /new)" {
    run bash -c '
        MOCK_PANE_CLI="codex"
        source "'"$TEST_HARNESS"'"
        CLI_TYPE="claude"
        send_cli_command "/clear"
    '
    [ "$status" -eq 0 ]

    grep -q "send-keys.*/new" "$MOCK_LOG"
    ! grep -q "send-keys.*/clear" "$MOCK_LOG"
    ! grep -q "send-keys.*C-c" "$MOCK_LOG"
}

# --- T-CODEX-009: invalid model_switch payload is rejected ---

@test "T-CODEX-008b: command-layer codex は escalation /clear を抑止する" {
    run bash -c '
        MOCK_PANE_CLI="codex"
        source "'"$TEST_HARNESS"'"
        AGENT_ID="shogun"
        CLI_TYPE="claude"
        send_cli_command "/clear" "escalation"
    '
    [ "$status" -eq 0 ]

    ! grep -q "send-keys.*/new" "$MOCK_LOG"
    ! grep -q "send-keys.*/clear" "$MOCK_LOG"
}

@test "T-CODEX-008c: ashigaru codex は escalation /clear を /new へ変換する" {
    run bash -c '
        MOCK_PANE_CLI="codex"
        source "'"$TEST_HARNESS"'"
        AGENT_ID="ashigaru1"
        CLI_TYPE="claude"
        send_cli_command "/clear" "escalation"
    '
    [ "$status" -eq 0 ]

    grep -q "send-keys.*/new" "$MOCK_LOG"
    ! grep -q "send-keys.*/clear" "$MOCK_LOG"
}

# --- T-CODEX-009: invalid model_switch payload is rejected ---

@test "T-CODEX-009: normalize_special_command rejects invalid model_switch payload" {
    run bash -c '
        source "'"$TEST_HARNESS"'"
        cmd=$(normalize_special_command "model_switch" "please change model" 2>/dev/null)
        [ -z "$cmd" ]
    '
    [ "$status" -eq 0 ]
}

# --- T-CODEX-010: unresolved cli falls back to codex-safe ---

@test "T-CODEX-010: unresolved CLI type falls back to codex-safe (/clear->/new, no C-c)" {
    run bash -c '
        MOCK_PANE_CLI=""
        source "'"$TEST_HARNESS"'"
        CLI_TYPE="unknown_cli"
        send_cli_command "/clear"
    '
    [ "$status" -eq 0 ]

    grep -q "send-keys.*/new" "$MOCK_LOG"
    ! grep -q "send-keys.*/clear" "$MOCK_LOG"
    ! grep -q "send-keys.*C-c" "$MOCK_LOG"
}

@test "T-CODEX-010b: send_wakeup は Codex rate-limit prompt を dismiss してから nudge する" {
    run bash -c '
        MOCK_PANE_CLI="codex"
        MOCK_CAPTURE_PANE=$'"'"'Approaching rate limits\nSwitch to gpt-5.1-codex-mini\n3. Keep current model (never show again)'"'"'
        source "'"$TEST_HARNESS"'"
        send_wakeup 2
    '
    [ "$status" -eq 0 ]

    grep -q "send-keys -t test:0.0 3" "$MOCK_LOG"
    grep -q "send-keys -t test:0.0 inbox2" "$MOCK_LOG"
}

@test "T-CODEX-010b0: send_wakeup は Codex 通常画面では no-prompt を許容して nudge する" {
    run bash -c '
        MOCK_PANE_CLI="codex"
        MOCK_CAPTURE_PANE=$'"'"'normal codex idle screen'"'"'
        source "'"$TEST_HARNESS"'"
        send_wakeup 2
    '
    [ "$status" -eq 0 ]

    ! grep -q "send-keys -t test:0.0 3" "$MOCK_LOG"
    grep -q "send-keys -t test:0.0 inbox2" "$MOCK_LOG"
}

@test "T-CODEX-010b2: send_wakeup は Codex rate-limit prompt dismiss 失敗時に abort する" {
    run bash -c '
        MOCK_PANE_CLI="codex"
        MOCK_SENDKEYS_ENTER_RC=1
        MOCK_CAPTURE_PANE=$'"'"'Approaching rate limits\nKeep current model (never show again)'"'"'
        source "'"$TEST_HARNESS"'"
        send_wakeup 2
    '
    [ "$status" -eq 1 ]

    grep -q "send-keys -t test:0.0 3" "$MOCK_LOG"
    ! grep -q "send-keys -t test:0.0 inbox2" "$MOCK_LOG"
    echo "$output" | grep -qi "prompt dismiss failed\|Enter failed"
}

@test "T-CODEX-010c: send_wakeup_with_escape も Codex rate-limit prompt を dismiss する" {
    run bash -c '
        MOCK_PANE_CLI="codex"
        MOCK_CAPTURE_PANE=$'"'"'Approaching rate limits\nKeep current model (never show again)'"'"'
        source "'"$TEST_HARNESS"'"
        send_wakeup_with_escape 4
    '
    [ "$status" -eq 0 ]

    grep -q "send-keys -t test:0.0 3" "$MOCK_LOG"
    grep -q "send-keys.*Escape" "$MOCK_LOG"
    grep -q "send-keys.*inbox4" "$MOCK_LOG"
}

@test "T-CODEX-010c0: send_wakeup_with_escape は Codex 通常画面では no-prompt を許容して継続する" {
    run bash -c '
        MOCK_PANE_CLI="codex"
        MOCK_CAPTURE_PANE=$'"'"'normal codex idle screen'"'"'
        source "'"$TEST_HARNESS"'"
        send_wakeup_with_escape 4
    '
    [ "$status" -eq 0 ]

    ! grep -q "send-keys -t test:0.0 3" "$MOCK_LOG"
    grep -q "send-keys.*Escape" "$MOCK_LOG"
    grep -q "send-keys.*inbox4" "$MOCK_LOG"
}

@test "T-CODEX-010c2: send_wakeup_with_escape は Codex rate-limit prompt dismiss 失敗時に abort する" {
    run bash -c '
        MOCK_PANE_CLI="codex"
        MOCK_SENDKEYS_ENTER_RC=1
        MOCK_CAPTURE_PANE=$'"'"'Approaching rate limits\nKeep current model (never show again)'"'"'
        source "'"$TEST_HARNESS"'"
        send_wakeup_with_escape 4
    '
    [ "$status" -eq 1 ]

    grep -q "send-keys -t test:0.0 3" "$MOCK_LOG"
    ! grep -q "send-keys.*Escape" "$MOCK_LOG"
    ! grep -q "send-keys.*inbox4" "$MOCK_LOG"
    echo "$output" | grep -qi "prompt dismiss failed\|Enter failed"
}

@test "T-CODEX-010d: send_wakeup は Codex usage-limit prompt で mini 切替を選ぶ" {
    run bash -c '
        MOCK_PANE_CLI="codex"
        MOCK_CAPTURE_PANE=$(printf "%s\n%s\n%s" "You'\''ve hit your usage limit" "Switch to gpt-5.1-codex-mini" "1. Switch to gpt-5.1-codex-mini")
        source "'"$TEST_HARNESS"'"
        send_wakeup 1
    '
    [ "$status" -eq 0 ]

    grep -q "send-keys -t test:0.0 1" "$MOCK_LOG"
    grep -q "send-keys -t test:0.0 inbox1" "$MOCK_LOG"
}

@test "T-CODEX-010d2: send_wakeup は hard usage-limit prompt では 1 を送らず nudge も抑止する" {
    run bash -c '
        MOCK_PANE_CLI="codex"
        MOCK_CAPTURE_PANE=$(printf "%s\n%s" "You'\''ve hit your usage limit" "try again at Apr 4th, 2026 12:47 AM.")
        source "'"$TEST_HARNESS"'"
        send_wakeup 1
    '
    [ "$status" -eq 0 ]

    ! grep -q "send-keys -t test:0.0 1" "$MOCK_LOG"
    ! grep -q "send-keys -t test:0.0 inbox1" "$MOCK_LOG"
    echo "$output" | grep -qi "Hard Codex usage-limit prompt"
}

@test "T-CODEX-010d2b: send_wakeup は hard usage-limit prompt を dashboard 通知へ記録する" {
    export NOTICE_LOG="$TEST_TMPDIR/runtime_blocker_notice.log"
    export MOCK_NOTICE_SCRIPT="$TEST_TMPDIR/mock_runtime_blocker_notice.py"
    cat > "$MOCK_NOTICE_SCRIPT" <<'MOCK'
#!/usr/bin/env python3
import os
import sys

with open(os.environ["NOTICE_LOG"], "a", encoding="utf-8") as fh:
    fh.write(" ".join(sys.argv[1:]) + "\n")
MOCK
    chmod +x "$MOCK_NOTICE_SCRIPT"

    run bash -c '
        export MAS_RUNTIME_BLOCKER_NOTICE_SCRIPT="'"$MOCK_NOTICE_SCRIPT"'"
        MOCK_PANE_CLI="codex"
        MOCK_CAPTURE_PANE=$(printf "%s\n%s" "You'\''ve hit your usage limit" "try again at Apr 4th, 2026 12:47 AM.")
        source "'"$TEST_HARNESS"'"
        send_wakeup 1
    '
    [ "$status" -eq 0 ]

    grep -q -- '--agent test_agent --issue codex-hard-usage-limit' "$NOTICE_LOG"
    grep -q -- '--action record' "$NOTICE_LOG"
    grep -q -- '--detail You'\''ve hit your usage limit' "$NOTICE_LOG"
    ! grep -q "send-keys -t test:0.0 1" "$MOCK_LOG"
}

@test "T-CODEX-010d2c: send_wakeup は Codex 通常画面で stale blocked notice を除去する" {
    export NOTICE_LOG="$TEST_TMPDIR/runtime_blocker_notice_clear.log"
    export MOCK_NOTICE_SCRIPT="$TEST_TMPDIR/mock_runtime_blocker_notice_clear.py"
    cat > "$MOCK_NOTICE_SCRIPT" <<'MOCK'
#!/usr/bin/env python3
import os
import sys

with open(os.environ["NOTICE_LOG"], "a", encoding="utf-8") as fh:
    fh.write(" ".join(sys.argv[1:]) + "\n")
MOCK
    chmod +x "$MOCK_NOTICE_SCRIPT"

    run bash -c '
        export MAS_RUNTIME_BLOCKER_NOTICE_SCRIPT="'"$MOCK_NOTICE_SCRIPT"'"
        MOCK_PANE_CLI="codex"
        MOCK_CAPTURE_PANE=$'"'"'normal codex idle screen'"'"'
        source "'"$TEST_HARNESS"'"
        send_wakeup 1
    '
    [ "$status" -eq 0 ]

    grep -q -- '--action clear --agent test_agent --issue codex-hard-usage-limit' "$NOTICE_LOG"
    grep -q "send-keys -t test:0.0 inbox1" "$MOCK_LOG"
}

@test "T-CODEX-010d3: send_wakeup_with_escape は hard usage-limit prompt では Escape+nudge を抑止する" {
    run bash -c '
        MOCK_PANE_CLI="codex"
        MOCK_CAPTURE_PANE=$(printf "%s\n%s" "You'\''ve hit your usage limit" "try again at Apr 4th, 2026 12:47 AM.")
        source "'"$TEST_HARNESS"'"
        send_wakeup_with_escape 1
    '
    [ "$status" -eq 0 ]

    ! grep -q "send-keys -t test:0.0 1" "$MOCK_LOG"
    ! grep -q "send-keys.*Escape" "$MOCK_LOG"
    ! grep -q "send-keys -t test:0.0 inbox1" "$MOCK_LOG"
    echo "$output" | grep -qi "Hard Codex usage-limit prompt"
}

@test "T-CODEX-015: watcher は auth 解消後に pending bootstrap を literal 再配信する" {
    run bash -c '
        MOCK_PANE_CLI="codex"
        MOCK_CAPTURE_PANE=$'"'"'Welcome to Codex\nfor shortcuts'"'"'
        source "'"$TEST_HARNESS"'"
        SCRIPT_DIR="'"$TEST_TMPDIR"'/project"
        mkdir -p "$SCRIPT_DIR/queue/runtime"
        printf "%s\n" "【初動命令】ready:test_agent" > "$SCRIPT_DIR/queue/runtime/bootstrap_test_agent.md"
        : > "$SCRIPT_DIR/queue/runtime/bootstrap_test_agent.pending"
        deliver_pending_bootstrap_if_ready
        test ! -f "$SCRIPT_DIR/queue/runtime/bootstrap_test_agent.pending"
        test -f "$SCRIPT_DIR/queue/runtime/bootstrap_test_agent.delivered"
    '
    [ "$status" -eq 0 ]

    grep -q "send-keys -l -t test:0.0" "$MOCK_LOG"
    grep -q "send-keys -t test:0.0 Enter" "$MOCK_LOG"
}

@test "T-CODEX-015a: watcher は auth prompt 中の pending bootstrap を dashboard 通知へ記録する" {
    export NOTICE_LOG="$TEST_TMPDIR/runtime_blocker_notice_auth.log"
    export MOCK_NOTICE_SCRIPT="$TEST_TMPDIR/mock_runtime_blocker_notice_auth.py"
    cat > "$MOCK_NOTICE_SCRIPT" <<'MOCK'
#!/usr/bin/env python3
import os
import sys

with open(os.environ["NOTICE_LOG"], "a", encoding="utf-8") as fh:
    fh.write(" ".join(sys.argv[1:]) + "\n")
MOCK
    chmod +x "$MOCK_NOTICE_SCRIPT"

    run bash -c '
        export MAS_RUNTIME_BLOCKER_NOTICE_SCRIPT="'"$MOCK_NOTICE_SCRIPT"'"
        MOCK_PANE_CLI="codex"
        MOCK_CAPTURE_PANE=$'"'"'Welcome to Codex\n1. Sign in with ChatGPT\nPress Enter to continue'"'"'
        source "'"$TEST_HARNESS"'"
        SCRIPT_DIR="'"$TEST_TMPDIR"'/project"
        mkdir -p "$SCRIPT_DIR/queue/runtime"
        printf "%s\n" "【初動命令】ready:test_agent" > "$SCRIPT_DIR/queue/runtime/bootstrap_test_agent.md"
        : > "$SCRIPT_DIR/queue/runtime/bootstrap_test_agent.pending"
        deliver_pending_bootstrap_if_ready
        test -f "$SCRIPT_DIR/queue/runtime/bootstrap_test_agent.pending"
        test ! -f "$SCRIPT_DIR/queue/runtime/bootstrap_test_agent.delivered"
    '
    [ "$status" -eq 0 ]

    grep -q -- '--action record --agent test_agent --issue codex-auth-required' "$NOTICE_LOG"
    ! grep -q "send-keys -l -t test:0.0" "$MOCK_LOG"
}

@test "T-CODEX-015b: watcher は bootstrap 再配信成功時に auth notice を除去する" {
    export NOTICE_LOG="$TEST_TMPDIR/runtime_blocker_notice_auth_clear.log"
    export MOCK_NOTICE_SCRIPT="$TEST_TMPDIR/mock_runtime_blocker_notice_auth_clear.py"
    cat > "$MOCK_NOTICE_SCRIPT" <<'MOCK'
#!/usr/bin/env python3
import os
import sys

with open(os.environ["NOTICE_LOG"], "a", encoding="utf-8") as fh:
    fh.write(" ".join(sys.argv[1:]) + "\n")
MOCK
    chmod +x "$MOCK_NOTICE_SCRIPT"

    run bash -c '
        export MAS_RUNTIME_BLOCKER_NOTICE_SCRIPT="'"$MOCK_NOTICE_SCRIPT"'"
        MOCK_PANE_CLI="codex"
        MOCK_CAPTURE_PANE=$'"'"'Welcome to Codex\nfor shortcuts'"'"'
        source "'"$TEST_HARNESS"'"
        SCRIPT_DIR="'"$TEST_TMPDIR"'/project"
        mkdir -p "$SCRIPT_DIR/queue/runtime"
        printf "%s\n" "【初動命令】ready:test_agent" > "$SCRIPT_DIR/queue/runtime/bootstrap_test_agent.md"
        : > "$SCRIPT_DIR/queue/runtime/bootstrap_test_agent.pending"
        deliver_pending_bootstrap_if_ready
    '
    [ "$status" -eq 0 ]

    grep -q -- '--action clear --agent test_agent --issue codex-auth-required' "$NOTICE_LOG"
}

@test "T-CODEX-015c: watcher は Codex login server failure も auth-required として保留する" {
    export NOTICE_LOG="$TEST_TMPDIR/runtime_blocker_notice_auth_login_failure.log"
    export MOCK_NOTICE_SCRIPT="$TEST_TMPDIR/mock_runtime_blocker_notice_auth_login_failure.py"
    cat > "$MOCK_NOTICE_SCRIPT" <<'MOCK'
#!/usr/bin/env python3
import os
import sys

with open(os.environ["NOTICE_LOG"], "a", encoding="utf-8") as fh:
    fh.write(" ".join(sys.argv[1:]) + "\n")
MOCK
    chmod +x "$MOCK_NOTICE_SCRIPT"

    run bash -c '
        export MAS_RUNTIME_BLOCKER_NOTICE_SCRIPT="'"$MOCK_NOTICE_SCRIPT"'"
        MOCK_PANE_CLI="codex"
        MOCK_CAPTURE_PANE=$'"'"'Login server error: Login cancelled\naccount/login/start failed: failed to start login server: Port'"'"'
        source "'"$TEST_HARNESS"'"
        SCRIPT_DIR="'"$TEST_TMPDIR"'/project"
        mkdir -p "$SCRIPT_DIR/queue/runtime"
        printf "%s\n" "【初動命令】ready:test_agent" > "$SCRIPT_DIR/queue/runtime/bootstrap_test_agent.md"
        : > "$SCRIPT_DIR/queue/runtime/bootstrap_test_agent.pending"
        deliver_pending_bootstrap_if_ready
        test -f "$SCRIPT_DIR/queue/runtime/bootstrap_test_agent.pending"
        test ! -f "$SCRIPT_DIR/queue/runtime/bootstrap_test_agent.delivered"
    '
    [ "$status" -eq 0 ]

    grep -q -- '--action record --agent test_agent --issue codex-auth-required' "$NOTICE_LOG"
    ! grep -q "send-keys -l -t test:0.0" "$MOCK_LOG"
}

@test "T-CODEX-015d: watcher は Codex process が shell に戻っていたら pending bootstrap を再送しない" {
    run bash -c '
        MOCK_PANE_CLI="codex"
        MOCK_PANE_CURRENT_COMMAND="bash"
        MOCK_CAPTURE_PANE=$'"'"'Update ran successfully! Please restart Codex.'"'"'
        source "'"$TEST_HARNESS"'"
        SCRIPT_DIR="'"$TEST_TMPDIR"'/project"
        mkdir -p "$SCRIPT_DIR/queue/runtime"
        printf "%s\n" "【初動命令】ready:test_agent" > "$SCRIPT_DIR/queue/runtime/bootstrap_test_agent.md"
        : > "$SCRIPT_DIR/queue/runtime/bootstrap_test_agent.pending"
        deliver_pending_bootstrap_if_ready
        test -f "$SCRIPT_DIR/queue/runtime/bootstrap_test_agent.pending"
        test ! -f "$SCRIPT_DIR/queue/runtime/bootstrap_test_agent.delivered"
    '
    [ "$status" -eq 0 ]

    ! grep -q "send-keys -l -t test:0.0" "$MOCK_LOG"
}

@test "T-CODEX-015e: watcher は shell に戻った Codex pane を再起動する" {
    run bash -c '
        MOCK_PANE_CLI="codex"
        MOCK_PANE_CURRENT_COMMAND="bash"
        MOCK_CAPTURE_PANE=$'"'"'(test_agent) /repo$'"'"'
        source "'"$TEST_HARNESS"'"
        build_cli_command_with_type() { echo "codex --search --no-alt-screen"; }
        recover_shell_returned_codex_if_needed
    '
    [ "$status" -eq 0 ]

    grep -q "send-keys -t test:0.0 codex --search --no-alt-screen" "$MOCK_LOG"
    grep -q "send-keys -t test:0.0 Enter" "$MOCK_LOG"
}

# --- T-CODEX-011: clear_command auto-recovery injection ---

@test "T-CODEX-011: process_unread injects auto-recovery task and sends inbox nudge after clear_command" {
    run bash -c '
        source "'"$TEST_HARNESS"'"
        CLI_TYPE="codex"
        cat > "$INBOX" << "YAML"
messages:
  - id: msg_clear
    from: karo
    timestamp: "2026-02-10T14:00:00+09:00"
    type: clear_command
    content: redo
    read: false
YAML
        process_unread event
        python3 - << "PY" "$INBOX"
import sys
import yaml

inbox_path = sys.argv[1]
with open(inbox_path, "r", encoding="utf-8") as f:
    data = yaml.safe_load(f) or {}

messages = data.get("messages", []) or []
msg_clear = [m for m in messages if m.get("id") == "msg_clear"]
assert len(msg_clear) == 1 and msg_clear[0].get("read") is True

auto = [
    m for m in messages
    if m.get("from") == "inbox_watcher"
    and m.get("type") == "task_assigned"
    and "[auto-recovery]" in (m.get("content") or "")
]
assert len(auto) == 1
assert auto[0].get("read") is False
print("OK")
PY
    '
    [ "$status" -eq 0 ]
    echo "$output" | grep -q "OK"

    # codex clear path uses /new
    grep -q "send-keys.*/new" "$MOCK_LOG"
    # auto-injected unread should trigger inbox1 nudge
    grep -q "send-keys.*inbox1" "$MOCK_LOG"
}

# --- T-CODEX-012: auto-recovery dedupe ---

@test "T-CODEX-012: enqueue_recovery_task_assigned deduplicates unread auto-recovery message" {
    run bash -c '
        source "'"$TEST_HARNESS"'"
        cat > "$INBOX" << "YAML"
messages:
  - id: msg_auto_existing
    from: inbox_watcher
    timestamp: "2026-02-10T14:00:00+09:00"
    type: task_assigned
    content: "[auto-recovery] existing hint"
    read: false
YAML
        r1=$(enqueue_recovery_task_assigned)
        r2=$(enqueue_recovery_task_assigned)
        python3 - << "PY" "$INBOX" "$r1" "$r2"
import sys
import yaml

inbox_path, r1, r2 = sys.argv[1], sys.argv[2], sys.argv[3]
with open(inbox_path, "r", encoding="utf-8") as f:
    data = yaml.safe_load(f) or {}
messages = data.get("messages", []) or []
auto = [
    m for m in messages
    if m.get("from") == "inbox_watcher"
    and m.get("type") == "task_assigned"
    and "[auto-recovery]" in (m.get("content") or "")
    and m.get("read") is False
]
assert len(auto) == 1
assert r1 == "SKIP_DUPLICATE"
assert r2 == "SKIP_DUPLICATE"
print("OK")
PY
    '
    [ "$status" -eq 0 ]
    echo "$output" | grep -q "OK"
}

# --- T-COPILOT-001: copilot /clear → Ctrl-C + restart ---

@test "T-COPILOT-001: send_cli_command sends Ctrl-C + copilot restart for copilot /clear" {
    run bash -c '
        source "'"$TEST_HARNESS"'"
        CLI_TYPE="copilot"
        send_cli_command "/clear"
    '
    [ "$status" -eq 0 ]

    # Should trigger copilot restart
    grep -q "send-keys.*C-c" "$MOCK_LOG"
    grep -q "send-keys.*copilot --yolo" "$MOCK_LOG"
    # NOT /clear or /new
    ! grep -q "send-keys.*/clear" "$MOCK_LOG"
    ! grep -q "send-keys.*/new" "$MOCK_LOG"
}

# --- T-COPILOT-002: copilot /model → skip ---

@test "T-COPILOT-002: send_cli_command skips /model for copilot" {
    run bash -c '
        source "'"$TEST_HARNESS"'"
        CLI_TYPE="copilot"
        send_cli_command "/model opus"
    '
    [ "$status" -eq 0 ]

    ! grep -q "send-keys.*/model" "$MOCK_LOG"
    echo "$output" | grep -q "not supported on copilot"
}

# --- T-GEMINI-001: gemini /clear → Ctrl-C + restart ---

@test "T-GEMINI-001: send_cli_command sends Ctrl-C + gemini restart for gemini /clear" {
    run bash -c '
        source "'"$TEST_HARNESS"'"
        CLI_TYPE="gemini"
        send_cli_command "/clear"
    '
    [ "$status" -eq 0 ]

    grep -q "send-keys.*C-c" "$MOCK_LOG"
    grep -q "send-keys.*gemini --yolo" "$MOCK_LOG"
    ! grep -q "send-keys.*/clear" "$MOCK_LOG"
}

# --- T-OPENCODE-001: opencode /clear → Ctrl-C + restart ---

@test "T-OPENCODE-001: send_cli_command sends Ctrl-C + opencode restart for opencode /clear" {
    run bash -c '
        source "'"$TEST_HARNESS"'"
        CLI_TYPE="opencode"
        send_cli_command "/clear"
    '
    [ "$status" -eq 0 ]

    grep -q "send-keys.*C-c" "$MOCK_LOG"
    grep -q "send-keys.*opencode" "$MOCK_LOG"
    ! grep -q "send-keys.*/clear" "$MOCK_LOG"
}

@test "T-OPENCODE-002: send_cli_command skips /model for opencode" {
    run bash -c '
        source "'"$TEST_HARNESS"'"
        CLI_TYPE="opencode"
        send_cli_command "/model gpt-5.4"
    '
    [ "$status" -eq 0 ]

    ! grep -q "send-keys.*/model" "$MOCK_LOG"
}

# --- T-KILO-001: kilo /clear → Ctrl-C + restart ---

@test "T-KILO-001: send_cli_command sends Ctrl-C + kilo restart for kilo /clear" {
    run bash -c '
        source "'"$TEST_HARNESS"'"
        CLI_TYPE="kilo"
        send_cli_command "/clear"
    '
    [ "$status" -eq 0 ]

    grep -q "send-keys.*C-c" "$MOCK_LOG"
    grep -q "send-keys.*kilo" "$MOCK_LOG"
    ! grep -q "send-keys.*/clear" "$MOCK_LOG"
}

@test "T-KILO-002: send_cli_command skips /model for kilo" {
    run bash -c '
        source "'"$TEST_HARNESS"'"
        CLI_TYPE="kilo"
        send_cli_command "/model gpt-5.4"
    '
    [ "$status" -eq 0 ]

    ! grep -q "send-keys.*/model" "$MOCK_LOG"
}

# --- T-LOCALAPI-001: localapi /model → :model translation ---

@test "T-LOCALAPI-001: send_cli_command translates /model for localapi" {
    run bash -c '
        source "'"$TEST_HARNESS"'"
        CLI_TYPE="localapi"
        send_cli_command "/model qwen2.5-coder"
    '
    [ "$status" -eq 0 ]

    grep -q "send-keys.*:model qwen2.5-coder" "$MOCK_LOG"
}

# --- T-CODEX-013: busy中の/clearは延期する ---

@test "T-CODEX-013: send_cli_command defers /clear when agent is busy" {
    run bash -c '
        MOCK_CAPTURE_PANE="◦ Working on request (9s • esc to interrupt)"
        source "'"$TEST_HARNESS"'"
        send_cli_command "/clear"
    '
    [ "$status" -eq 0 ]

    ! grep -q "send-keys.*/clear" "$MOCK_LOG"
    ! grep -q "send-keys.*/new" "$MOCK_LOG"
    echo "$output" | grep -qi "deferred"
}

# --- T-CODEX-014: clear_commandはbusy中にauto-recoveryを生成しない ---

@test "T-CODEX-014: process_unread skips auto-recovery when clear_command is deferred by busy guard" {
    run bash -c '
        MOCK_CAPTURE_PANE="◦ Thinking deeply (7s • esc to interrupt)"
        source "'"$TEST_HARNESS"'"
        AGENT_ID="ashigaru1"
        CLI_TYPE="codex"
        INBOX="$TEST_INBOX_DIR/ashigaru1.yaml"
        LOCKFILE="${INBOX}.lock"
        cat > "$INBOX" << "YAML"
messages:
  - id: msg_clear_busy
    from: karo
    timestamp: "2026-03-05T10:00:00+09:00"
    type: clear_command
    content: redo
    read: false
YAML
        process_unread event
        python3 - << "PY" "$INBOX"
import sys
import yaml

inbox_path = sys.argv[1]
with open(inbox_path, "r", encoding="utf-8") as f:
    data = yaml.safe_load(f) or {}
messages = data.get("messages", []) or []

msg = [m for m in messages if m.get("id") == "msg_clear_busy"]
assert len(msg) == 1
assert msg[0].get("read") is True

auto = [
    m for m in messages
    if m.get("from") == "inbox_watcher"
    and m.get("type") == "task_assigned"
    and "[auto-recovery]" in (m.get("content") or "")
    and m.get("read") is False
]
assert len(auto) == 0
print("OK")
PY
    '
    [ "$status" -eq 0 ]
    echo "$output" | grep -q "OK"

    ! grep -q "send-keys.*/clear" "$MOCK_LOG"
    ! grep -q "send-keys.*/new" "$MOCK_LOG"
}
