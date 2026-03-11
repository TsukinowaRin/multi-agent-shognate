#!/usr/bin/env bash
set -euo pipefail

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
cd "$ROOT_DIR"

# 既定の zellij 運用は安定優先: zellij UI + tmux backend
exec bash "$ROOT_DIR/scripts/goza_no_ma.sh" --mux tmux --ui zellij "$@"
