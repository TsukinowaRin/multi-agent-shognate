#!/usr/bin/env bash
# Start Shogunate runtime and attach to the Shogunate tmux session.

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)"
CALLER_DIR="$(pwd -P)"
cd "$SCRIPT_DIR"

source "$SCRIPT_DIR/shogunate_mod/runtime/launcher.sh"
shogunate_launcher_init_context "$CALLER_DIR"
CLEAN_ARG="-c"
ATTACH_AFTER=1
EXTRA_ARGS=()

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
    --resume)
      CLEAN_ARG=""
      shift
      ;;
    --clean)
      CLEAN_ARG="-c"
      shift
      ;;
    --no-attach)
      ATTACH_AFTER=0
      shift
      ;;
    -h|--help)
      cat <<'EOF'
Usage: ./Shogunate-Runtime.sh [--clean|--resume] [--no-attach] [shutsujin args...]

Defaults:
  --clean      Start with bash shutsujin_departure.sh -c
  attach       Attach to tmux session shogunate after startup
  project      Use the caller's current directory as the target project

Examples:
  ./Shogunate-Runtime.sh
  ./Shogunate-Runtime.sh --resume
  ./Shogunate-Runtime.sh --project /path/to/project
  ./Shogunate-Runtime.sh --clean --no-attach
EOF
      exit 0
      ;;
    *)
      EXTRA_ARGS+=("$1")
      shift
      ;;
  esac
done

printf '\n'
printf '  %s+============================================================+%s\n' "$C_CYAN" "$C_RESET"
printf '  %s|  %s[SHOGUN]%s multi-agent-shognate - Runtime Launcher          |%s\n' "$C_CYAN" "$C_BOLD" "$C_CYAN" "$C_RESET"
printf '  %s|      Starts Shogunate and opens the runtime session        |%s\n' "$C_CYAN" "$C_RESET"
printf '  %s+============================================================+%s\n\n' "$C_CYAN" "$C_RESET"

shogunate_launcher_require_departure
shogunate_launcher_require_tmux

if [[ -n "$CLEAN_ARG" ]]; then
  info "Mode: clean start"
else
  info "Mode: resume existing state"
fi
info "Target project: $SHOGUNATE_PROJECT_DIR"
info "Runtime root: $SCRIPT_DIR"

if [[ "$ATTACH_AFTER" -eq 1 ]]; then
  mkdir -p queue/runtime
  STARTUP_LOG="queue/runtime/shogunate_runtime_launcher.log"
  : > "$STARTUP_LOG"

  info "Starting runtime in background."
  info "CLI panes will launch after tmux session '$SHOGUNATE_SESSION_NAME' is attached."
  info "Startup log: $STARTUP_LOG"
  RUN_ID="runtime-$(date +%s)-$$"
  if [[ -n "$CLEAN_ARG" ]]; then
    SHOGUNATE_PROJECT_DIR="$SHOGUNATE_PROJECT_DIR" SHOGUNATE_SESSION_NAME="$SHOGUNATE_SESSION_NAME" GOZA_SESSION_NAME="$SHOGUNATE_SESSION_NAME" MAS_WAIT_FOR_GOZA_CLIENT_BEFORE_CLI=1 MAS_GOZA_STARTUP_WINDOW=1 MAS_GOZA_STARTUP_LOG="$STARTUP_LOG" MAS_LAUNCHER_RUN_ID="$RUN_ID" bash shutsujin_departure.sh "$CLEAN_ARG" "${EXTRA_ARGS[@]}" >"$STARTUP_LOG" 2>&1 &
  else
    SHOGUNATE_PROJECT_DIR="$SHOGUNATE_PROJECT_DIR" SHOGUNATE_SESSION_NAME="$SHOGUNATE_SESSION_NAME" GOZA_SESSION_NAME="$SHOGUNATE_SESSION_NAME" MAS_WAIT_FOR_GOZA_CLIENT_BEFORE_CLI=1 MAS_GOZA_STARTUP_WINDOW=1 MAS_GOZA_STARTUP_LOG="$STARTUP_LOG" MAS_LAUNCHER_RUN_ID="$RUN_ID" bash shutsujin_departure.sh "${EXTRA_ARGS[@]}" >"$STARTUP_LOG" 2>&1 &
  fi
  RUNTIME_PID=$!

  for _ in $(seq 1 120); do
    if [[ "$(tmux show-options -t "$SHOGUNATE_SESSION_NAME" -v @mas_launcher_run_id 2>/dev/null || true)" == "$RUN_ID" ]]; then
      break
    fi
    if ! kill -0 "$RUNTIME_PID" 2>/dev/null; then
      echo ""
      err "Runtime exited before '$SHOGUNATE_SESSION_NAME' was created."
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

if [[ -n "$CLEAN_ARG" ]]; then
  SHOGUNATE_PROJECT_DIR="$SHOGUNATE_PROJECT_DIR" bash shutsujin_departure.sh "$CLEAN_ARG" "${EXTRA_ARGS[@]}"
else
  SHOGUNATE_PROJECT_DIR="$SHOGUNATE_PROJECT_DIR" bash shutsujin_departure.sh "${EXTRA_ARGS[@]}"
fi

echo ""
ok "Runtime started. Attach with: tmux attach-session -t $SHOGUNATE_SESSION_NAME"
