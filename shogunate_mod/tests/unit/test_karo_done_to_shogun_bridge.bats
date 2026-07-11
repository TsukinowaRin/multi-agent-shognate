#!/usr/bin/env bats

source "$BATS_TEST_DIRNAME/../helpers/search_helper.bash"

setup() {
  TEST_TMP="$(mktemp -d)"
  local dir
  dir="$(cd "$(dirname "$BATS_TEST_FILENAME")" && pwd)"
  while [ "$dir" != "/" ] && [ ! -f "$dir/shogunate_mod/runtime/karo_done_to_shogun_bridge.py" ]; do
    dir="$(dirname "$dir")"
  done
  PROJECT_ROOT="$dir"

  mkdir -p "$TEST_TMP/queue/inbox" "$TEST_TMP/queue/runtime" "$TEST_TMP/scripts"

  cat > "$TEST_TMP/queue/shogun_to_karo.yaml" <<'YAML'
- id: cmd_300
  timestamp: "2026-03-13T22:33:00+09:00"
  status: done
  purpose: 点呼結果を報告する
  command: |
    全軍に点呼を取れ
- id: cmd_301
  timestamp: "2026-03-13T22:40:00+09:00"
  status: pending
  purpose: 未完了
YAML

  cat > "$TEST_TMP/queue/shogun_to_karo_archive.yaml" <<'YAML'
commands:
  - id: cmd_250
    timestamp: "2026-03-12T21:00:00+09:00"
    status: done
    purpose: 過去の完了cmd
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
  export MAS_SHOGUN_TO_KARO_ARCHIVE_FILE="$TEST_TMP/queue/shogun_to_karo_archive.yaml"
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

  run bats_search "cmd_300" "$MAS_SHOGUN_INBOX_FILE"
  [ "$status" -eq 1 ]
}

@test "karo_done_to_shogun_bridge: 新たにdoneになったcmdをshogun inboxへ通知する" {
  python3 "$PROJECT_ROOT/scripts/karo_done_to_shogun_bridge.py" >/dev/null
  python3 - <<'PY' "$MAS_SHOGUN_TO_KARO_FILE"
import sys, yaml
p = sys.argv[1]
with open(p, encoding='utf-8') as fh:
    data = yaml.safe_load(fh)
data.append({'id':'cmd_302','timestamp':'2026-03-13T23:00:00+09:00','status':'done','purpose':'結果を上申する'})
with open(p,'w',encoding='utf-8') as fh:
    yaml.safe_dump(data, fh, allow_unicode=True, sort_keys=False)
PY
  run python3 "$PROJECT_ROOT/scripts/karo_done_to_shogun_bridge.py"
  [ "$status" -eq 0 ]
  [[ "$output" =~ "sent" ]]
  run bats_search "cmd_302|cmd_done|上申|2026-03-13T23:00:00\\+09:00" "$MAS_SHOGUN_INBOX_FILE" "$MAS_KARO_DONE_TO_SHOGUN_STATE"
  [ "$status" -eq 0 ]
}

@test "karo_done_to_shogun_bridge: archive へ移した done cmd は既定では通知しない" {
  python3 "$PROJECT_ROOT/scripts/karo_done_to_shogun_bridge.py" >/dev/null
  python3 - <<'PY' "$MAS_SHOGUN_TO_KARO_ARCHIVE_FILE"
import sys, yaml
p = sys.argv[1]
with open(p, encoding='utf-8') as fh:
    data = yaml.safe_load(fh) or {}
cmds = data.get('commands', []) or []
cmds.append({
    'id': 'cmd_350',
    'timestamp': '2026-03-13T23:30:00+09:00',
    'status': 'done',
    'purpose': 'archive 側の完了通知',
})
data['commands'] = cmds
with open(p, 'w', encoding='utf-8') as fh:
    yaml.safe_dump(data, fh, allow_unicode=True, sort_keys=False)
PY
  run python3 "$PROJECT_ROOT/scripts/karo_done_to_shogun_bridge.py"
  [ "$status" -eq 0 ]
  [[ "$output" =~ "noop" ]]
  run bats_search "cmd_350|archive 側の完了通知|2026-03-13T23:30:00\\+09:00" "$MAS_SHOGUN_INBOX_FILE" "$MAS_KARO_DONE_TO_SHOGUN_STATE"
  [ "$status" -eq 1 ]
}

