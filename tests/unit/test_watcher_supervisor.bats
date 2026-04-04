#!/usr/bin/env bats

setup() {
  TEST_TMP="$(mktemp -d)"
  PROJECT_ROOT="$(cd "$(dirname "$BATS_TEST_FILENAME")/../.." && pwd)"
  SUPERVISOR_SNIPPET="$TEST_TMP/watcher_supervisor_functions.sh"
  sed '/^while true; do/,$d' "$PROJECT_ROOT/scripts/watcher_supervisor.sh" > "$SUPERVISOR_SNIPPET"
}

teardown() {
  rm -rf "$TEST_TMP"
}

@test "watcher_supervisor: cleanup_stale_watchers は gunshi watcher を stale 扱いしない" {
  cat > "$TEST_TMP/pgrep_output.txt" <<EOF
1001 $PROJECT_ROOT/scripts/inbox_watcher.sh gunshi %9 claude tmux
1002 $PROJECT_ROOT/scripts/inbox_watcher.sh ashigaru9 %10 claude tmux
EOF

  run env TEST_TMP="$TEST_TMP" PROJECT_ROOT="$PROJECT_ROOT" SUPERVISOR_SNIPPET="$SUPERVISOR_SNIPPET" bash -lc '
    pgrep() { cat "$TEST_TMP/pgrep_output.txt"; }
    kill() { echo "$1" >> "$TEST_TMP/killed.txt"; }
    source "$SUPERVISOR_SNIPPET"
    ACTIVE_ASHIGARU=(ashigaru1)
    KARO_AGENTS=(karo)
    cleanup_stale_watchers
  '
  [ "$status" -eq 0 ]
  run cat "$TEST_TMP/killed.txt"
  [ "$status" -eq 0 ]
  [[ "$output" == "1002" ]]
}

@test "watcher_supervisor: cleanup_stale_watchers は karo と active ashigaru を保持する" {
  cat > "$TEST_TMP/pgrep_output.txt" <<EOF
2001 $PROJECT_ROOT/scripts/inbox_watcher.sh karo %11 codex tmux
2002 $PROJECT_ROOT/scripts/inbox_watcher.sh ashigaru1 %12 codex tmux
2003 $PROJECT_ROOT/scripts/inbox_watcher.sh ashigaru8 %13 codex tmux
EOF

  run env TEST_TMP="$TEST_TMP" PROJECT_ROOT="$PROJECT_ROOT" SUPERVISOR_SNIPPET="$SUPERVISOR_SNIPPET" bash -lc '
    pgrep() { cat "$TEST_TMP/pgrep_output.txt"; }
    kill() { echo "$1" >> "$TEST_TMP/killed.txt"; }
    source "$SUPERVISOR_SNIPPET"
    ACTIVE_ASHIGARU=(ashigaru1)
    KARO_AGENTS=(karo)
    cleanup_stale_watchers
  '
  [ "$status" -eq 0 ]
  run cat "$TEST_TMP/killed.txt"
  [ "$status" -eq 0 ]
  [[ "$output" == "2003" ]]
}

@test "watcher_supervisor: shell に戻った codex pane を cooldown 付きで再起動する" {
  run env TEST_TMP="$TEST_TMP" PROJECT_ROOT="$PROJECT_ROOT" SUPERVISOR_SNIPPET="$SUPERVISOR_SNIPPET" bash -lc '
    TEST_PROJECT="$TEST_TMP/project"
    tmux() {
      if [[ "$*" == *"display-message -p -t %4 #{pane_id}"* ]]; then
        echo "%4"
        return 0
      fi
      if [[ "$*" == *"show-options -p -t %4 -v @agent_cli"* ]]; then
        echo "codex"
        return 0
      fi
      if [[ "$*" == *"display-message -p -t %4 #{pane_current_command}"* ]]; then
        echo "bash"
        return 0
      fi
      if [[ "$1" == "send-keys" ]]; then
        echo "$*" >> "$TEST_TMP/send_keys.log"
        return 0
      fi
      return 0
    }
    build_cli_command_with_type() { echo "codex --search --no-alt-screen"; }
    source "$SUPERVISOR_SNIPPET"
    SCRIPT_DIR="$TEST_PROJECT"
    mkdir -p "$SCRIPT_DIR/queue/runtime"
    printf "%s\n" "【初動命令】ready:ashigaru2" > "$SCRIPT_DIR/queue/runtime/bootstrap_ashigaru2.md"
    : > "$SCRIPT_DIR/queue/runtime/bootstrap_ashigaru2.delivered"
    restart_shell_returned_codex_if_needed ashigaru2 %4
    cat "$TEST_TMP/send_keys.log"
    test -f "$SCRIPT_DIR/queue/runtime/cli_restart_ashigaru2.state"
    test -f "$SCRIPT_DIR/queue/runtime/bootstrap_ashigaru2.pending"
    test ! -f "$SCRIPT_DIR/queue/runtime/bootstrap_ashigaru2.delivered"
  '
  [ "$status" -eq 0 ]
  [[ "$output" == *"send-keys -t %4 codex --search --no-alt-screen Enter"* ]]
}

@test "watcher_supervisor: codex pane が node に戻ったら restart state を消す" {
  run env TEST_TMP="$TEST_TMP" PROJECT_ROOT="$PROJECT_ROOT" SUPERVISOR_SNIPPET="$SUPERVISOR_SNIPPET" bash -lc '
    TEST_PROJECT="$TEST_TMP/project"
    tmux() {
      if [[ "$*" == *"display-message -p -t %4 #{pane_id}"* ]]; then
        echo "%4"
        return 0
      fi
      if [[ "$*" == *"show-options -p -t %4 -v @agent_cli"* ]]; then
        echo "codex"
        return 0
      fi
      if [[ "$*" == *"display-message -p -t %4 #{pane_current_command}"* ]]; then
        echo "node"
        return 0
      fi
      return 0
    }
    source "$SUPERVISOR_SNIPPET"
    SCRIPT_DIR="$TEST_PROJECT"
    mkdir -p "$SCRIPT_DIR/queue/runtime"
    printf "123\t%%4\tcodex\n" > "$SCRIPT_DIR/queue/runtime/cli_restart_ashigaru2.state"
    restart_shell_returned_codex_if_needed ashigaru2 %4
    test ! -f "$SCRIPT_DIR/queue/runtime/cli_restart_ashigaru2.state"
  '
  [ "$status" -eq 0 ]
}
