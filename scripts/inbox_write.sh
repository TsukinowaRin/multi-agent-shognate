#!/bin/bash
# Compatibility wrapper for the Shogunate MOD inbox writer.
set -e

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
exec bash "$SCRIPT_DIR/shogunate_mod/inbox/write.sh" "$@"
