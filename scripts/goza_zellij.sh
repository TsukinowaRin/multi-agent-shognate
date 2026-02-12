#!/usr/bin/env bash
set -euo pipefail

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
cd "$ROOT_DIR"

# 純正zellijモード（backend=zellij, ui=zellij）
exec bash "$ROOT_DIR/scripts/goza_no_ma.sh" --mux zellij --ui zellij "$@"
