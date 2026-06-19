#!/usr/bin/env bats

setup() {
  PROJECT_ROOT="$(cd "$(dirname "$BATS_TEST_FILENAME")/../.." && pwd)"
}

@test "runtime launchers: Unix wrappers are valid shell and call the MOD runtime entrypoint" {
  run bash -n "$PROJECT_ROOT/Shutsujin.sh"
  [ "$status" -eq 0 ]

  run bash -n "$PROJECT_ROOT/Shogunate-Runtime.sh"
  [ "$status" -eq 0 ]

  run bash -n "$PROJECT_ROOT/shogunate_mod/runtime/runtime_launcher.sh"
  [ "$status" -eq 0 ]

  run bash -n "$PROJECT_ROOT/shogunate_mod/runtime/shutsujin_launcher.sh"
  [ "$status" -eq 0 ]

  run bash -n "$PROJECT_ROOT/Shogunate-Runtime.command"
  [ "$status" -eq 0 ]

  run bash -n "$PROJECT_ROOT/shogunate_mod/macos/runtime_launcher.command"
  [ "$status" -eq 0 ]

  run bash -n "$PROJECT_ROOT/shogunate_mod/runtime/launcher.sh"
  [ "$status" -eq 0 ]

  run bash -n "$PROJECT_ROOT/shogunate_mod/runtime/entrypoint.sh"
  [ "$status" -eq 0 ]

  run grep -F "shogunate_mod/macos/runtime_launcher.command" "$PROJECT_ROOT/Shogunate-Runtime.command"
  [ "$status" -eq 0 ]

  run grep -F "shogunate_mod/runtime/runtime_launcher.sh" "$PROJECT_ROOT/shogunate_mod/macos/runtime_launcher.command"
  [ "$status" -eq 0 ]

  run grep -F "shogunate_mod/runtime/runtime_launcher.sh" "$PROJECT_ROOT/Shogunate-Runtime.sh"
  [ "$status" -eq 0 ]

  run grep -F "shogunate_mod/runtime/launcher.sh" "$PROJECT_ROOT/shogunate_mod/runtime/runtime_launcher.sh"
  [ "$status" -eq 0 ]

  run grep -F "bash shogunate_mod/runtime/entrypoint.sh" "$PROJECT_ROOT/shogunate_mod/runtime/runtime_launcher.sh"
  [ "$status" -eq 0 ]

  run grep -F "Usage: bash shogunate_mod/runtime/runtime_launcher.sh" "$PROJECT_ROOT/shogunate_mod/runtime/runtime_launcher.sh"
  [ "$status" -eq 0 ]

  run grep -F "Usage: ./Shogunate-Runtime.sh" "$PROJECT_ROOT/shogunate_mod/runtime/runtime_launcher.sh"
  [ "$status" -ne 0 ]

  run grep -F "bash shutsujin_departure.sh" "$PROJECT_ROOT/shogunate_mod/runtime/runtime_launcher.sh"
  [ "$status" -ne 0 ]

  run grep -F "MAS_WAIT_FOR_GOZA_CLIENT_BEFORE_CLI=1" "$PROJECT_ROOT/shogunate_mod/runtime/runtime_launcher.sh"
  [ "$status" -eq 0 ]

  run grep -F "MAS_LAUNCHER_RUN_ID" "$PROJECT_ROOT/shogunate_mod/runtime/runtime_launcher.sh"
  [ "$status" -eq 0 ]

  run grep -F "MAS_GOZA_STARTUP_LOG" "$PROJECT_ROOT/shogunate_mod/runtime/runtime_launcher.sh"
  [ "$status" -eq 0 ]

  run grep -F "SHOGUNATE_PROJECT_DIR" "$PROJECT_ROOT/shogunate_mod/runtime/runtime_launcher.sh"
  [ "$status" -eq 0 ]

  run grep -F -- "--project" "$PROJECT_ROOT/shogunate_mod/runtime/runtime_launcher.sh"
  [ "$status" -eq 0 ]

  run grep -F 'tmux attach-session -t "$SHOGUNATE_SESSION_NAME"' "$PROJECT_ROOT/shogunate_mod/runtime/runtime_launcher.sh"
  [ "$status" -eq 0 ]
}

