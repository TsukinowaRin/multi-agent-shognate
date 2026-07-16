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

@test "runtime launchers: daemon watchers are started before bootstrap delivery" {
  run grep -n "launch_all_agent_clis_tmux" "$PROJECT_ROOT/shogunate_mod/runtime/departure.sh"
  [ "$status" -eq 0 ]
  launch_line="${output%%:*}"

  run grep -n "ensure_runtime_daemons_for_bootstrap" "$PROJECT_ROOT/shogunate_mod/runtime/departure.sh"
  [ "$status" -eq 0 ]
  daemon_line="${output%%:*}"

  run grep -n "run_startup_bootstrap_delivery_flow" "$PROJECT_ROOT/shogunate_mod/runtime/departure.sh"
  [ "$status" -eq 0 ]
  bootstrap_line="${output%%:*}"

  [ "$launch_line" -lt "$daemon_line" ]
  [ "$daemon_line" -lt "$bootstrap_line" ]

  run grep -F "restart_tmux_runtime_daemon_session" "$PROJECT_ROOT/shogunate_mod/runtime/daemon.sh"
  [ "$status" -eq 0 ]
}

@test "runtime launchers: role failover exports generation, reports exit, and starts monitor" {
  run bash -n "$PROJECT_ROOT/shogunate_mod/runtime/role_failover_runner.sh"
  [ "$status" -eq 0 ]
  run bash -n "$PROJECT_ROOT/shogunate_mod/runtime/launch.sh"
  [ "$status" -eq 0 ]
  run grep -F 'SHOGUNATE_ROLE_GENERATION' "$PROJECT_ROOT/shogunate_mod/runtime/launch.sh"
  [ "$status" -eq 0 ]
  run grep -F 'role_failover_runner.sh' "$PROJECT_ROOT/shogunate_mod/runtime/launch.sh"
  [ "$status" -eq 0 ]
  run grep -F 'initialize_role_failover_state' "$PROJECT_ROOT/shogunate_mod/runtime/launch.sh"
  [ "$status" -eq 0 ]
  run grep -F 'ensure_role_failover_daemon_started' "$PROJECT_ROOT/shogunate_mod/runtime/daemon.sh"
  [ "$status" -eq 0 ]
  run grep -F 'monitor-candidates' "$PROJECT_ROOT/shogunate_mod/runtime/role_failover_runner.sh"
  [ "$status" -eq 0 ]
}

@test "runtime launchers: intentional stop marker is separate from crash recovery" {
  run grep -F 'queue/runtime/intentional_stop' "$PROJECT_ROOT/shogunate_mod/runtime/departure.sh"
  [ "$status" -eq 0 ]
  run grep -F 'intentional_stop' "$PROJECT_ROOT/shogunate_mod/runtime/launch.sh"
  [ "$status" -eq 0 ]
  run grep -F 'process_exit' "$PROJECT_ROOT/shogunate_mod/runtime/launch.sh"
  [ "$status" -eq 0 ]
}

@test "runtime launchers: failover-enabled watchers do not use legacy direct restart" {
  run grep -F 'role_failover_runner.sh' "$PROJECT_ROOT/shogunate_mod/watcher/supervisor.sh"
  [ "$status" -eq 0 ]
  run grep -F 'role_failover_runner.sh' "$PROJECT_ROOT/shogunate_mod/watcher/inbox_watcher.sh"
  [ "$status" -eq 0 ]
  run grep -F 'role_exit_reported_generation' "$PROJECT_ROOT/shogunate_mod/watcher/supervisor.sh"
  [ "$status" -eq 0 ]
  run grep -F 'role_exit_reported_generation' "$PROJECT_ROOT/shogunate_mod/watcher/inbox_watcher.sh"
  [ "$status" -eq 0 ]
}

@test "runtime launchers: fixed runner performs one Primary restart then Fallback" {
  tmp="$(mktemp -d)"
  mkdir -p "$tmp/shogunate_mod/runtime" "$tmp/config" "$tmp/queue/runtime" "$tmp/bin"
  cp "$PROJECT_ROOT/shogunate_mod/runtime/role_failover.py" "$tmp/shogunate_mod/runtime/role_failover.py"
  cp "$PROJECT_ROOT/shogunate_mod/runtime/role_failover_runner.sh" "$tmp/shogunate_mod/runtime/role_failover_runner.sh"
  printf '#!/usr/bin/env bash\nexit 0\n' > "$tmp/queue/runtime/launch_karo.sh"
  cat > "$tmp/config/settings.yaml" <<'YAML'
cli:
  agents:
    karo:
      type: codex
      fallback:
        type: opencode
YAML
  cat > "$tmp/bin/tmux" <<'SH'
#!/usr/bin/env bash
printf '%s\n' "$*" >> "$TMUX_LOG"
exit 0
SH
  chmod +x "$tmp/bin/tmux"
  python3 "$tmp/shogunate_mod/runtime/role_failover.py" --root "$tmp" init-role --role karo --event-id init --settings "$tmp/config/settings.yaml" --reset >/dev/null

  run env PATH="$tmp/bin:$PATH" TMUX_LOG="$tmp/tmux.log" SHOGUNATE_RUNTIME_DIR="$tmp" SHOGUNATE_ROLE_RESTART_COOLDOWN_SECONDS=0 \
    bash "$tmp/shogunate_mod/runtime/role_failover_runner.sh" process_exit karo 1 process_exit %1
  [ "$status" -eq 0 ]
  run grep -F 'respawn-pane -k -t %1' "$tmp/tmux.log"
  [ "$status" -eq 0 ]
  run python3 - "$tmp/queue/runtime/role_failover.yaml" <<'PY'
import sys, yaml
r = yaml.safe_load(open(sys.argv[1], encoding="utf-8"))["roles"]["karo"]
assert r["generation"] == 2 and r["active_slot"] == "primary"
PY
  [ "$status" -eq 0 ]

  run env PATH="$tmp/bin:$PATH" TMUX_LOG="$tmp/tmux.log" SHOGUNATE_RUNTIME_DIR="$tmp" SHOGUNATE_ROLE_RESTART_COOLDOWN_SECONDS=0 \
    bash "$tmp/shogunate_mod/runtime/role_failover_runner.sh" process_exit karo 2 process_exit %1
  [ "$status" -eq 0 ]
  run python3 - "$tmp/queue/runtime/role_failover.yaml" <<'PY'
import sys, yaml
r = yaml.safe_load(open(sys.argv[1], encoding="utf-8"))["roles"]["karo"]
assert r["generation"] == 3 and r["active_slot"] == "fallback"
PY
  [ "$status" -eq 0 ]
  run env PATH="$tmp/bin:$PATH" TMUX_LOG="$tmp/tmux.log" SHOGUNATE_RUNTIME_DIR="$tmp" SHOGUNATE_ROLE_RESTART_COOLDOWN_SECONDS=0 \
    bash "$tmp/shogunate_mod/runtime/role_failover_runner.sh" primary_recovered karo 3 primary_recovered %1
  [ "$status" -eq 0 ]
  run python3 - "$tmp/queue/runtime/role_failover.yaml" <<'PY'
import sys, yaml
r = yaml.safe_load(open(sys.argv[1], encoding="utf-8"))["roles"]["karo"]
assert r["generation"] == 4 and r["active_slot"] == "primary"
PY
  [ "$status" -eq 0 ]
  rm -rf "$tmp"
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
