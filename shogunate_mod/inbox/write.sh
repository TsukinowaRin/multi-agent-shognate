#!/bin/bash
# shogunate_mod/inbox/write.sh — メールボックスへのメッセージ書き込み（排他ロック付き）
# Usage: bash shogunate_mod/inbox/write.sh <target_agent> <content> <type> <from>
# Example: bash shogunate_mod/inbox/write.sh karo "足軽5号、任務完了" report_received ashigaru5

set -e

MOD_INBOX_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
SCRIPT_DIR="$(cd "$MOD_INBOX_DIR/../.." && pwd)"
TARGET="${1:-}"
CONTENT="${2:-}"
TYPE="${3:-}"
FROM="${4:-}"
OWNER_MAP="$SCRIPT_DIR/queue/runtime/ashigaru_owner.tsv"
FAILOVER_STATE="$SCRIPT_DIR/queue/runtime/role_failover.yaml"
FAILOVER_CONTROLLER="$SCRIPT_DIR/shogunate_mod/runtime/role_failover.py"
MESSAGE_GENERATION="${SHOGUNATE_ROLE_GENERATION:-${MAS_ROLE_GENERATION:-}}"

INBOX="$SCRIPT_DIR/queue/inbox/${TARGET}.yaml"
LOCKFILE="${INBOX}.lock"
INBOX_DIR="$(dirname "$INBOX")"

# Validate arguments
if [ -z "$TARGET" ] || [ -z "$CONTENT" ] || [ -z "$TYPE" ] || [ -z "$FROM" ]; then
    echo "Usage: bash shogunate_mod/inbox/write.sh <target_agent> <content> <type> <from>" >&2
    exit 1
fi

# Self-send guard: reject messages where sender == target.
if [ "$FROM" = "$TARGET" ]; then
    echo "[inbox_write] REJECTED: self-send detected (from=$FROM, target=$TARGET)" >&2
    exit 1
fi

is_karo_agent() {
    local agent="$1"
    [[ "$agent" == "karo" || "$agent" == "karo_gashira" || "$agent" =~ ^karo[1-9][0-9]*$ ]]
}

is_ashigaru_agent() {
    local agent="$1"
    [[ "$agent" =~ ^ashigaru[1-9][0-9]*$ ]]
}

lookup_owner_karo() {
    local ashigaru="$1"
    [ -f "$OWNER_MAP" ] || return 1
    awk -F '\t' -v id="$ashigaru" '$1==id {print $2; found=1; exit} END{if(!found) exit 1}' "$OWNER_MAP"
}

validate_route_policy() {
    local owner=""
    # 家老同士の自由な直接通信は禁止。構造化 coordination board の wake-up notice だけ許可。
    if is_karo_agent "$FROM" && is_karo_agent "$TARGET" && [ "$FROM" != "$TARGET" ]; then
        case "$TYPE" in
            coordination_notice|dependency_notice|conflict_notice|handoff_request|merge_request|status_sync)
                ;;
            *)
                echo "[inbox_write] route rejected: karo-to-karo free direct communication is forbidden ($FROM -> $TARGET, type=$TYPE). Use queue/runtime/karo_coordination.yaml plus coordination_notice." >&2
                return 1
                ;;
        esac
    fi

    # 足軽→家老は担当固定（owner map がある場合）
    if is_ashigaru_agent "$FROM" && is_karo_agent "$TARGET"; then
        owner="$(lookup_owner_karo "$FROM" 2>/dev/null || true)"
        if [ -n "$owner" ]; then
            if [ "$TARGET" != "$owner" ]; then
                echo "[inbox_write] route rejected: $FROM is owned by $owner, cannot send to $TARGET" >&2
                return 1
            fi
        elif [ -f "$OWNER_MAP" ] && [ "$TARGET" != "karo" ]; then
            # 互換性維持: owner不明時は単一家老(karo)のみ許容
            echo "[inbox_write] route rejected: owner missing for $FROM in $OWNER_MAP" >&2
            return 1
        fi
    fi

    return 0
}

validate_route_policy

