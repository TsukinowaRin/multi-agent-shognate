#!/usr/bin/env bash
# macOS Finder launcher for Shogunate role configuration.

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
cd "$SCRIPT_DIR"

echo ""
echo "  +============================================================+"
echo "  |  [SHOGUN] multi-agent-shognate - Role Configurator         |"
echo "  |      Choose CLI type per role and active ashigaru count     |"
echo "  +============================================================+"
echo ""

if [[ ! -f "scripts/configure_runtime_roles.py" ]]; then
  echo "  [ERROR] scripts/configure_runtime_roles.py not found."
  echo "          Put this .command file in the Shogunate folder."
  echo ""
  read -r -p "Press Enter to close..."
  exit 1
fi

python3 scripts/configure_runtime_roles.py "$@"

echo ""
echo "  [OK] Role configuration finished."
echo "      Restart runtime with: bash shutsujin_departure.sh -c"
echo ""
read -r -p "Press Enter to close..."
