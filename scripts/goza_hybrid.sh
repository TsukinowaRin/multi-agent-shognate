#!/usr/bin/env bash
set -euo pipefail

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
cd "$ROOT_DIR"

# ハイブリッドモード（backend=tmux, ui=zellij）
exec bash "$ROOT_DIR/scripts/goza_no_ma.sh" --mux tmux --ui zellij "$@"
