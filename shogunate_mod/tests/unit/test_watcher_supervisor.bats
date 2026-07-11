#!/usr/bin/env bats

setup() {
  TEST_TMP="$(mktemp -d)"
  PROJECT_ROOT="$(cd "$(dirname "$BATS_TEST_FILENAME")/../.." && pwd)"
  export SHOGUNATE_REPO_ROOT="$PROJECT_ROOT"
  SUPERVISOR_SOURCE="$PROJECT_ROOT/shogunate_mod/watcher/supervisor.sh"
  SUPERVISOR_SNIPPET="$TEST_TMP/watcher_supervisor_functions.sh"
  sed '/^while true; do/,$d' "$SUPERVISOR_SOURCE" > "$SUPERVISOR_SNIPPET"
}

teardown() {
  rm -rf "$TEST_TMP"
}

@test "watcher_supervisor: cleanup_stale_watchers は gunkan/gunshi watcher を stale 扱いしない" {
  cat > "$TEST_TMP/pgrep_output.txt" <<EOF
1001 $PROJECT_ROOT/scripts/inbox_watcher.sh gunshi %9 claude tmux
1003 $PROJECT_ROOT/scripts/inbox_watcher.sh gunkan %8 claude tmux
1002 $PROJECT_ROOT/scripts/inbox_watcher.sh ashigaru9 %10 claude tmux
1004 $PROJECT_ROOT/shogunate_mod/watcher/inbox_watcher.sh gunshi %14 claude tmux
1005 $PROJECT_ROOT/shogunate_mod/watcher/inbox_watcher.sh ashigaru10 %15 claude tmux
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
  [[ "$output" == $'1002\n1005' ]]
}

@test "watcher_supervisor: cleanup_stale_watchers は karo と active ashigaru を保持する" {
  cat > "$TEST_TMP/pgrep_output.txt" <<EOF
2001 $PROJECT_ROOT/scripts/inbox_watcher.sh karo %11 codex tmux
2002 $PROJECT_ROOT/scripts/inbox_watcher.sh ashigaru1 %12 codex tmux
2003 $PROJECT_ROOT/scripts/inbox_watcher.sh ashigaru8 %13 codex tmux
2004 $PROJECT_ROOT/shogunate_mod/watcher/inbox_watcher.sh karo %14 codex tmux
2005 $PROJECT_ROOT/shogunate_mod/watcher/inbox_watcher.sh ashigaru8 %15 codex tmux
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
  [[ "$output" == $'2003\n2005' ]]
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
    source "$SUPERVISOR_SNIPPET"
    build_cli_command_with_type() { echo "codex --search"; }
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
  [[ "$output" == *"send-keys -l -t %4 codex --search"* ]]
  [[ "$output" == *"send-keys -t %4 Enter"* ]]
}