@test "karo_done_to_shogun_bridge: 明示設定時だけ archive の done cmd も通知する" {
  python3 "$PROJECT_ROOT/scripts/karo_done_to_shogun_bridge.py" >/dev/null
  python3 - <<'PY' "$MAS_SHOGUN_TO_KARO_ARCHIVE_FILE"
import sys, yaml
p = sys.argv[1]
with open(p, encoding='utf-8') as fh:
    data = yaml.safe_load(fh) or {}
cmds = data.get('commands', []) or []
cmds.append({
    'id': 'cmd_350',
    'timestamp': '2026-03-13T23:30:00+09:00',
    'status': 'done',
    'purpose': 'archive 側の完了通知',
})
data['commands'] = cmds
with open(p, 'w', encoding='utf-8') as fh:
    yaml.safe_dump(data, fh, allow_unicode=True, sort_keys=False)
PY
  run env MAS_KARO_DONE_INCLUDE_ARCHIVE=1 python3 "$PROJECT_ROOT/scripts/karo_done_to_shogun_bridge.py"
  [ "$status" -eq 0 ]
  [[ "$output" =~ "sent" ]]
  run bats_search "cmd_350|archive 側の完了通知|2026-03-13T23:30:00\\+09:00" "$MAS_SHOGUN_INBOX_FILE" "$MAS_KARO_DONE_TO_SHOGUN_STATE"
  [ "$status" -eq 0 ]
}

@test "karo_done_to_shogun_bridge: 同じ cmd_id でも timestamp が違えば別完了として通知する" {
  python3 "$PROJECT_ROOT/scripts/karo_done_to_shogun_bridge.py" >/dev/null
  python3 - <<'PY' "$MAS_SHOGUN_TO_KARO_ARCHIVE_FILE"
import sys, yaml
p = sys.argv[1]
with open(p, encoding='utf-8') as fh:
    data = yaml.safe_load(fh) or {}
cmds = data.get('commands', []) or []
cmds.append({
    'id': 'cmd_250',
    'timestamp': '2026-03-13T23:45:00+09:00',
    'status': 'done',
    'purpose': '再利用 cmd_id の新規完了',
})
data['commands'] = cmds
with open(p, 'w', encoding='utf-8') as fh:
    yaml.safe_dump(data, fh, allow_unicode=True, sort_keys=False)
PY
  run env MAS_KARO_DONE_INCLUDE_ARCHIVE=1 python3 "$PROJECT_ROOT/scripts/karo_done_to_shogun_bridge.py"
  [ "$status" -eq 0 ]
  [[ "$output" =~ "sent" ]]
  run bats_search "cmd_250|再利用 cmd_id の新規完了|2026-03-13T23:45:00\\+09:00" "$MAS_SHOGUN_INBOX_FILE" "$MAS_KARO_DONE_TO_SHOGUN_STATE"
  [ "$status" -eq 0 ]
}

@test "karo_done_to_shogun_bridge: 既通知済みdoneは重複通知しない" {
  python3 "$PROJECT_ROOT/scripts/karo_done_to_shogun_bridge.py" >/dev/null
  python3 - <<'PY' "$MAS_SHOGUN_TO_KARO_FILE" "$MAS_SHOGUN_INBOX_FILE"
import sys, yaml
cmdp, inboxp = sys.argv[1:]
with open(cmdp, encoding='utf-8') as fh:
    data = yaml.safe_load(fh)
data.append({'id':'cmd_303','timestamp':'2026-03-13T23:59:00+09:00','status':'done','purpose':'二重通知防止'})
with open(cmdp,'w',encoding='utf-8') as fh:
    yaml.safe_dump(data, fh, allow_unicode=True, sort_keys=False)
with open(inboxp, encoding='utf-8') as fh:
    inbox = yaml.safe_load(fh) or {}
msgs = inbox.get('messages', []) or []
msgs.append({'id':'msg_existing','from':'karo','type':'cmd_done','content':'[cmd:cmd_303] 家老より完了報告。 時刻: 2026-03-13T23:59:00+09:00', 'read': False})
inbox['messages'] = msgs
with open(inboxp, 'w', encoding='utf-8') as fh:
    yaml.safe_dump(inbox, fh, allow_unicode=True, sort_keys=False)
PY
  run python3 "$PROJECT_ROOT/scripts/karo_done_to_shogun_bridge.py"
  [ "$status" -eq 0 ]
  [[ "$output" =~ "already_notified=cmd_303" ]]
}

