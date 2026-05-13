#!/usr/bin/env bats

setup() {
  PROJECT_ROOT="$(cd "$(dirname "$BATS_TEST_FILENAME")/../.." && pwd)"
  WATCH_LIB="$PROJECT_ROOT/lib/file_watch.sh"
  TEST_TMP="$(mktemp -d)"
}

teardown() {
  rm -rf "$TEST_TMP"
}

@test "file_watch: auto selects fswatch when inotifywait is unavailable" {
  run bash -lc '
    command() {
      if [ "$1" = "-v" ]; then
        case "$2" in
          inotifywait) return 1 ;;
          fswatch) echo fswatch; return 0 ;;
        esac
      fi
      builtin command "$@"
    }
    source "'"$WATCH_LIB"'"
    file_watch_backend
  '
  [ "$status" -eq 0 ]
  [ "$output" = "fswatch" ]
}

@test "file_watch: polling fallback is available when no native watcher exists" {
  run bash -lc '
    command() {
      if [ "$1" = "-v" ]; then
        case "$2" in
          inotifywait|fswatch) return 1 ;;
        esac
      fi
      builtin command "$@"
    }
    source "'"$WATCH_LIB"'"
    file_watch_backend
    file_watch_backend_available
  '
  [ "$status" -eq 0 ]
  [[ "$output" == "polling" ]]
}

@test "file_watch: fswatch one-shot event returns event rc" {
  touch "$TEST_TMP/inbox.yaml"
  run bash -lc '
    fswatch() { return 0; }
    source "'"$WATCH_LIB"'"
    MAS_FILE_WATCH_BACKEND=fswatch file_watch_wait_once "'"$TEST_TMP"'/inbox.yaml" 1
  '
  [ "$status" -eq 0 ]
}

@test "file_watch: polling wait returns timeout rc" {
  touch "$TEST_TMP/inbox.yaml"
  run bash -lc '
    sleep() { :; }
    source "'"$WATCH_LIB"'"
    MAS_FILE_WATCH_BACKEND=polling file_watch_wait_once "'"$TEST_TMP"'/inbox.yaml" 1
  '
  [ "$status" -eq 2 ]
}

@test "file_watch: forced missing fswatch falls back to timeout rc" {
  touch "$TEST_TMP/inbox.yaml"
  run bash -lc '
    sleep() { :; }
    command() {
      if [ "$1" = "-v" ] && [ "$2" = "fswatch" ]; then
        return 1
      fi
      builtin command "$@"
    }
    source "'"$WATCH_LIB"'"
    MAS_FILE_WATCH_BACKEND=fswatch file_watch_wait_once "'"$TEST_TMP"'/inbox.yaml" 1
  '
  [ "$status" -eq 2 ]
}