if [[ "$FROM" =~ ^(shogun|gunkan|gunshi|karo([1-9][0-9]*)?|ashigaru[1-9][0-9]*)$ ]] && [ -f "$FAILOVER_STATE" ]; then
    if ! [[ "$MESSAGE_GENERATION" =~ ^[1-9][0-9]*$ ]]; then
        echo "[inbox_write] REJECTED: generation is required for managed sender $FROM" >&2
        exit 1
    fi
    if ! python3 "$FAILOVER_CONTROLLER" --root "$SCRIPT_DIR" validate-write \
        --role "$FROM" --expected-generation "$MESSAGE_GENERATION" >/dev/null; then
        echo "[inbox_write] REJECTED: stale or stopped generation (from=$FROM, generation=$MESSAGE_GENERATION)" >&2
        exit 1
    fi
fi

# Initialize inbox if not exists
if [ ! -f "$INBOX" ]; then
    if [ -f "$INBOX_DIR" ] && [ ! -d "$INBOX_DIR" ]; then
        rm -f "$INBOX_DIR"
    fi
    mkdir -p "$INBOX_DIR"
    echo "messages: []" > "$INBOX"
fi

# Generate unique message ID (timestamp + 4 random bytes).
# Use od instead of xxd because od is available on GNU/Linux and macOS runners.
MSG_ID="msg_$(date +%Y%m%d_%H%M%S)_$(od -An -N4 -tx1 /dev/urandom | tr -d ' \n')"
TIMESTAMP=$(date "+%Y-%m-%dT%H:%M:%S")

write_inbox_message() {
    # Add message via python3 (unified YAML handling)
    python3 - "$INBOX" "$MSG_ID" "$FROM" "$TIMESTAMP" "$TYPE" "$CONTENT" "$MESSAGE_GENERATION" <<'PY'
import os
import sys
import tempfile

import yaml

inbox_path, msg_id, msg_from, timestamp, msg_type, content, generation = sys.argv[1:]

try:
    # Load existing inbox
    with open(inbox_path, encoding="utf-8") as f:
        data = yaml.safe_load(f)

    # Initialize if needed
    if not data:
        data = {}
    if not data.get("messages"):
        data["messages"] = []

    # Add new message
    new_msg = {
        "id": msg_id,
        "from": msg_from,
        "timestamp": timestamp,
        "type": msg_type,
        "content": content,
        "read": False,
    }
    if generation:
        new_msg["generation"] = int(generation)
    data["messages"].append(new_msg)

    # Overflow protection: keep max 50 messages
    if len(data["messages"]) > 50:
        msgs = data["messages"]
        unread = [m for m in msgs if not m.get("read", False)]
        read = [m for m in msgs if m.get("read", False)]
        # Keep all unread + newest 30 read messages
        data["messages"] = unread + read[-30:]

    # Atomic write: tmp file + rename (prevents partial reads)
    tmp_fd, tmp_path = tempfile.mkstemp(dir=os.path.dirname(inbox_path), suffix=".tmp")
    try:
        with os.fdopen(tmp_fd, "w", encoding="utf-8") as f:
            yaml.dump(data, f, default_flow_style=False, allow_unicode=True, indent=2)
        os.replace(tmp_path, inbox_path)
    except Exception:
        os.unlink(tmp_path)
        raise

except Exception as e:
    print(f"ERROR: {e}", file=sys.stderr)
    sys.exit(1)
PY
}

record_failover_work_state() {
    [ -f "$FAILOVER_STATE" ] || return 0
    case "$TYPE" in cmd_new|task_assigned|audit_requested|cmd_done|report_received|audit_report) ;; *) return 0 ;; esac
    python3 - "$SCRIPT_DIR" "$MSG_ID" "$FROM" "$TARGET" "$TYPE" "$TIMESTAMP" <<'PY'
import sys
from pathlib import Path

root, message_id, sender, target, message_type, timestamp = sys.argv[1:]
sys.path.insert(0, root)
from shogunate_mod.runtime.role_failover import (  # noqa: E402
    EVENT_WORK_COMPLETE,
    EVENT_WORK_STATE_UPDATE,
    RoleFailoverStore,
    is_role_name,
)

store = RoleFailoverStore(Path(root))
state = store.load()
roles = state.get("roles", {})
source_state = roles.get(sender) if isinstance(roles, dict) else None
plan_id = source_state.get("current_work", {}).get("approved_plan_id") if isinstance(source_state, dict) and isinstance(source_state.get("current_work"), dict) else None
plan_revision = source_state.get("current_work", {}).get("approved_plan_revision") if isinstance(source_state, dict) and isinstance(source_state.get("current_work"), dict) else None

