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
