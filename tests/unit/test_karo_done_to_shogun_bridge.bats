#!/usr/bin/env bats

setup() {
  TEST_TMP="$(mktemp -d)"
  PROJECT_ROOT="$(cd "$(dirname "$BATS_TEST_FILENAME")/../.." && pwd)"

  mkdir -p "$TEST_TMP/queue/inbox" "$TEST_TMP/queue/runtime" "$TEST_TMP/scripts"

  cat > "$TEST_TMP/queue/shogun_to_karo.yaml" <<'YAML'
- id: cmd_300
  status: done
  purpose: 点呼結果を報告する
  command: |
    全軍に点呼を取れ
- id: cmd_301
  status: pending
  purpose: 未完了
YAML

  cat > "$TEST_TMP/dashboard.md" <<'MD'
# dashboard
- 2026-03-13 22:33 `cmd_300` 完了。全軍 active を確認した。
MD

  cat > "$TEST_TMP/queue/inbox/shogun.yaml" <<'YAML'
messages: []
YAML

  cat > "$TEST_TMP/scripts/inbox_write.sh" <<'SH'
#!/usr/bin/env bash
set -euo pipefail
TARGET="$1"
CONTENT="$2"
TYPE="${3:-wake_up}"
FROM="${4:-unknown}"
INBOX_PATH="${MAS_SHOGUN_INBOX_FILE}"
python3 - "$INBOX_PATH" "$TARGET" "$CONTENT" "$TYPE" "$FROM" <<'PY'
import sys, yaml
path, target, content, msg_type, source = sys.argv[1:]
with open(path, encoding='utf-8') as fh:
    data = yaml.safe_load(fh) or {}
msgs = data.get('messages', []) or []
msgs.append({
    'id': 'test',
    'from': source,
    'type': msg_type,
    'content': content,
    'read': False,
})
data['messages'] = msgs
with open(path, 'w', encoding='utf-8') as fh:
    yaml.safe_dump(data, fh, allow_unicode=True, sort_keys=False)
PY
SH
  chmod +x "$TEST_TMP/scripts/inbox_write.sh"

  export MAS_PROJECT_ROOT="$TEST_TMP"
  export MAS_QUEUE_DIR="$TEST_TMP/queue"
  export MAS_RUNTIME_DIR="$TEST_TMP/queue/runtime"
  export MAS_SHOGUN_TO_KARO_FILE="$TEST_TMP/queue/shogun_to_karo.yaml"
  export MAS_SHOGUN_INBOX_FILE="$TEST_TMP/queue/inbox/shogun.yaml"
  export MAS_DASHBOARD_FILE="$TEST_TMP/dashboard.md"
  export MAS_KARO_DONE_TO_SHOGUN_STATE="$TEST_TMP/queue/runtime/karo_done_to_shogun.tsv"
  export MAS_INBOX_WRITE_SCRIPT="$TEST_TMP/scripts/inbox_write.sh"
}

teardown() {
  rm -rf "$TEST_TMP"
}

@test "karo_done_to_shogun_bridge: 初回は既存doneをprimeして通知しない" {
  run python3 "$PROJECT_ROOT/scripts/karo_done_to_shogun_bridge.py"
  [ "$status" -eq 0 ]
  [[ "$output" =~ "primed" ]]

  run rg -n "cmd_300" "$MAS_SHOGUN_INBOX_FILE"
  [ "$status" -eq 1 ]
}

@test "karo_done_to_shogun_bridge: 新たにdoneになったcmdをshogun inboxへ通知する" {
  python3 "$PROJECT_ROOT/scripts/karo_done_to_shogun_bridge.py" >/dev/null
  python3 - <<'PY' "$MAS_SHOGUN_TO_KARO_FILE"
import sys, yaml
p = sys.argv[1]
with open(p, encoding='utf-8') as fh:
    data = yaml.safe_load(fh)
data.append({'id':'cmd_302','status':'done','purpose':'結果を上申する'})
with open(p,'w',encoding='utf-8') as fh:
    yaml.safe_dump(data, fh, allow_unicode=True, sort_keys=False)
PY
  run python3 "$PROJECT_ROOT/scripts/karo_done_to_shogun_bridge.py"
  [ "$status" -eq 0 ]
  [[ "$output" =~ "sent" ]]
  run rg -n "cmd_302|cmd_done|上申" "$MAS_SHOGUN_INBOX_FILE" "$MAS_KARO_DONE_TO_SHOGUN_STATE"
  [ "$status" -eq 0 ]
}

@test "karo_done_to_shogun_bridge: 既通知済みdoneは重複通知しない" {
  python3 "$PROJECT_ROOT/scripts/karo_done_to_shogun_bridge.py" >/dev/null
  python3 - <<'PY' "$MAS_SHOGUN_TO_KARO_FILE" "$MAS_SHOGUN_INBOX_FILE"
import sys, yaml
cmdp, inboxp = sys.argv[1:]
with open(cmdp, encoding='utf-8') as fh:
    data = yaml.safe_load(fh)
data.append({'id':'cmd_303','status':'done','purpose':'二重通知防止'})
with open(cmdp,'w',encoding='utf-8') as fh:
    yaml.safe_dump(data, fh, allow_unicode=True, sort_keys=False)
with open(inboxp, encoding='utf-8') as fh:
    inbox = yaml.safe_load(fh) or {}
msgs = inbox.get('messages', []) or []
msgs.append({'id':'msg_existing','from':'karo','type':'cmd_done','content':'[cmd:cmd_303] 家老より完了報告。', 'read': False})
inbox['messages'] = msgs
with open(inboxp, 'w', encoding='utf-8') as fh:
    yaml.safe_dump(inbox, fh, allow_unicode=True, sort_keys=False)
PY
  run python3 "$PROJECT_ROOT/scripts/karo_done_to_shogun_bridge.py"
  [ "$status" -eq 0 ]
  [[ "$output" =~ "already_notified=cmd_303" ]]
}
