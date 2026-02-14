#!/bin/bash
# inbox_write.sh — メールボックスへのメッセージ書き込み（排他ロック付き）
# Usage: bash scripts/inbox_write.sh <target_agent> <content> [type] [from]
# Example: bash scripts/inbox_write.sh karo "足軽5号、任務完了" report_received ashigaru5

set -e

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
TARGET="$1"
CONTENT="$2"
TYPE="${3:-wake_up}"
FROM="${4:-unknown}"
OWNER_MAP="$SCRIPT_DIR/queue/runtime/ashigaru_owner.tsv"

INBOX="$SCRIPT_DIR/queue/inbox/${TARGET}.yaml"
LOCKFILE="${INBOX}.lock"
INBOX_DIR="$(dirname "$INBOX")"

# Validate arguments
if [ -z "$TARGET" ] || [ -z "$CONTENT" ]; then
    echo "Usage: inbox_write.sh <target_agent> <content> [type] [from]" >&2
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
    # 家老同士の直接通信は禁止（自己宛は許可）
    if is_karo_agent "$FROM" && is_karo_agent "$TARGET" && [ "$FROM" != "$TARGET" ]; then
        echo "[inbox_write] route rejected: karo-to-karo direct communication is forbidden ($FROM -> $TARGET)" >&2
        return 1
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

# Initialize inbox if not exists
if [ ! -f "$INBOX" ]; then
    if [ -f "$INBOX_DIR" ] && [ ! -d "$INBOX_DIR" ]; then
        rm -f "$INBOX_DIR"
    fi
    mkdir -p "$INBOX_DIR"
    echo "messages: []" > "$INBOX"
fi

# Generate unique message ID (timestamp-based)
MSG_ID="msg_$(date +%Y%m%d_%H%M%S)_$(head -c 4 /dev/urandom | xxd -p)"
TIMESTAMP=$(date "+%Y-%m-%dT%H:%M:%S")

# Atomic write with flock (3 retries)
attempt=0
max_attempts=3

while [ $attempt -lt $max_attempts ]; do
    if (
        flock -w 5 200 || exit 1

        # Add message via python3 (unified YAML handling)
        python3 -c "
import yaml, sys

try:
    # Load existing inbox
    with open('$INBOX') as f:
        data = yaml.safe_load(f)

    # Initialize if needed
    if not data:
        data = {}
    if not data.get('messages'):
        data['messages'] = []

    # Add new message
    new_msg = {
        'id': '$MSG_ID',
        'from': '$FROM',
        'timestamp': '$TIMESTAMP',
        'type': '$TYPE',
        'content': '''$CONTENT''',
        'read': False
    }
    data['messages'].append(new_msg)

    # Overflow protection: keep max 50 messages
    if len(data['messages']) > 50:
        msgs = data['messages']
        unread = [m for m in msgs if not m.get('read', False)]
        read = [m for m in msgs if m.get('read', False)]
        # Keep all unread + newest 30 read messages
        data['messages'] = unread + read[-30:]

    # Atomic write: tmp file + rename (prevents partial reads)
    import tempfile, os
    tmp_fd, tmp_path = tempfile.mkstemp(dir=os.path.dirname('$INBOX'), suffix='.tmp')
    try:
        with os.fdopen(tmp_fd, 'w') as f:
            yaml.dump(data, f, default_flow_style=False, allow_unicode=True, indent=2)
        os.replace(tmp_path, '$INBOX')
    except:
        os.unlink(tmp_path)
        raise

except Exception as e:
    print(f'ERROR: {e}', file=sys.stderr)
    sys.exit(1)
" || exit 1

    ) 200>"$LOCKFILE"; then
        # Success
        if [ -x "$SCRIPT_DIR/scripts/history_book.sh" ]; then
            bash "$SCRIPT_DIR/scripts/history_book.sh" >/dev/null 2>&1 || true
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
