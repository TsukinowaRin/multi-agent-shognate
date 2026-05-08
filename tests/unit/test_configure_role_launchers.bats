#!/usr/bin/env bats

setup() {
  PROJECT_ROOT="$(cd "$(dirname "$BATS_TEST_FILENAME")/../.." && pwd)"
}

@test "configure role launchers: Unix wrappers are valid shell and call canonical script" {
  run bash -n "$PROJECT_ROOT/Shogunate-Configure-Roles.sh"
  [ "$status" -eq 0 ]

  run bash -n "$PROJECT_ROOT/Shogunate-Configure-Roles.command"
  [ "$status" -eq 0 ]

  run grep -F "python3 scripts/configure_runtime_roles.py" "$PROJECT_ROOT/Shogunate-Configure-Roles.sh"
  [ "$status" -eq 0 ]

  run grep -F "python3 scripts/configure_runtime_roles.py" "$PROJECT_ROOT/Shogunate-Configure-Roles.command"
  [ "$status" -eq 0 ]
}

@test "configure role launchers: Windows wrapper runs canonical script through Ubuntu WSL" {
  run grep -F "wsl.exe -d Ubuntu" "$PROJECT_ROOT/Shogunate-Configure-Roles.bat"
  [ "$status" -eq 0 ]

  run grep -F "wslpath -a" "$PROJECT_ROOT/Shogunate-Configure-Roles.bat"
  [ "$status" -eq 0 ]

  run grep -F "python3 scripts/configure_runtime_roles.py" "$PROJECT_ROOT/Shogunate-Configure-Roles.bat"
  [ "$status" -eq 0 ]
}
