#!/usr/bin/env bash

set -euo pipefail

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
cd "$ROOT_DIR"

AGENT_ID="${1:-${AGENT_ID:-}}"
SESSION_ID="${2:-${ZELLIJ_UI_SESSION:-goza-no-ma-ui}}"

if [[ -z "$AGENT_ID" ]]; then
  echo "[ERROR] AGENT_ID is required" >&2
  exit 1
fi

# shellcheck source=/dev/null
source "$ROOT_DIR/lib/cli_adapter.sh"

DISPLAY_MODE="${DISPLAY_MODE:-shout}"
export AGENT_ID DISPLAY_MODE
export MAS_CLI_COL_MULTIPLIER="${MAS_CLI_COL_MULTIPLIER:-2}"

TRANSCRIPT_FILE="$ROOT_DIR/queue/runtime/pure_zellij_${SESSION_ID}_${AGENT_ID}.log"
BOOTSTRAP_FILE="$ROOT_DIR/queue/runtime/pure_zellij_${SESSION_ID}_${AGENT_ID}.bootstrap.txt"
META_LOG="$ROOT_DIR/queue/runtime/pure_zellij_${SESSION_ID}_${AGENT_ID}.meta.log"

mkdir -p "$ROOT_DIR/queue/runtime"
: > "$TRANSCRIPT_FILE"
: > "$META_LOG"

log_meta() {
  printf "[%s] %s\n" "$(date -Iseconds)" "$1" >> "$META_LOG"
}

if [[ "${GOZA_SETUP_ONLY:-0}" == "1" || "${GOZA_SETUP_ONLY:-}" == "true" ]]; then
  clear || true
  log_meta "setup-only agent=$AGENT_ID"
  exec bash
fi

CLI_TYPE="$(resolve_cli_type_for_agent "$AGENT_ID" 2>/dev/null || get_cli_type "$AGENT_ID")"
CLI_CMD="$(build_cli_command_with_type "$AGENT_ID" "$CLI_TYPE")"
log_meta "launch agent=$AGENT_ID cli=$CLI_TYPE bootstrap_file=$(basename "$BOOTSTRAP_FILE")"

clear || true
python3 "$ROOT_DIR/scripts/interactive_agent_runner.py" \
  --root "$ROOT_DIR" \
  --agent "$AGENT_ID" \
  --cli "$CLI_TYPE" \
  --command "$CLI_CMD" \
  --transcript "$TRANSCRIPT_FILE" \
  --meta "$META_LOG" \
  --bootstrap "$BOOTSTRAP_FILE" || true

log_meta "pane ended agent=$AGENT_ID cli=$CLI_TYPE"
echo "[INFO] ${AGENT_ID} pane ended. Waiting at shell."
exec bash