@test "watcher_supervisor: 起動直後grace中の codex pane は再起動しない" {
  run env TEST_TMP="$TEST_TMP" PROJECT_ROOT="$PROJECT_ROOT" SUPERVISOR_SNIPPET="$SUPERVISOR_SNIPPET" bash -lc '
    TEST_PROJECT="$TEST_TMP/project"
    NOW_TS="$(date +%s)"
    tmux() {
      if [[ "$*" == *"show-options -p -t %4 -v @agent_cli"* ]]; then
        echo "codex"
        return 0
      fi
      if [[ "$*" == *"show-options -p -t %4 -v @cli_launch_epoch"* ]]; then
        echo "$NOW_TS"
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
    build_cli_command_with_type() { echo "codex --search"; }
    source "$SUPERVISOR_SNIPPET"
    SCRIPT_DIR="$TEST_PROJECT"
    mkdir -p "$SCRIPT_DIR/queue/runtime"
    restart_shell_returned_codex_if_needed ashigaru2 %4
    test ! -f "$TEST_TMP/send_keys.log"
  '
  [ "$status" -eq 0 ]
}

@test "watcher_supervisor: initial bootstrap pending 中の codex pane は再起動しない" {
  run env TEST_TMP="$TEST_TMP" PROJECT_ROOT="$PROJECT_ROOT" SUPERVISOR_SNIPPET="$SUPERVISOR_SNIPPET" bash -lc '
    TEST_PROJECT="$TEST_TMP/project"
    tmux() {
      if [[ "$*" == *"show-options -p -t %4 -v @agent_cli"* ]]; then
        echo "codex"
        return 0
      fi
      if [[ "$*" == *"show-options -p -t %4 -v @cli_launch_epoch"* ]]; then
        echo ""
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
    build_cli_command_with_type() { echo "codex --search"; }
    source "$SUPERVISOR_SNIPPET"
    SCRIPT_DIR="$TEST_PROJECT"
    mkdir -p "$SCRIPT_DIR/queue/runtime"
    printf "%s\n" "【初動命令】ready:ashigaru2" > "$SCRIPT_DIR/queue/runtime/bootstrap_ashigaru2.md"
    : > "$SCRIPT_DIR/queue/runtime/bootstrap_ashigaru2.pending"
    restart_shell_returned_codex_if_needed ashigaru2 %4
    test ! -f "$TEST_TMP/send_keys.log"
  '
  [ "$status" -eq 0 ]
}

@test "watcher_supervisor: runtime startup grace 中の codex pane は再起動しない" {
  run env TEST_TMP="$TEST_TMP" PROJECT_ROOT="$PROJECT_ROOT" SUPERVISOR_SNIPPET="$SUPERVISOR_SNIPPET" bash -lc '
    TEST_PROJECT="$TEST_TMP/project"
    tmux() {
      if [[ "$*" == *"show-options -p -t %4 -v @agent_cli"* ]]; then
        echo "codex"
        return 0
      fi
      if [[ "$*" == *"show-options -p -t %4 -v @cli_launch_epoch"* ]]; then
        echo ""
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
    build_cli_command_with_type() { echo "codex --search"; }
    source "$SUPERVISOR_SNIPPET"
    SCRIPT_DIR="$TEST_PROJECT"
    mkdir -p "$SCRIPT_DIR/queue/runtime"
    date +%s > "$SCRIPT_DIR/queue/runtime/runtime_start_epoch"
    restart_shell_returned_codex_if_needed ashigaru2 %4
    test ! -f "$TEST_TMP/send_keys.log"
  '
  [ "$status" -eq 0 ]
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

@test "watcher_supervisor: pane 未生成でも supervisor_tick は即死しない" {
  run env TEST_TMP="$TEST_TMP" PROJECT_ROOT="$PROJECT_ROOT" SUPERVISOR_SNIPPET="$SUPERVISOR_SNIPPET" bash -lc '
    source "$SUPERVISOR_SNIPPET"
    refresh_active_ashigaru() { ACTIVE_ASHIGARU=(ashigaru1); }
    refresh_karo_agents() { KARO_AGENTS=(karo); }
    cleanup_stale_watchers() { :; }
    resolve_agent_pane_target() { return 1; }
    supervisor_tick
  '
  [ "$status" -eq 0 ]
}

@test "watcher_supervisor: supervisor_tick は Shogunate @agent_id から複数家老と離れた足軽を解決する" {
  run env TEST_TMP="$TEST_TMP" PROJECT_ROOT="$PROJECT_ROOT" SUPERVISOR_SNIPPET="$SUPERVISOR_SNIPPET" bash -lc '
    tmux() {
      case "$*" in
        "has-session -t shogunate") return 0 ;;
        "list-panes -s -t shogunate -F #{pane_id}") printf "%%1\n%%2\n%%3\n%%4\n%%5\n%%6\n%%7\n"; return 0 ;;
        "show-options -p -t %1 -v @agent_id") printf "shogun\n"; return 0 ;;
        "show-options -p -t %2 -v @agent_id") printf "gunkan\n"; return 0 ;;
        "show-options -p -t %3 -v @agent_id") printf "gunshi\n"; return 0 ;;
        "show-options -p -t %4 -v @agent_id") printf "karo1\n"; return 0 ;;
        "show-options -p -t %5 -v @agent_id") printf "karo2\n"; return 0 ;;
        "show-options -p -t %6 -v @agent_id") printf "ashigaru3\n"; return 0 ;;
        "show-options -p -t %7 -v @agent_id") printf "ashigaru8\n"; return 0 ;;
      esac
      return 0
    }
    source "$SUPERVISOR_SNIPPET"
    refresh_active_ashigaru() { ACTIVE_ASHIGARU=(ashigaru3 ashigaru8); }
    refresh_karo_agents() { KARO_AGENTS=(karo1 karo2); }
    cleanup_stale_watchers() { :; }
    restart_shell_returned_codex_if_needed() { :; }
    start_watcher_if_missing() { printf "%s=%s\n" "$1" "$2" >> "$TEST_TMP/watchers.log"; }
    supervisor_tick
    cat "$TEST_TMP/watchers.log"
  '
  [ "$status" -eq 0 ]
  [[ "$output" == *"shogun=%1"* ]]
  [[ "$output" == *"gunkan=%2"* ]]
  [[ "$output" == *"gunshi=%3"* ]]
  [[ "$output" == *"karo1=%4"* ]]
  [[ "$output" == *"karo2=%5"* ]]
  [[ "$output" == *"ashigaru3=%6"* ]]
  [[ "$output" == *"ashigaru8=%7"* ]]
  [[ "$output" != *"ashigaru1"* ]]
  [[ "$output" != *"multiagent:agents"* ]]
}

@test "watcher_supervisor: watcher 起動は tmux watcher window を作る" {
  run env PROJECT_ROOT="$PROJECT_ROOT" bash -lc '
    rg -q "WATCHER_RUNTIME_SESSION|watcher_window_name|tmux new-window -d -t \"\\$WATCHER_RUNTIME_SESSION\" -n \"\\$window_name\" \"\\$shell_cmd\"" "'"$PROJECT_ROOT"'/shogunate_mod/watcher/supervisor.sh"
  '
  [ "$status" -eq 0 ]
}
