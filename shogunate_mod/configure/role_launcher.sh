#!/usr/bin/env bash
# Shared launcher for Shogunate role configuration.

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)"
cd "$SCRIPT_DIR"

PAUSE_ON_EXIT="${SHOGUNATE_ROLE_CONFIG_PAUSE:-0}"

pause_if_needed() {
  if [[ "$PAUSE_ON_EXIT" == "1" ]]; then
    echo ""
    read -r -p "Press Enter to close..." || true
  fi
}

exit_with_error() {
  local message="$1"
  echo "  [ERROR] $message"
  echo "          Run this launcher from the Shogunate folder."
  pause_if_needed
  exit 1
}

echo ""
echo "  +============================================================+"
echo "  |  [SHOGUN] multi-agent-shognate - Role Configurator         |"
echo "  |      Choose CLI type per role and active ashigaru count     |"
echo "  +============================================================+"
echo ""

if [[ -f "shogunate_mod/configure/runtime_roles.py" ]]; then
  CONFIGURATOR="shogunate_mod/configure/runtime_roles.py"
else
  exit_with_error "role configurator not found."
fi

if python3 "$CONFIGURATOR" "$@"; then
  :
else
  status=$?
  echo ""
  echo "  [ERROR] Role configuration failed with exit code $status."
  pause_if_needed
  exit "$status"
fi

echo ""
echo "  [OK] Role configuration finished."
echo "      Restart runtime with: bash shutsujin_departure.sh -c"
pause_if_needed
