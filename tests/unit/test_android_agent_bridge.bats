#!/usr/bin/env bats

setup() {
    export PROJECT_ROOT
    PROJECT_ROOT="$(cd "$BATS_TEST_DIRNAME/../.." && pwd)"
}

@test "android agent bridge has valid shell syntax" {
    run bash -n "$PROJECT_ROOT/scripts/android_agent_bridge.sh"
    [ "$status" -eq 0 ]
}

@test "android pairing profile has valid shell syntax" {
    run bash -n "$PROJECT_ROOT/scripts/android_pairing_profile.sh"
    [ "$status" -eq 0 ]
}

@test "android pairing profile prints tailscale metadata without secrets" {
    tmpdir="$BATS_TEST_TMPDIR/fakebin-profile"
    mkdir -p "$tmpdir"
    cat > "$tmpdir/tailscale" <<'EOF'
#!/usr/bin/env bash
if [ "$1" = "ip" ] && [ "$2" = "-4" ]; then
  printf '100.64.1.2\n'
  exit 0
fi
exit 9
EOF
    chmod +x "$tmpdir/tailscale"

    run env PATH="$tmpdir:$PATH" "$PROJECT_ROOT/scripts/android_pairing_profile.sh" --mode tailscale --ssh-port 2022 --project /repo/path
    [ "$status" -eq 0 ]
    [[ "$output" == *'"host": "100.64.1.2"'* ]]
    [[ "$output" == *'"port": "2022"'* ]]
    [[ "$output" == *'"projectPath": "/repo/path"'* ]]
    [[ "$output" != *password* ]]
    [[ "$output" != *privateKey* ]]
    [[ "$output" != *token* ]]
}

@test "android agent bridge resolves agents by tmux @agent_id and lists metadata" {
    tmpdir="$BATS_TEST_TMPDIR/fakebin"
    mkdir -p "$tmpdir"
    cat > "$tmpdir/tmux" <<'EOF'
#!/usr/bin/env bash
case "$*" in
  "has-session -t goza-no-ma") exit 0 ;;
  "list-panes -s -t goza-no-ma -F #{pane_id}") printf '%%1\n%%2\n%%3\n' ;;
  "show-options -p -t %1 -v @agent_id") printf 'shogun\n' ;;
  "show-options -p -t %2 -v @agent_id") printf 'karo1\n' ;;
  "show-options -p -t %3 -v @agent_id") printf 'ashigaru1\n' ;;
  "show-options -p -t %1 -v @model_name") printf 'Codex\n' ;;
  "show-options -p -t %2 -v @model_name") printf 'Claude\n' ;;
  "show-options -p -t %3 -v @model_name") printf 'OpenCode\n' ;;
  "show-options -p -t %1 -v @agent_cli") printf 'codex\n' ;;
  "show-options -p -t %2 -v @agent_cli") printf 'claude\n' ;;
  "show-options -p -t %3 -v @agent_cli") printf 'opencode\n' ;;
  *) printf 'unexpected tmux call: %s\n' "$*" >&2; exit 9 ;;
esac
EOF
    chmod +x "$tmpdir/tmux"

    run env TMUX_BIN="$tmpdir/tmux" "$PROJECT_ROOT/scripts/android_agent_bridge.sh" list
    [ "$status" -eq 0 ]
    [[ "$output" == *$'shogun\tCodex\tcodex'* ]]
    [[ "$output" == *$'karo1\tClaude\tclaude'* ]]
    [[ "$output" == *$'ashigaru1\tOpenCode\topencode'* ]]
}

@test "android agent bridge sends decoded base64 literal text and Enter to selected agent" {
    tmpdir="$BATS_TEST_TMPDIR/fakebin-send"
    log="$BATS_TEST_TMPDIR/tmux.log"
    mkdir -p "$tmpdir"
    cat > "$tmpdir/tmux" <<'EOF'
#!/usr/bin/env bash
log="${TMUX_FAKE_LOG:?}"
case "$*" in
  "has-session -t goza-no-ma") exit 0 ;;
  "list-panes -s -t goza-no-ma -F #{pane_id}") printf '%%1\n%%2\n' ;;
  "show-options -p -t %1 -v @agent_id") printf 'shogun\n' ;;
  "show-options -p -t %2 -v @agent_id") printf 'ashigaru2\n' ;;
  "send-keys -l -t %2 hello world") printf 'literal-ok\n' >> "$log" ;;
  "send-keys -t %2 Enter") printf 'enter-ok\n' >> "$log" ;;
  *) printf 'unexpected tmux call: %s\n' "$*" >&2; exit 9 ;;
esac
EOF
    chmod +x "$tmpdir/tmux"

    run env TMUX_BIN="$tmpdir/tmux" TMUX_FAKE_LOG="$log" "$PROJECT_ROOT/scripts/android_agent_bridge.sh" send-b64 ashigaru2 "aGVsbG8gd29ybGQ="
    [ "$status" -eq 0 ]
    run cat "$log"
    [ "$status" -eq 0 ]
    [[ "$output" == *"literal-ok"* ]]
    [[ "$output" == *"enter-ok"* ]]
}
