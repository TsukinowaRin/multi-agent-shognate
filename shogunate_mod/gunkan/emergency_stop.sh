#!/bin/bash
# Gunkan emergency stop helper.
# Usage: bash shogunate_mod/gunkan/emergency_stop.sh <agent_id> <reason>

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
AGENT_ID="${1:-}"
REASON="${2:-}"
SESSION_NAME="${SHOGUNATE_SESSION_NAME:-shogunate}"
OUT="$SCRIPT_DIR/queue/runtime/gunkan_emergency_stop.yaml"

if [ -z "$AGENT_ID" ] || [ -z "$REASON" ]; then
    echo "Usage: bash shogunate_mod/gunkan/emergency_stop.sh <agent_id> <reason>" >&2
    exit 1
fi

find_agent_pane() {
    local pane
    while IFS= read -r pane; do
        [ -n "$pane" ] || continue
        if [ "$(tmux show-options -p -t "$pane" -v @agent_id 2>/dev/null || true)" = "$AGENT_ID" ]; then
            printf '%s\n' "$pane"
            return 0
        fi
    done < <(tmux list-panes -s -t "$SESSION_NAME" -F '#{pane_id}' 2>/dev/null || true)
    return 1
}

PANE_TARGET="$(find_agent_pane || true)"
STATUS="pane_not_found"
if [ -n "$PANE_TARGET" ]; then
    if tmux send-keys -t "$PANE_TARGET" C-c 2>/dev/null; then
        STATUS="interrupted"
    else
        STATUS="interrupt_failed"
    fi
fi

mkdir -p "$(dirname "$OUT")"
python3 - "$OUT" "$AGENT_ID" "$REASON" "$STATUS" "$PANE_TARGET" <<'PY'
import os
import sys
import tempfile
from datetime import datetime

import yaml

out, agent_id, reason, status, pane_target = sys.argv[1:]
try:
    with open(out, encoding="utf-8") as f:
        data = yaml.safe_load(f) or {}
except FileNotFoundError:
    data = {}

events = data.setdefault("events", [])
events.append(
    {
        "timestamp": datetime.now().astimezone().isoformat(timespec="seconds"),
        "agent_id": agent_id,
        "reason": reason,
        "status": status,
        "pane_target": pane_target,
    }
)
data["latest"] = events[-1]

fd, tmp = tempfile.mkstemp(dir=os.path.dirname(out), suffix=".tmp")
try:
    with os.fdopen(fd, "w", encoding="utf-8") as f:
        yaml.safe_dump(data, f, allow_unicode=True, sort_keys=False)
    os.replace(tmp, out)
except Exception:
    os.unlink(tmp)
    raise
PY

if [ -f "$SCRIPT_DIR/shogunate_mod/inbox/write.sh" ]; then
    bash "$SCRIPT_DIR/shogunate_mod/inbox/write.sh" shogun "軍監、${AGENT_ID} を緊急停止処理。status=${STATUS} reason=${REASON}" emergency_stop_report gunkan >/dev/null 2>&1 || true
fi

echo "$STATUS"