@test "karo_done_to_shogun_bridge: 同じ cmd_id の旧通知が inbox に残っていても timestamp が違えば新規通知する" {
  python3 "$PROJECT_ROOT/scripts/karo_done_to_shogun_bridge.py" >/dev/null
  python3 - <<'PY' "$MAS_SHOGUN_TO_KARO_ARCHIVE_FILE" "$MAS_SHOGUN_INBOX_FILE"
import sys, yaml
archivep, inboxp = sys.argv[1:]
with open(archivep, encoding='utf-8') as fh:
    data = yaml.safe_load(fh) or {}
cmds = data.get('commands', []) or []
cmds.append({
    'id': 'cmd_250',
    'timestamp': '2026-03-14T00:05:00+09:00',
    'status': 'done',
    'purpose': '再利用 cmd_id の別完了',
})
data['commands'] = cmds
with open(archivep, 'w', encoding='utf-8') as fh:
    yaml.safe_dump(data, fh, allow_unicode=True, sort_keys=False)

with open(inboxp, encoding='utf-8') as fh:
    inbox = yaml.safe_load(fh) or {}
msgs = inbox.get('messages', []) or []
msgs.append({
    'id': 'msg_old',
    'from': 'karo',
    'type': 'cmd_done',
    'content': '[cmd:cmd_250] 家老より完了報告。 時刻: 2026-03-12T21:00:00+09:00',
    'read': True,
})
inbox['messages'] = msgs
with open(inboxp, 'w', encoding='utf-8') as fh:
    yaml.safe_dump(inbox, fh, allow_unicode=True, sort_keys=False)
PY

  run env MAS_KARO_DONE_INCLUDE_ARCHIVE=1 python3 "$PROJECT_ROOT/scripts/karo_done_to_shogun_bridge.py"
  [ "$status" -eq 0 ]
  [[ "$output" =~ "sent" ]]
  run bats_search "cmd_250|2026-03-14T00:05:00\\+09:00|再利用 cmd_id の別完了" "$MAS_SHOGUN_INBOX_FILE" "$MAS_KARO_DONE_TO_SHOGUN_STATE"
  [ "$status" -eq 0 ]
}

@test "karo_done_to_shogun_bridge: 差戻し後に同じ cmd_id/timestamp が再完了したら completed_at で再通知する" {
  python3 "$PROJECT_ROOT/scripts/karo_done_to_shogun_bridge.py" >/dev/null
  printf 'cmd_300\t2026-03-13T22:33:00+09:00\t2026-03-13T22:50:00+09:00\n' > "$MAS_KARO_DONE_TO_SHOGUN_STATE"
  python3 - <<'PY' "$MAS_SHOGUN_TO_KARO_ARCHIVE_FILE" "$MAS_SHOGUN_INBOX_FILE"
import sys, yaml
archivep, inboxp = sys.argv[1:]
with open(archivep, encoding='utf-8') as fh:
    data = yaml.safe_load(fh) or {}
cmds = data.get('commands', []) or []
cmds.append({
    'id': 'cmd_300',
    'timestamp': '2026-03-13T22:33:00+09:00',
    'completed_at': '2026-03-13T23:10:00+09:00',
    'status': 'done',
    'purpose': '差戻し後の再完了',
})
data['commands'] = cmds
with open(archivep, 'w', encoding='utf-8') as fh:
    yaml.safe_dump(data, fh, allow_unicode=True, sort_keys=False)

with open(inboxp, encoding='utf-8') as fh:
    inbox = yaml.safe_load(fh) or {}
msgs = inbox.get('messages', []) or []
msgs.append({
    'id': 'msg_old',
    'from': 'karo',
    'type': 'cmd_done',
    'content': '[cmd:cmd_300] 家老より完了報告。 時刻: 2026-03-13T22:33:00+09:00 完了: 2026-03-13T22:50:00+09:00',
    'read': True,
})
inbox['messages'] = msgs
with open(inboxp, 'w', encoding='utf-8') as fh:
    yaml.safe_dump(inbox, fh, allow_unicode=True, sort_keys=False)
PY

  run env MAS_KARO_DONE_INCLUDE_ARCHIVE=1 python3 "$PROJECT_ROOT/scripts/karo_done_to_shogun_bridge.py"
  [ "$status" -eq 0 ]
  [[ "$output" =~ "sent" ]]
  run bats_search $'cmd_300\t2026-03-13T22:33:00\\+09:00\t2026-03-13T23:10:00\\+09:00|完了: 2026-03-13T23:10:00\\+09:00|差戻し後の再完了' "$MAS_SHOGUN_INBOX_FILE" "$MAS_KARO_DONE_TO_SHOGUN_STATE"
  [ "$status" -eq 0 ]
}

