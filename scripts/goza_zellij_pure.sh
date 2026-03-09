#!/usr/bin/env bash
set -euo pipefail

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
cd "$ROOT_DIR"

SETUP_ONLY=0
EXPLICIT_SESSION=0
for arg in "$@"; do
  case "$arg" in
    -s|--setup-only)
      SETUP_ONLY=1
      ;;
    --session)
      EXPLICIT_SESSION=1
      ;;
  esac
done

# 純正 zellij モード（experimental）
export MAS_ENABLE_PURE_ZELLIJ=1
if [[ "$SETUP_ONLY" -eq 1 && "$EXPLICIT_SESSION" -eq 0 && -z "${ZELLIJ_UI_SESSION:-}" ]]; then
  # setup-only で通常起動用 session を汚染しないよう、専用 session 名を使う
  export ZELLIJ_UI_SESSION="goza-no-ma-ui-setup"
fi
exec bash "$ROOT_DIR/scripts/goza_no_ma.sh" --mux zellij --ui zellij "$@"
