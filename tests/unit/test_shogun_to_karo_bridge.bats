#!/usr/bin/env bats

source "$BATS_TEST_DIRNAME/../helpers/search_helper.bash"

setup() {
  TEST_TMP="$(mktemp -d)"
  PROJECT_ROOT="$(cd "$(dirname "$BATS_TEST_FILENAME")/../.." && pwd)"

  mkdir -p "$TEST_TMP/queue/inbox" "$TEST_TMP/queue/runtime" "$TEST_TMP/scripts"

  cat > "$TEST_TMP/queue/shogun_to_karo.yaml" <<'YAML'
- id: cmd_200
  status: pending
  command: |
    全軍に点呼を取れ
- id: cmd_201
  status: done
  command: |
    完了済み
YAML

  cat > "$TEST_TMP/queue/inbox/karo.yaml" <<'YAML'
messages: []
YAML

  cat > "$TEST_TMP/scripts/inbox_write.sh" <<'SH'
#!/usr/bin/env bash
set -euo pipefail
TARGET="$1"
CONTENT="$2"
TYPE="${3:-wake_up}"
FROM="${4:-unknown}"
INBOX_PATH="${MAS_KARO_INBOX_FILE}"
python3 - "$INBOX_PATH" "$TARGET" "$CONTENT" "$TYPE" "$FROM" <<'PY'
import sys, yaml
path, target, content, msg_type, source = sys.argv[1:]
with open(path, encoding="utf-8") as fh:
    data = yaml.safe_load(fh) or {}
msgs = data.get("messages", []) or []
msgs.append({
    "id": "test",
    "from": source,
    "type": msg_type,
    "content": content,
    "read": False,
})
data["messages"] = msgs
with open(path, "w", encoding="utf-8") as fh:
    yaml.safe_dump(data, fh, allow_unicode=True, sort_keys=False)
PY
SH
  chmod +x "$TEST_TMP/scripts/inbox_write.sh"

  export MAS_PROJECT_ROOT="$TEST_TMP"
  export MAS_QUEUE_DIR="$TEST_TMP/queue"
  export MAS_RUNTIME_DIR="$TEST_TMP/queue/runtime"
  export MAS_SHOGUN_TO_KARO_FILE="$TEST_TMP/queue/shogun_to_karo.yaml"
  export MAS_KARO_INBOX_FILE="$TEST_TMP/queue/inbox/karo.yaml"
  export MAS_SHOGUN_TO_KARO_BRIDGE_STATE="$TEST_TMP/queue/runtime/shogun_to_karo_bridge.tsv"
  export MAS_INBOX_WRITE_SCRIPT="$TEST_TMP/scripts/inbox_write.sh"
}

teardown() {
  rm -rf "$TEST_TMP"
}

@test "shogun_to_karo_bridge: pending cmd を karo inbox へ橋渡しする" {
  run python3 "$PROJECT_ROOT/scripts/shogun_to_karo_bridge.py"
  [ "$status" -eq 0 ]
  [[ "$output" =~ "sent" ]]

  run bats_search "cmd_200" "$MAS_KARO_INBOX_FILE" "$MAS_SHOGUN_TO_KARO_BRIDGE_STATE"
  [ "$status" -eq 0 ]
}

@test "shogun_to_karo_bridge: 既に通知済み cmd は重複送信しない" {
  printf 'cmd_200\n' > "$MAS_SHOGUN_TO_KARO_BRIDGE_STATE"

  run python3 "$PROJECT_ROOT/scripts/shogun_to_karo_bridge.py"
  [ "$status" -eq 0 ]
  [[ "$output" =~ "already_sent=cmd_200" ]]

  run bats_search "cmd_200" "$MAS_KARO_INBOX_FILE"
  [ "$status" -eq 1 ]
}

@test "shogun_to_karo_bridge: inboxに既通知がある時は already_notified を返す" {
  python3 - <<'PY' "$MAS_KARO_INBOX_FILE"
import sys, yaml
path = sys.argv[1]
data = {
    "messages": [
        {
            "id": "msg_existing",
            "from": "shogun",
            "type": "cmd_new",
            "content": "[cmd:cmd_200] 殿の新規命令が queue/shogun_to_karo.yaml に追加された。確認し、ただちに着手せよ。",
            "read": False,
        }
    ]
}
with open(path, "w", encoding="utf-8") as fh:
    yaml.safe_dump(data, fh, allow_unicode=True, sort_keys=False)
PY

  run python3 "$PROJECT_ROOT/scripts/shogun_to_karo_bridge.py"
  [ "$status" -eq 0 ]
  [[ "$output" =~ "already_notified=cmd_200" ]]
}