if message_type in {"cmd_done", "report_received", "audit_report"}:
    if is_role_name(sender) and isinstance(source_state, dict):
        generation = source_state.get("generation")
        if isinstance(generation, int) and not isinstance(generation, bool):
            store.apply_event({
                "event_id": f"complete-{message_id}-{sender}"[:128],
                "type": EVENT_WORK_COMPLETE,
                "role": sender,
                "expected_generation": generation,
            })
    raise SystemExit(0)

for role in dict.fromkeys((sender, target)):
    if not is_role_name(role):
        continue
    role_state = roles.get(role)
    if not isinstance(role_state, dict) or role_state.get("current_work"):
        continue
    generation = role_state.get("generation")
    if not isinstance(generation, int) or isinstance(generation, bool):
        continue
    work = {
        "work_id": message_id,
        "purpose": f"process inbox {message_type} reference {message_id}",
        "acceptance_criteria": ["process the referenced inbox message and record the result"],
        "approved_plan_id": plan_id,
        "approved_plan_revision": plan_revision,
        "progress": {"done": [], "in_progress": ["inbox_received"], "todo": ["process", "report"]},
        "scope": {"inbox_message_id": message_id, "started_at": timestamp},
        "next_step": "read the referenced inbox message",
    }
    store.apply_event(
        {
            "event_id": f"work-{message_id}-{role}"[:128],
            "type": EVENT_WORK_STATE_UPDATE,
            "role": role,
            "expected_generation": generation,
            "work_state": work,
        }
    )
PY
}

write_with_lock() {
    if command -v flock >/dev/null 2>&1; then
        (
            flock -w 5 200 || exit 1
            write_inbox_message
        ) 200>"$LOCKFILE"
        return $?
    fi

    # macOS does not provide flock by default. mkdir is atomic on local
    # filesystems, so use a lock directory as the portable fallback.
    local lockdir="${LOCKFILE}.d"
    local status=0
    local lock_attempt=0
    while ! mkdir "$lockdir" 2>/dev/null; do
        lock_attempt=$((lock_attempt + 1))
        [ "$lock_attempt" -lt 50 ] || return 1
        sleep 0.1
    done
    write_inbox_message || status=$?
    rmdir "$lockdir" 2>/dev/null || true
    return "$status"
}

# Atomic write with lock (3 retries)
attempt=0
max_attempts=3

while [ $attempt -lt $max_attempts ]; do
    if write_with_lock; then
        # Success
        if [ -x "$SCRIPT_DIR/shogunate_mod/queue/history_book.sh" ]; then
            bash "$SCRIPT_DIR/shogunate_mod/queue/history_book.sh" >/dev/null 2>&1 || true
        fi
        if [ -f "$SCRIPT_DIR/shogunate_mod/gunkan/event_log.py" ] && command -v python3 >/dev/null 2>&1; then
            python3 "$SCRIPT_DIR/shogunate_mod/gunkan/event_log.py" \
                --target "$TARGET" \
                --from-agent "$FROM" \
                --type "$TYPE" \
                --content "$CONTENT" \
                --message-id "$MSG_ID" \
                --timestamp "$TIMESTAMP" >/dev/null 2>&1 || true
        fi
        if ! record_failover_work_state; then
            echo "[inbox_write] WARN: message persisted but failover work state was not updated" >&2
        fi
        # shellcheck source=shogunate_mod/transport/agmsg_bridge.sh
        if source "$SCRIPT_DIR/shogunate_mod/transport/agmsg_bridge.sh" 2>/dev/null \
            && agmsg_bridge_enabled "$TARGET"; then
            agmsg_bridge_send "$TARGET" "$TYPE" "$FROM"
        fi
        exit 0
    else
        # Lock timeout or error
        attempt=$((attempt + 1))
        if [ $attempt -lt $max_attempts ]; then
            echo "[inbox_write] Lock timeout for $INBOX (attempt $attempt/$max_attempts), retrying..." >&2
            sleep 1
        else
            echo "[inbox_write] Failed to acquire lock after $max_attempts attempts for $INBOX" >&2
            exit 1
        fi
    fi
done
