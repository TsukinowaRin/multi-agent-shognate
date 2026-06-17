#!/usr/bin/env bash
# Start Shogunate with shutsujin_departure.sh and attach before CLI launch.

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)"
CALLER_DIR="$(pwd -P)"
cd "$SCRIPT_DIR"

source "$SCRIPT_DIR/shogunate_mod/runtime/launcher.sh"
shogunate_launcher_init_context "$CALLER_DIR"
ATTACH_AFTER=1
OPEN_SHELL=1
SHUTSUJIN_ARGS=()

while [[ $# -gt 0 ]]; do
  case "$1" in
    --project)
      SHOGUNATE_PROJECT_DIR="$(shogunate_launcher_resolve_project_dir "${2:-}")"
      shift 2
      ;;
    --project=*)
      SHOGUNATE_PROJECT_DIR="$(shogunate_launcher_resolve_project_dir "${1#--project=}")"
      shift
      ;;
    --no-attach)
      ATTACH_AFTER=0
      shift
      ;;
    --no-shell)
      ATTACH_AFTER=0
      OPEN_SHELL=0
      shift
      ;;
    -h|--help)
      cat <<'EOF'
Usage: ./Shutsujin.sh [--clean|--resume] [--no-attach] [--no-shell] [shutsujin_departure.sh args...]

Starts Shogunate with shutsujin_departure.sh, attaches before agent CLIs launch,
then opens an alias-ready command shell after startup.

Pass --clean to recreate tmux sessions and reset runtime queues. Without
--clean, Shutsujin resumes or recreates according to shutsujin_departure.sh.

Use --no-attach when you want the old pre-attach manual shell workflow. Add
--no-shell to skip that shell:

Use --project DIR to target a project directory explicitly. Without it,
Shutsujin uses the caller's current directory.

  cgo / CGO  Goza View
  csa / CSA  Ashigaru View
  csm / CSM  Multiagent View
  cma / CMA  Multiagent View
  css / CSS  Shogun pane
  cgn / CGN  Gunkan pane
  csg / CSG  Gunshi pane
  csk / CSK  Karo pane
  ckr / CKR  Karo pane

EOF
      exit 0
      ;;
    *)
      SHUTSUJIN_ARGS+=("$1")
      shift
      ;;
  esac
done

printf '\n'
printf '  %s+============================================================+%s\n' "$C_CYAN" "$C_RESET"
printf '  %s|  %s[SHOGUN]%s multi-agent-shognate - Shutsujin Launcher        |%s\n' "$C_CYAN" "$C_BOLD" "$C_CYAN" "$C_RESET"
printf '  %s|      Starts agents, then opens cgo/CMA command shell        |%s\n' "$C_CYAN" "$C_RESET"
printf '  %s+============================================================+%s\n\n' "$C_CYAN" "$C_RESET"

shogunate_launcher_require_departure
shogunate_launcher_require_tmux

if [[ "$ATTACH_AFTER" -eq 1 ]]; then
  mkdir -p queue/runtime
  STARTUP_LOG="queue/runtime/shogunate_shutsujin_launcher.log"
  : > "$STARTUP_LOG"

  info "Starting Shutsujin in background."
  info "Target project: $SHOGUNATE_PROJECT_DIR"
  info "Runtime root: $SCRIPT_DIR"
  info "CLI panes will launch after tmux session '$SHOGUNATE_SESSION_NAME' is attached."
  info "After startup, type cgo/CMA/csa/css/cgn/csk in the command shell."
  info "Startup log: $STARTUP_LOG"
  RUN_ID="shutsujin-$(date +%s)-$$"
  SHOGUNATE_PROJECT_DIR="$SHOGUNATE_PROJECT_DIR" SHOGUNATE_SESSION_NAME="$SHOGUNATE_SESSION_NAME" GOZA_SESSION_NAME="$SHOGUNATE_SESSION_NAME" MAS_WAIT_FOR_GOZA_CLIENT_BEFORE_CLI=1 MAS_GOZA_STARTUP_WINDOW=1 MAS_GOZA_STARTUP_LOG="$STARTUP_LOG" MAS_GOZA_FINISH_TARGET=command MAS_LAUNCHER_RUN_ID="$RUN_ID" bash shutsujin_departure.sh "${SHUTSUJIN_ARGS[@]}" >"$STARTUP_LOG" 2>&1 &
  RUNTIME_PID=$!

  for _ in $(seq 1 120); do
    if [[ "$(tmux show-options -t "$SHOGUNATE_SESSION_NAME" -v @mas_launcher_run_id 2>/dev/null || true)" == "$RUN_ID" ]]; then
      break
    fi
    if ! kill -0 "$RUNTIME_PID" 2>/dev/null; then
      echo ""
      err "Shutsujin exited before '$SHOGUNATE_SESSION_NAME' was created."
      echo "  ----- $STARTUP_LOG -----"
      tail -120 "$STARTUP_LOG" 2>/dev/null || true
      exit 1
    fi
    sleep 1
  done

  if [[ "$(tmux show-options -t "$SHOGUNATE_SESSION_NAME" -v @mas_launcher_run_id 2>/dev/null || true)" != "$RUN_ID" ]]; then
    echo ""
    err "Timed out waiting for '$SHOGUNATE_SESSION_NAME'."
    echo "  ----- $STARTUP_LOG -----"
    tail -120 "$STARTUP_LOG" 2>/dev/null || true
    exit 1
  fi

  echo ""
  info "Attaching to $SHOGUNATE_SESSION_NAME. CLI launch continues inside tmux."
  info "Detach from tmux with Ctrl+B, then D."
  disown "$RUNTIME_PID" 2>/dev/null || true
  exec tmux attach-session -t "$SHOGUNATE_SESSION_NAME"
fi

info "Starting without auto attach: bash shutsujin_departure.sh ${SHUTSUJIN_ARGS[*]}"
SHOGUNATE_PROJECT_DIR="$SHOGUNATE_PROJECT_DIR" bash shutsujin_departure.sh "${SHUTSUJIN_ARGS[@]}"

echo ""
ok "Shutsujin finished."
info "View commands are available in the next shell:"
echo "        cgo/CGO = Goza View, csa/CSA = Ashigaru View"
echo "        css/CSS = Shogun, csm/CSM = Multiagent, cma/CMA = Multiagent"
echo "        cgn/CGN = Gunkan, csg/CSG = Gunshi, csk/CSK or ckr/CKR = Karo"
echo ""

if [[ "$OPEN_SHELL" -ne 1 ]]; then
  exit 0
fi

exec bash --rcfile <(
  printf '[[ -f ~/.bashrc ]] && source ~/.bashrc\n'
  if declare -F shogunate_mod_shell_aliases_path >/dev/null 2>&1; then
    printf 'source %q\n' "$(shogunate_mod_shell_aliases_path "$SCRIPT_DIR")"
  else
    printf 'source %q/scripts/shell_aliases.sh\n' "$SCRIPT_DIR"
  fi
  printf 'cd %q\n' "$SHOGUNATE_PROJECT_DIR"
  printf 'echo "[Shogunate] Type cgo/CGO for Goza, csa/CSA for Ashigaru, csm/CSM for Multiagent."\n'
) -i
