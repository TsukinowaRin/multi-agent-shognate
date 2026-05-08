#!/usr/bin/env bats

setup() {
  PROJECT_ROOT="$(cd "$(dirname "$BATS_TEST_FILENAME")/../.." && pwd)"
}

@test "runtime launchers: Unix wrappers are valid shell and call shutsujin" {
  run bash -n "$PROJECT_ROOT/Shogunate-Runtime.sh"
  [ "$status" -eq 0 ]

  run bash -n "$PROJECT_ROOT/Shogunate-Runtime.command"
  [ "$status" -eq 0 ]

  run grep -F "bash shutsujin_departure.sh" "$PROJECT_ROOT/Shogunate-Runtime.sh"
  [ "$status" -eq 0 ]

  run grep -F "tmux attach-session -t goza-no-ma" "$PROJECT_ROOT/Shogunate-Runtime.sh"
  [ "$status" -eq 0 ]
}

@test "runtime launchers: Windows wrapper runs shutsujin through Ubuntu WSL and attaches" {
  run grep -F "wsl.exe -d Ubuntu" "$PROJECT_ROOT/Shogunate-Runtime.bat"
  [ "$status" -eq 0 ]

  run grep -F "bash shutsujin_departure.sh" "$PROJECT_ROOT/Shogunate-Runtime.bat"
  [ "$status" -eq 0 ]

  run grep -F "tmux attach-session -t goza-no-ma" "$PROJECT_ROOT/Shogunate-Runtime.bat"
  [ "$status" -eq 0 ]
}
