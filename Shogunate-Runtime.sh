#!/usr/bin/env bash
# Start Shogunate runtime and attach to goza-no-ma.

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
cd "$SCRIPT_DIR"

CLEAN_ARG="-c"
ATTACH_AFTER=1
EXTRA_ARGS=()

while [[ $# -gt 0 ]]; do
  case "$1" in
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
  attach       Attach to tmux session goza-no-ma after startup

Examples:
  ./Shogunate-Runtime.sh
  ./Shogunate-Runtime.sh --resume
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

echo ""
echo "  +============================================================+"
echo "  |  [SHOGUN] multi-agent-shognate - Runtime Launcher          |"
echo "  |      Starts Shogunate and opens goza-no-ma                 |"
echo "  +============================================================+"
echo ""

if [[ ! -f "shutsujin_departure.sh" ]]; then
  echo "  [ERROR] shutsujin_departure.sh not found."
  echo "          Run this launcher from the Shogunate folder."
  exit 1
fi

if ! command -v tmux >/dev/null 2>&1; then
  echo "  [ERROR] tmux is not installed or not on PATH."
  exit 1
fi

if [[ -n "$CLEAN_ARG" ]]; then
  echo "  [INFO] Mode: clean start"
else
  echo "  [INFO] Mode: resume existing state"
fi

if [[ "$ATTACH_AFTER" -eq 1 ]]; then
  mkdir -p queue/runtime
  STARTUP_LOG="queue/runtime/shogunate_runtime_launcher.log"
  : > "$STARTUP_LOG"

  echo "  [INFO] Starting runtime in background."
  echo "  [INFO] CLI panes will launch after goza-no-ma is attached."
  echo "  [INFO] Startup log: $STARTUP_LOG"
  RUN_ID="runtime-$(date +%s)-$$"
  if [[ -n "$CLEAN_ARG" ]]; then
    MAS_WAIT_FOR_GOZA_CLIENT_BEFORE_CLI=1 MAS_GOZA_STARTUP_WINDOW=1 MAS_GOZA_STARTUP_LOG="$STARTUP_LOG" MAS_LAUNCHER_RUN_ID="$RUN_ID" bash shutsujin_departure.sh "$CLEAN_ARG" "${EXTRA_ARGS[@]}" >"$STARTUP_LOG" 2>&1 &
  else
    MAS_WAIT_FOR_GOZA_CLIENT_BEFORE_CLI=1 MAS_GOZA_STARTUP_WINDOW=1 MAS_GOZA_STARTUP_LOG="$STARTUP_LOG" MAS_LAUNCHER_RUN_ID="$RUN_ID" bash shutsujin_departure.sh "${EXTRA_ARGS[@]}" >"$STARTUP_LOG" 2>&1 &
  fi
  RUNTIME_PID=$!

  for _ in $(seq 1 120); do
    if [[ "$(tmux show-options -t goza-no-ma -v @mas_launcher_run_id 2>/dev/null || true)" == "$RUN_ID" ]]; then
      break
    fi
    if ! kill -0 "$RUNTIME_PID" 2>/dev/null; then
      echo ""
      echo "  [ERROR] Runtime exited before goza-no-ma was created."
      echo "  ----- $STARTUP_LOG -----"
      tail -120 "$STARTUP_LOG" 2>/dev/null || true
      exit 1
    fi
    sleep 1
  done

  if [[ "$(tmux show-options -t goza-no-ma -v @mas_launcher_run_id 2>/dev/null || true)" != "$RUN_ID" ]]; then
    echo ""
    echo "  [ERROR] Timed out waiting for goza-no-ma."
    echo "  ----- $STARTUP_LOG -----"
    tail -120 "$STARTUP_LOG" 2>/dev/null || true
    exit 1
  fi

  echo ""
  echo "  [INFO] Attaching to goza-no-ma. CLI launch continues inside tmux."
  echo "  [INFO] Detach from tmux with Ctrl+B, then D."
  disown "$RUNTIME_PID" 2>/dev/null || true
  exec tmux attach-session -t goza-no-ma
fi

if [[ -n "$CLEAN_ARG" ]]; then
  bash shutsujin_departure.sh "$CLEAN_ARG" "${EXTRA_ARGS[@]}"
else
  bash shutsujin_departure.sh "${EXTRA_ARGS[@]}"
fi

echo ""
echo "  [OK] Runtime started. Attach with: tmux attach-session -t goza-no-ma"