@test "runtime launchers: Shutsujin attaches before CLI launch and keeps manual fallback aliases" {
  run grep -F "shogunate_mod/runtime/shutsujin_launcher.sh" "$PROJECT_ROOT/Shutsujin.sh"
  [ "$status" -eq 0 ]

  run grep -F "shogunate_mod/runtime/launcher.sh" "$PROJECT_ROOT/shogunate_mod/runtime/shutsujin_launcher.sh"
  [ "$status" -eq 0 ]

  run grep -F "bash shogunate_mod/runtime/entrypoint.sh" "$PROJECT_ROOT/shogunate_mod/runtime/shutsujin_launcher.sh"
  [ "$status" -eq 0 ]

  run grep -F "bash shutsujin_departure.sh" "$PROJECT_ROOT/shogunate_mod/runtime/shutsujin_launcher.sh"
  [ "$status" -ne 0 ]

  run grep -F "MAS_WAIT_FOR_GOZA_CLIENT_BEFORE_CLI=1" "$PROJECT_ROOT/shogunate_mod/runtime/shutsujin_launcher.sh"
  [ "$status" -eq 0 ]

  run grep -F "MAS_LAUNCHER_RUN_ID" "$PROJECT_ROOT/shogunate_mod/runtime/shutsujin_launcher.sh"
  [ "$status" -eq 0 ]

  run grep -F "MAS_GOZA_STARTUP_LOG" "$PROJECT_ROOT/shogunate_mod/runtime/shutsujin_launcher.sh"
  [ "$status" -eq 0 ]

  run grep -F "MAS_GOZA_FINISH_TARGET=command" "$PROJECT_ROOT/shogunate_mod/runtime/shutsujin_launcher.sh"
  [ "$status" -eq 0 ]

  run grep -F "SHOGUNATE_PROJECT_DIR" "$PROJECT_ROOT/shogunate_mod/runtime/shutsujin_launcher.sh"
  [ "$status" -eq 0 ]

  run grep -F 'tmux attach-session -t "$SHOGUNATE_SESSION_NAME"' "$PROJECT_ROOT/shogunate_mod/runtime/shutsujin_launcher.sh"
  [ "$status" -eq 0 ]

  run grep -F "shogunate_mod/shell/aliases.sh" "$PROJECT_ROOT/shogunate_mod/runtime/shutsujin_launcher.sh"
  [ "$status" -eq 0 ]

  run grep -F "cgo/CGO = Goza View" "$PROJECT_ROOT/shogunate_mod/runtime/shutsujin_launcher.sh"
  [ "$status" -eq 0 ]

  run grep -F "csa/CSA = Ashigaru View" "$PROJECT_ROOT/shogunate_mod/runtime/shutsujin_launcher.sh"
  [ "$status" -eq 0 ]

  run grep -F "csm/CSM = Multiagent" "$PROJECT_ROOT/shogunate_mod/runtime/shutsujin_launcher.sh"
  [ "$status" -eq 0 ]

  run grep -F "csk/CSK or ckr/CKR = Karo" "$PROJECT_ROOT/shogunate_mod/runtime/shutsujin_launcher.sh"
  [ "$status" -eq 0 ]

  run grep -F "cgn/CGN = Gunkan" "$PROJECT_ROOT/shogunate_mod/runtime/shutsujin_launcher.sh"
  [ "$status" -eq 0 ]
}

