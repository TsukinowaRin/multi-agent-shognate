#!/bin/bash
# shogunate_mod/app/reply.sh — append a role reply to an app chat transcript
# Usage: bash shogunate_mod/app/reply.sh [--type <type>] <session_id> <from_role> <reply_text>

set -e

MOD_APP_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
SCRIPT_DIR="$(cd "$MOD_APP_DIR/../.." && pwd)"
TYPE="role_message"

if [ "${1:-}" = "--type" ]; then
    if [ -z "${2:-}" ]; then
        echo "Usage: bash shogunate_mod/app/reply.sh [--type <type>] <session_id> <from_role> <reply_text>" >&2
        exit 1
    fi
    TYPE="$2"
    shift 2
fi

SESSION_ID="${1:-}"
FROM_ROLE="${2:-}"
REPLY_TEXT="${3:-}"

if [ -z "$SESSION_ID" ] || [ -z "$FROM_ROLE" ] || [ -z "$REPLY_TEXT" ]; then
    echo "Usage: bash shogunate_mod/app/reply.sh [--type <type>] <session_id> <from_role> <reply_text>" >&2
    exit 1
fi

SESSION_DIR="$SCRIPT_DIR/queue/app/sessions/$SESSION_ID"
TRANSCRIPT="$SESSION_DIR/messages.jsonl"
LOCKFILE="${TRANSCRIPT}.lock"

if [ ! -d "$SESSION_DIR" ]; then
    echo "[app_reply] ERROR: app session not found: $SESSION_ID ($SESSION_DIR)" >&2
    exit 1
fi

append_reply_message() {
    python3 - "$TRANSCRIPT" "$FROM_ROLE" "$TYPE" "$REPLY_TEXT" <<'PY'
import json
import sys
import time

transcript_path, from_role, message_type, reply_text = sys.argv[1:]

entry = {
    "id": f"msg-{time.time_ns()}",
    "time": time.strftime("%Y-%m-%dT%H:%M:%S%z"),
    "from": from_role,
    "to": "lord",
    "type": message_type,
    "content": reply_text,
}

with open(transcript_path, "a", encoding="utf-8") as handle:
    handle.write(json.dumps(entry, ensure_ascii=False) + "\n")
PY
}

write_with_lock() {
    if command -v flock >/dev/null 2>&1; then
        (
            flock -w 5 200 || exit 1
            append_reply_message
        ) 200>"$LOCKFILE"
        return $?
    fi

    local lockdir="${LOCKFILE}.d"
    local status=0
    local lock_attempt=0
    while ! mkdir "$lockdir" 2>/dev/null; do
        lock_attempt=$((lock_attempt + 1))
        [ "$lock_attempt" -lt 50 ] || return 1
        sleep 0.1
    done
    append_reply_message || status=$?
    rmdir "$lockdir" 2>/dev/null || true
    return "$status"
}

attempt=0
max_attempts=3

while [ $attempt -lt $max_attempts ]; do
    if write_with_lock; then
        exit 0
    fi

    attempt=$((attempt + 1))
    if [ $attempt -lt $max_attempts ]; then
        echo "[app_reply] Lock timeout for $TRANSCRIPT (attempt $attempt/$max_attempts), retrying..." >&2
        sleep 1
    else
        echo "[app_reply] Failed to acquire lock after $max_attempts attempts for $TRANSCRIPT" >&2
        exit 1
    fi
done
