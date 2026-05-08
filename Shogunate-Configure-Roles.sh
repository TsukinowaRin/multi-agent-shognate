#!/usr/bin/env bash
# Configure Shogunate role CLI types and active ashigaru count.

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
cd "$SCRIPT_DIR"

echo ""
echo "  +============================================================+"
echo "  |  [SHOGUN] multi-agent-shognate - Role Configurator         |"
echo "  |      Choose CLI type per role and active ashigaru count     |"
echo "  +============================================================+"
echo ""

if [[ ! -f "scripts/configure_runtime_roles.py" ]]; then
  echo "  [ERROR] scripts/configure_runtime_roles.py not found."
  echo "          Run this launcher from the Shogunate folder."
  exit 1
fi

python3 scripts/configure_runtime_roles.py "$@"

echo ""
echo "  [OK] Role configuration finished."
echo "      Restart runtime with: bash shutsujin_departure.sh -c"
