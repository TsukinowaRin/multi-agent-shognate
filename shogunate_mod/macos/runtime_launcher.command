#!/usr/bin/env bash
# macOS Finder launcher for Shogunate runtime.

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "$0")/../.." && pwd)"
cd "$SCRIPT_DIR"

if [[ ! -x "shogunate_mod/runtime/runtime_launcher.sh" ]]; then
  echo ""
  echo "  [ERROR] shogunate_mod/runtime/runtime_launcher.sh is missing or not executable."
  echo "          Put this .command file in the Shogunate folder."
  echo ""
  read -r -p "Press Enter to close..."
  exit 1
fi

bash shogunate_mod/runtime/runtime_launcher.sh "$@"

echo ""
read -r -p "Press Enter to close..."