@test "karo_done_to_shogun_bridge: completed_at が無い再完了も dashboard 指紋で再通知する" {
  python3 "$PROJECT_ROOT/scripts/karo_done_to_shogun_bridge.py" >/dev/null
  printf 'cmd_300\t2026-03-13T22:33:00+09:00\n' > "$MAS_KARO_DONE_TO_SHOGUN_STATE"
  cat > "$MAS_DASHBOARD_FILE" <<'MD'
# dashboard
- 2026-03-13 23:20 `cmd_300` 再完了。監査差戻し後に修正と検証を完了した。
MD
  python3 - <<'PY' "$MAS_SHOGUN_INBOX_FILE"
import sys, yaml
inboxp = sys.argv[1]
with open(inboxp, encoding='utf-8') as fh:
    inbox = yaml.safe_load(fh) or {}
msgs = inbox.get('messages', []) or []
msgs.append({
    'id': 'msg_old',
    'from': 'karo',
    'type': 'cmd_done',
    'content': '[cmd:cmd_300] 家老より完了報告。 時刻: 2026-03-13T22:33:00+09:00 要約: 旧完了',
    'read': True,
})
inbox['messages'] = msgs
with open(inboxp, 'w', encoding='utf-8') as fh:
    yaml.safe_dump(inbox, fh, allow_unicode=True, sort_keys=False)
PY

  run python3 "$PROJECT_ROOT/scripts/karo_done_to_shogun_bridge.py"
  [ "$status" -eq 0 ]
  [[ "$output" =~ "sent" ]]
  run bats_search "完了ID: digest:|再完了。監査差戻し後に修正と検証を完了した|cmd_300.*digest:" "$MAS_SHOGUN_INBOX_FILE" "$MAS_KARO_DONE_TO_SHOGUN_STATE"
  [ "$status" -eq 0 ]
}

@test "karo_done_to_shogun_bridge: legacy state が cmd_id 単独でも timestamp 付き state へ昇格して再送しない" {
  printf 'cmd_250\ncmd_300\n' > "$MAS_KARO_DONE_TO_SHOGUN_STATE"

  run python3 "$PROJECT_ROOT/scripts/karo_done_to_shogun_bridge.py"
  [ "$status" -eq 0 ]
  [[ "$output" =~ "already_sent=cmd_300" ]]

  run bats_search $'cmd_300\t2026-03-13T22:33:00\\+09:00' "$MAS_KARO_DONE_TO_SHOGUN_STATE"
  [ "$status" -eq 0 ]
  run bats_search "cmd_done" "$MAS_SHOGUN_INBOX_FILE"
  [ "$status" -eq 1 ]
}

@test "karo_done_to_shogun_bridge: 重複 cmd_id の no-op 出力は timestamp 付きで区別する" {
  python3 "$PROJECT_ROOT/scripts/karo_done_to_shogun_bridge.py" >/dev/null
  python3 - <<'PY' "$MAS_SHOGUN_TO_KARO_ARCHIVE_FILE"
import sys, yaml
p = sys.argv[1]
with open(p, encoding='utf-8') as fh:
    data = yaml.safe_load(fh) or {}
cmds = data.get('commands', []) or []
cmds.append({
    'id': 'cmd_250',
    'timestamp': '2026-03-13T23:45:00+09:00',
    'status': 'done',
    'purpose': '再利用 cmd_id の新規完了',
})
data['commands'] = cmds
with open(p, 'w', encoding='utf-8') as fh:
    yaml.safe_dump(data, fh, allow_unicode=True, sort_keys=False)
PY
  printf 'cmd_250\t2026-03-12T21:00:00+09:00\ncmd_250\t2026-03-13T23:45:00+09:00\ncmd_300\t2026-03-13T22:33:00+09:00\n' > "$MAS_KARO_DONE_TO_SHOGUN_STATE"

  run env MAS_KARO_DONE_INCLUDE_ARCHIVE=1 python3 "$PROJECT_ROOT/scripts/karo_done_to_shogun_bridge.py"
  [ "$status" -eq 0 ]
  [[ "$output" == *"already_sent="* ]]
  [[ "$output" == *"cmd_250@2026-03-12T21:00:00+09:00"* ]]
  [[ "$output" == *"cmd_250@2026-03-13T23:45:00+09:00"* ]]
  [[ "$output" == *"cmd_300"* ]]
}
