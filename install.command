#!/usr/bin/env bash
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
cd "$SCRIPT_DIR"

if [ ! -x "$SCRIPT_DIR/install.sh" ]; then
    chmod +x "$SCRIPT_DIR/install.sh" 2>/dev/null || true
fi

"$SCRIPT_DIR/install.sh"

printf '\nPress Enter to close this window... '
IFS= read -r _ || true
