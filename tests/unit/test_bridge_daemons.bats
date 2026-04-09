#!/usr/bin/env bats

setup() {
  TEST_TMP="$(mktemp -d)"
  PROJECT_ROOT="$(cd "$(dirname "$BATS_TEST_FILENAME")/../.." && pwd)"
  export TEST_TMP
}

teardown() {
  rm -rf "$TEST_TMP"
}

make_bridge_script() {
  local path="$1"
  local body="$2"
  BODY="$body" python3 - <<'PY' > "$path"
import os
print("#!/usr/bin/env python3")
print("import sys")
print(f"sys.stdout.write({os.environ['BODY']!r} + '\\n')")
PY
  chmod +x "$path"
}

@test "shogun_to_karo_bridge_daemon --once: noop は既定で出力しない" {
  make_bridge_script "$TEST_TMP/bridge.sh" $'noop\tempty'

  run env MAS_SHOGUN_TO_KARO_BRIDGE_SCRIPT="$TEST_TMP/bridge.sh" \
    bash "$PROJECT_ROOT/scripts/shogun_to_karo_bridge_daemon.sh" --once
  [ "$status" -eq 0 ]
  [ -z "$output" ]
}

@test "shogun_to_karo_bridge_daemon --once: verbose なら noop を出力する" {
  make_bridge_script "$TEST_TMP/bridge.sh" $'noop\tempty'

  run env MAS_BRIDGE_VERBOSE_NOOP=1 MAS_SHOGUN_TO_KARO_BRIDGE_SCRIPT="$TEST_TMP/bridge.sh" \
    bash "$PROJECT_ROOT/scripts/shogun_to_karo_bridge_daemon.sh" --once
  [ "$status" -eq 0 ]
  [[ "$output" == $'noop\tempty' ]]
}

@test "shogun_to_karo_bridge_daemon --once: primed は既定で出力しない" {
  make_bridge_script "$TEST_TMP/bridge.sh" $'primed\tcmd_001\t2026-04-09T14:00:00+09:00'

  run env MAS_SHOGUN_TO_KARO_BRIDGE_SCRIPT="$TEST_TMP/bridge.sh" \
    bash "$PROJECT_ROOT/scripts/shogun_to_karo_bridge_daemon.sh" --once
  [ "$status" -eq 0 ]
  [ -z "$output" ]
}

@test "shogun_to_karo_bridge_daemon --once: verbose なら primed を出力する" {
  make_bridge_script "$TEST_TMP/bridge.sh" $'primed\tcmd_001\t2026-04-09T14:00:00+09:00'

  run env MAS_BRIDGE_VERBOSE_NOOP=1 MAS_SHOGUN_TO_KARO_BRIDGE_SCRIPT="$TEST_TMP/bridge.sh" \
    bash "$PROJECT_ROOT/scripts/shogun_to_karo_bridge_daemon.sh" --once
  [ "$status" -eq 0 ]
  [[ "$output" == $'primed\tcmd_001\t2026-04-09T14:00:00+09:00' ]]
}

@test "shogun_to_karo_bridge_daemon --once: sent はそのまま出力する" {
  make_bridge_script "$TEST_TMP/bridge.sh" $'sent\tcmd_500'

  run env MAS_SHOGUN_TO_KARO_BRIDGE_SCRIPT="$TEST_TMP/bridge.sh" \
    bash "$PROJECT_ROOT/scripts/shogun_to_karo_bridge_daemon.sh" --once
  [ "$status" -eq 0 ]
  [[ "$output" == $'sent\tcmd_500' ]]
}

@test "karo_done_to_shogun_bridge_daemon --once: noop は既定で出力しない" {
  make_bridge_script "$TEST_TMP/bridge.sh" $'noop\talready_sent=cmd_001'

  run env MAS_KARO_DONE_TO_SHOGUN_SCRIPT="$TEST_TMP/bridge.sh" \
    bash "$PROJECT_ROOT/scripts/karo_done_to_shogun_bridge_daemon.sh" --once
  [ "$status" -eq 0 ]
  [ -z "$output" ]
}

@test "karo_done_to_shogun_bridge_daemon --once: primed は既定で出力しない" {
  make_bridge_script "$TEST_TMP/bridge.sh" $'primed\tcmd_001\t2026-04-09T14:00:00+09:00'

  run env MAS_KARO_DONE_TO_SHOGUN_SCRIPT="$TEST_TMP/bridge.sh" \
    bash "$PROJECT_ROOT/scripts/karo_done_to_shogun_bridge_daemon.sh" --once
  [ "$status" -eq 0 ]
  [ -z "$output" ]
}

@test "karo_done_to_shogun_bridge_daemon --once: verbose なら primed を出力する" {
  make_bridge_script "$TEST_TMP/bridge.sh" $'primed\tcmd_001\t2026-04-09T14:00:00+09:00'

  run env MAS_BRIDGE_VERBOSE_NOOP=1 MAS_KARO_DONE_TO_SHOGUN_SCRIPT="$TEST_TMP/bridge.sh" \
    bash "$PROJECT_ROOT/scripts/karo_done_to_shogun_bridge_daemon.sh" --once
  [ "$status" -eq 0 ]
  [[ "$output" == $'primed\tcmd_001\t2026-04-09T14:00:00+09:00' ]]
}

@test "karo_done_to_shogun_bridge_daemon --once: sent はそのまま出力する" {
  make_bridge_script "$TEST_TMP/bridge.sh" $'sent\tcmd_600'

  run env MAS_KARO_DONE_TO_SHOGUN_SCRIPT="$TEST_TMP/bridge.sh" \
    bash "$PROJECT_ROOT/scripts/karo_done_to_shogun_bridge_daemon.sh" --once
  [ "$status" -eq 0 ]
  [[ "$output" == $'sent\tcmd_600' ]]
}
