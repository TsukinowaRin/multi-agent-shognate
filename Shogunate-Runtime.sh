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
  bash shutsujin_departure.sh "$CLEAN_ARG" "${EXTRA_ARGS[@]}"
else
  echo "  [INFO] Mode: resume existing state"
  bash shutsujin_departure.sh "${EXTRA_ARGS[@]}"
fi

if [[ "$ATTACH_AFTER" -eq 1 ]]; then
  echo ""
  echo "  [INFO] Attaching to goza-no-ma. Detach from tmux with Ctrl+B, then D."
  exec tmux attach-session -t goza-no-ma
fi

echo ""
echo "  [OK] Runtime started. Attach with: tmux attach-session -t goza-no-ma"
