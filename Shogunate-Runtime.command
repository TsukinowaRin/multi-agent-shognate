#!/usr/bin/env bash
# macOS Finder launcher for Shogunate runtime.

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
cd "$SCRIPT_DIR"

if [[ ! -x "./Shogunate-Runtime.sh" ]]; then
  echo ""
  echo "  [ERROR] Shogunate-Runtime.sh is missing or not executable."
  echo "          Put this .command file in the Shogunate folder."
  echo ""
  read -r -p "Press Enter to close..."
  exit 1
fi

./Shogunate-Runtime.sh "$@"

echo ""
read -r -p "Press Enter to close..."
