#!/usr/bin/env bats

setup() {
  PROJECT_ROOT="$(cd "$(dirname "$BATS_TEST_FILENAME")/../.." && pwd)"
}

@test "runtime launchers: Unix wrappers are valid shell and call shutsujin" {
  run bash -n "$PROJECT_ROOT/Shutsujin.sh"
  [ "$status" -eq 0 ]

  run bash -n "$PROJECT_ROOT/Shogunate-Runtime.sh"
  [ "$status" -eq 0 ]

  run bash -n "$PROJECT_ROOT/Shogunate-Runtime.command"
  [ "$status" -eq 0 ]

  run grep -F "bash shutsujin_departure.sh" "$PROJECT_ROOT/Shogunate-Runtime.sh"
  [ "$status" -eq 0 ]

  run grep -F "MAS_WAIT_FOR_GOZA_CLIENT_BEFORE_CLI=1" "$PROJECT_ROOT/Shogunate-Runtime.sh"
  [ "$status" -eq 0 ]

  run grep -F "MAS_LAUNCHER_RUN_ID" "$PROJECT_ROOT/Shogunate-Runtime.sh"
  [ "$status" -eq 0 ]

  run grep -F "tmux attach-session -t goza-no-ma" "$PROJECT_ROOT/Shogunate-Runtime.sh"
  [ "$status" -eq 0 ]
}

@test "runtime launchers: Shutsujin attaches before CLI launch and keeps manual fallback aliases" {
  run grep -F "bash shutsujin_departure.sh" "$PROJECT_ROOT/Shutsujin.sh"
  [ "$status" -eq 0 ]

  run grep -F "MAS_WAIT_FOR_GOZA_CLIENT_BEFORE_CLI=1" "$PROJECT_ROOT/Shutsujin.sh"
  [ "$status" -eq 0 ]

  run grep -F "MAS_LAUNCHER_RUN_ID" "$PROJECT_ROOT/Shutsujin.sh"
  [ "$status" -eq 0 ]

  run grep -F "tmux attach-session -t goza-no-ma" "$PROJECT_ROOT/Shutsujin.sh"
  [ "$status" -eq 0 ]

  run grep -F "scripts/shell_aliases.sh" "$PROJECT_ROOT/Shutsujin.sh"
  [ "$status" -eq 0 ]

  run grep -F "cgo/CGO = Goza View" "$PROJECT_ROOT/Shutsujin.sh"
  [ "$status" -eq 0 ]

  run grep -F "csa/CSA = Ashigaru View" "$PROJECT_ROOT/Shutsujin.sh"
  [ "$status" -eq 0 ]

  run grep -F "csm/CSM = Multiagent" "$PROJECT_ROOT/Shutsujin.sh"
  [ "$status" -eq 0 ]

  run grep -F "csk/CSK or ckr/CKR = Karo" "$PROJECT_ROOT/Shutsujin.sh"
  [ "$status" -eq 0 ]
}

@test "runtime launchers: Windows wrapper runs shutsujin through Ubuntu WSL and attaches" {
  run grep -F "wsl.exe -d Ubuntu" "$PROJECT_ROOT/Shogunate-Runtime.bat"
  [ "$status" -eq 0 ]

  run grep -F "bash ./Shogunate-Runtime.sh" "$PROJECT_ROOT/Shogunate-Runtime.bat"
  [ "$status" -eq 0 ]

  run grep -F "Shogunate-Runtime.sh" "$PROJECT_ROOT/Shogunate-Runtime.bat"
  [ "$status" -eq 0 ]
}

@test "runtime launchers: Windows Shutsujin wrapper opens Goza via Shutsujin, not Runtime" {
  run grep -F "wsl.exe -d Ubuntu" "$PROJECT_ROOT/Shutsujin.bat"
  [ "$status" -eq 0 ]

  run grep -F "bash ./Shutsujin.sh" "$PROJECT_ROOT/Shutsujin.bat"
  [ "$status" -eq 0 ]

  run grep -F "opens Goza before agent CLIs launch" "$PROJECT_ROOT/Shutsujin.bat"
  [ "$status" -eq 0 ]

  run grep -F "Use --no-attach for the old manual shell workflow" "$PROJECT_ROOT/Shutsujin.bat"
  [ "$status" -eq 0 ]

  run grep -F "[1/3]" "$PROJECT_ROOT/Shutsujin.bat"
  [ "$status" -ne 0 ]

  run grep -F "[2/3]" "$PROJECT_ROOT/Shutsujin.bat"
  [ "$status" -ne 0 ]

  run grep -F "[3/3]" "$PROJECT_ROOT/Shutsujin.bat"
  [ "$status" -ne 0 ]

  run grep -F "Shogunate-Runtime.sh" "$PROJECT_ROOT/Shutsujin.bat"
  [ "$status" -ne 0 ]
}

@test "runtime launchers: Windows debug wrappers split clean and resume starts" {
  run test -f "$PROJECT_ROOT/Shutsujin-Clean.bat"
  [ "$status" -eq 0 ]

  run test -f "$PROJECT_ROOT/Shutsujin-Resume.bat"
  [ "$status" -eq 0 ]

  run grep -F 'call "%SCRIPT_DIR%\Shutsujin.bat" -c %*' "$PROJECT_ROOT/Shutsujin-Clean.bat"
  [ "$status" -eq 0 ]

  run grep -F 'call "%SCRIPT_DIR%\Shutsujin.bat" %*' "$PROJECT_ROOT/Shutsujin-Resume.bat"
  [ "$status" -eq 0 ]

  run grep -F 'Shogunate-Runtime' "$PROJECT_ROOT/Shutsujin-Clean.bat" "$PROJECT_ROOT/Shutsujin-Resume.bat"
  [ "$status" -ne 0 ]
}