@test "runtime launchers: Windows wrapper runs shutsujin through Ubuntu WSL and attaches" {
  run grep -F "shogunate_mod\\windows\\runtime_launcher.bat" "$PROJECT_ROOT/Shogunate-Runtime.bat"
  [ "$status" -eq 0 ]

  run grep -F "wsl.exe -d Ubuntu" "$PROJECT_ROOT/shogunate_mod/windows/runtime_launcher.bat"
  [ "$status" -eq 0 ]

  run grep -F "bash shogunate_mod/runtime/runtime_launcher.sh" "$PROJECT_ROOT/shogunate_mod/windows/runtime_launcher.bat"
  [ "$status" -eq 0 ]

  run grep -F "bash ./Shogunate-Runtime.sh" "$PROJECT_ROOT/shogunate_mod/windows/runtime_launcher.bat"
  [ "$status" -ne 0 ]
}

@test "runtime launchers: Windows Shutsujin wrapper opens Goza via Shutsujin, not Runtime" {
  run grep -F "shogunate_mod\\windows\\shutsujin_launcher.bat" "$PROJECT_ROOT/Shutsujin.bat"
  [ "$status" -eq 0 ]

  run grep -F "wsl.exe -d Ubuntu" "$PROJECT_ROOT/shogunate_mod/windows/shutsujin_launcher.bat"
  [ "$status" -eq 0 ]

  run grep -F "bash shogunate_mod/runtime/shutsujin_launcher.sh" "$PROJECT_ROOT/shogunate_mod/windows/shutsujin_launcher.bat"
  [ "$status" -eq 0 ]

  run grep -F "opens a command shell after startup" "$PROJECT_ROOT/shogunate_mod/windows/shutsujin_launcher.bat"
  [ "$status" -eq 0 ]

  run grep -F "Type cgo, CMA, csa, css, cgn, csk" "$PROJECT_ROOT/shogunate_mod/windows/shutsujin_launcher.bat"
  [ "$status" -eq 0 ]

  run grep -F "[1/3]" "$PROJECT_ROOT/Shutsujin.bat"
  [ "$status" -ne 0 ]

  run grep -F "[2/3]" "$PROJECT_ROOT/Shutsujin.bat"
  [ "$status" -ne 0 ]

  run grep -F "[3/3]" "$PROJECT_ROOT/Shutsujin.bat"
  [ "$status" -ne 0 ]

  run grep -F "Shogunate-Runtime.sh" "$PROJECT_ROOT/shogunate_mod/windows/shutsujin_launcher.bat"
  [ "$status" -ne 0 ]

  run grep -F "bash ./Shutsujin.sh" "$PROJECT_ROOT/shogunate_mod/windows/shutsujin_launcher.bat"
  [ "$status" -ne 0 ]
}

@test "runtime launchers: Windows debug wrappers split clean and resume starts" {
  run test -f "$PROJECT_ROOT/Shutsujin-Clean.bat"
  [ "$status" -eq 0 ]

  run test -f "$PROJECT_ROOT/Shutsujin-Resume.bat"
  [ "$status" -eq 0 ]

  run grep -F "shogunate_mod\\windows\\shutsujin_clean.bat" "$PROJECT_ROOT/Shutsujin-Clean.bat"
  [ "$status" -eq 0 ]

  run grep -F "shogunate_mod\\windows\\shutsujin_resume.bat" "$PROJECT_ROOT/Shutsujin-Resume.bat"
  [ "$status" -eq 0 ]

  run grep -F 'call "%REPO_DIR%\shogunate_mod\windows\shutsujin_launcher.bat" --clean %*' "$PROJECT_ROOT/shogunate_mod/windows/shutsujin_clean.bat"
  [ "$status" -eq 0 ]

  run grep -F 'call "%REPO_DIR%\shogunate_mod\windows\shutsujin_launcher.bat" %*' "$PROJECT_ROOT/shogunate_mod/windows/shutsujin_resume.bat"
  [ "$status" -eq 0 ]

  run grep -F 'Shogunate-Runtime' "$PROJECT_ROOT/Shutsujin-Clean.bat" "$PROJECT_ROOT/Shutsujin-Resume.bat"
  [ "$status" -ne 0 ]
}
