#!/usr/bin/env bash
# Start Shogunate with shutsujin_departure.sh, then leave an alias-ready shell.

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
cd "$SCRIPT_DIR"

OPEN_SHELL=1
SHUTSUJIN_ARGS=()

while [[ $# -gt 0 ]]; do
  case "$1" in
    --no-shell|--no-attach)
      OPEN_SHELL=0
      shift
      ;;
    -h|--help)
      cat <<'EOF'
Usage: ./Shutsujin.sh [--no-shell|--no-attach] [shutsujin_departure.sh args...]

Starts Shogunate with shutsujin_departure.sh without auto-attaching to Goza.
After startup, it opens an interactive shell with view aliases loaded:

  cgo / CGO  Goza View
  csa / CSA  Ashigaru View
  cma / CMA  Multiagent View
  css / CSS  Shogun pane
  csg / CSG  Gunshi pane
  csm / CSM  Karo pane

Use Shogunate-Runtime.sh when you want one-click auto Goza attach.
EOF
      exit 0
      ;;
    *)
      SHUTSUJIN_ARGS+=("$1")
      shift
      ;;
  esac
done

echo ""
echo "  +============================================================+"
echo "  |  [SHOGUN] multi-agent-shognate - Shutsujin Launcher        |"
echo "  |      Starts shutsujin; choose views manually with cgo/csa   |"
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

echo "  [INFO] Starting: bash shutsujin_departure.sh ${SHUTSUJIN_ARGS[*]}"
bash shutsujin_departure.sh "${SHUTSUJIN_ARGS[@]}"

echo ""
echo "  [OK] Shutsujin finished."
echo "  [INFO] View commands are available in the next shell:"
echo "        cgo/CGO = Goza View, csa/CSA = Ashigaru View, cma/CMA = Multiagent View"
echo "        css/CSS = Shogun, csg/CSG = Gunshi, csm/CSM = Karo"
echo ""

if [[ "$OPEN_SHELL" -ne 1 ]]; then
  exit 0
fi

exec bash --rcfile <(
  printf '[[ -f ~/.bashrc ]] && source ~/.bashrc\n'
  printf 'source %q/scripts/shell_aliases.sh\n' "$SCRIPT_DIR"
  printf 'cd %q\n' "$SCRIPT_DIR"
  printf 'echo "[Shogunate] Type cgo/CGO for Goza View, csa/CSA for Ashigaru View."\n'
) -i
