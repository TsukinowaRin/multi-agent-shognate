#!/usr/bin/env bash
# Compatibility setup entrypoint. Historical setup.sh now delegates here.

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)"
exec bash "$SCRIPT_DIR/shutsujin_departure.sh" "$@"
