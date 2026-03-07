#!/usr/bin/env bash
set -euo pipefail

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
cd "$ROOT_DIR"

# 純正 zellij モード（experimental）
export MAS_ENABLE_PURE_ZELLIJ=1
exec bash "$ROOT_DIR/scripts/goza_no_ma.sh" --mux zellij --ui zellij "$@"
