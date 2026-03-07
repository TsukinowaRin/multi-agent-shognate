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

TRANSCRIPT_FILE="$ROOT_DIR/queue/runtime/pure_zellij_${SESSION_ID}_${AGENT_ID}.log"
BOOTSTRAP_FILE="$ROOT_DIR/queue/runtime/pure_zellij_${SESSION_ID}_${AGENT_ID}.bootstrap.txt"
META_LOG="$ROOT_DIR/queue/runtime/pure_zellij_${SESSION_ID}_${AGENT_ID}.meta.log"

mkdir -p "$ROOT_DIR/queue/runtime"
: > "$TRANSCRIPT_FILE"
: > "$META_LOG"

log_meta() {
  printf "[%s] %s\n" "$(date -Iseconds)" "$1" >> "$META_LOG"
}

if [[ "${GOZA_SETUP_ONLY:-0}" == "1" ]]; then
  clear || true
  log_meta "setup-only agent=$AGENT_ID"
  exec bash
fi

CLI_TYPE="$(resolve_cli_type_for_agent "$AGENT_ID" 2>/dev/null || get_cli_type "$AGENT_ID")"
STARTUP_PROMPT=""
if [[ -f "$BOOTSTRAP_FILE" ]]; then
  STARTUP_PROMPT="$(cat "$BOOTSTRAP_FILE")"
fi

CLI_CMD="$(build_cli_command_with_startup_prompt "$AGENT_ID" "$CLI_TYPE" "$STARTUP_PROMPT")"
log_meta "launch agent=$AGENT_ID cli=$CLI_TYPE bootstrap_file=$(basename "$BOOTSTRAP_FILE")"

clear || true
if command -v script >/dev/null 2>&1; then
  script -qefc "$CLI_CMD" "$TRANSCRIPT_FILE" || true
else
  bash -lc "$CLI_CMD" 2>&1 | tee -a "$TRANSCRIPT_FILE" || true
fi

log_meta "pane ended agent=$AGENT_ID cli=$CLI_TYPE"
echo "[INFO] ${AGENT_ID} pane ended. Waiting at shell."
exec bash
