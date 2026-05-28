#!/usr/bin/env bats

setup_file() {
  export PROJECT_ROOT="$(cd "$(dirname "$BATS_TEST_FILENAME")/../.." && pwd)"
  export PYTHON_BIN="$(command -v python3)"
  python3 -c "import yaml" 2>/dev/null || return 1
}

setup() {
  export TEST_TMP="$(mktemp -d "$BATS_TMPDIR/gunkan_audit.XXXXXX")"
  mkdir -p "$TEST_TMP/queue/runtime" "$TEST_TMP/queue/reports" "$TEST_TMP/docs"
  printf '# reqs\n' > "$TEST_TMP/docs/REQS.md"
  printf '# index\n' > "$TEST_TMP/docs/INDEX.md"
  printf '# dashboard\n' > "$TEST_TMP/dashboard.md"
  printf 'queue: []\n' > "$TEST_TMP/queue/shogun_to_karo.yaml"
  printf 'worker_id: gunkan\nstatus: pending\n' > "$TEST_TMP/queue/reports/gunkan_report.yaml"
}

teardown() {
  rm -rf "$TEST_TMP"
}

@test "gunkan_event_log: appends event and updates by-agent summary" {
  run python3 "$PROJECT_ROOT/scripts/gunkan_event_log.py" \
    --project-root "$TEST_TMP" \
    --target karo \
    --from-agent ashigaru1 \
    --type report_completed \
    --content "done"
  [ "$status" -eq 0 ]

  python3 - "$TEST_TMP/queue/runtime/gunkan_events.yaml" <<'PY'
import sys
import yaml

with open(sys.argv[1], encoding="utf-8") as f:
    data = yaml.safe_load(f)
assert data["events"][0]["from"] == "ashigaru1"
assert data["summary"]["by_agent"]["ashigaru1"]["reports"] == 1
assert data["summary"]["by_type"]["report_completed"] == 1
PY
}

@test "gunkan_codd_audit: falls back when codd CLI is unavailable" {
  mkdir -p "$TEST_TMP/no-codd"
  export PATH="$TEST_TMP/no-codd:/usr/bin:/bin"

  run "$PYTHON_BIN" "$PROJECT_ROOT/scripts/gunkan_codd_audit.py" --project-root "$TEST_TMP" --scope runtime --parent-cmd cmd_1
  [ "$status" -eq 0 ]

  "$PYTHON_BIN" - "$TEST_TMP/queue/runtime/codd/gunkan_audit.yaml" <<'PY'
import sys
import yaml

with open(sys.argv[1], encoding="utf-8") as f:
    data = yaml.safe_load(f)
assert data["worker_id"] == "gunkan"
assert data["codd_available"] is False
assert data["status"] == "passed"
assert data["summary"].startswith("codd CLI not found")
PY
}

@test "gunkan_codd_audit: discovers repo-local codd venv" {
  mkdir -p "$TEST_TMP/.shogunate/codd-venv/bin"
  cat > "$TEST_TMP/.shogunate/codd-venv/bin/codd" <<'SH'
#!/bin/sh
echo "mock codd $*"
exit 0
SH
  chmod +x "$TEST_TMP/.shogunate/codd-venv/bin/codd"
  export PATH="/usr/bin:/bin"

  run "$PYTHON_BIN" "$PROJECT_ROOT/scripts/gunkan_codd_audit.py" --project-root "$TEST_TMP" --scope runtime --parent-cmd cmd_2
  [ "$status" -eq 0 ]

  "$PYTHON_BIN" - "$TEST_TMP/queue/runtime/codd/gunkan_audit.yaml" <<'PY'
import sys
import yaml

with open(sys.argv[1], encoding="utf-8") as f:
    data = yaml.safe_load(f)
assert data["codd_available"] is True
assert data["status"] == "passed"
assert len(data["commands"]) == 3
assert data["commands"][0]["stdout"].startswith("mock codd")
PY
}

@test "gunkan_light_watch: done report without verification wakes gunkan once" {
  cat > "$TEST_TMP/queue/reports/ashigaru1_report.yaml" <<'YAML'
worker_id: ashigaru1
status: done
verification: 未実行
parent_cmd: cmd_watch_1
YAML

  run "$PYTHON_BIN" "$PROJECT_ROOT/scripts/gunkan_light_watch.py" --project-root "$TEST_TMP" --alert-on-first-run
  [ "$status" -eq 0 ]

  "$PYTHON_BIN" - "$TEST_TMP/queue/runtime/gunkan_watch.yaml" "$TEST_TMP/queue/inbox/gunkan.yaml" <<'PY'
import sys
import yaml

watch = yaml.safe_load(open(sys.argv[1], encoding="utf-8"))
inbox = yaml.safe_load(open(sys.argv[2], encoding="utf-8"))
assert watch["status"] == "warn"
assert watch["alert_sent"] is True
assert any(f["kind"] == "done_without_verification" for f in watch["findings"])
messages = inbox["messages"]
assert len(messages) == 1
assert messages[0]["type"] == "audit_requested"
assert messages[0]["from"] == "gunkan_light_watch"
PY

  run "$PYTHON_BIN" "$PROJECT_ROOT/scripts/gunkan_light_watch.py" --project-root "$TEST_TMP" --alert-on-first-run
  [ "$status" -eq 0 ]

  "$PYTHON_BIN" - "$TEST_TMP/queue/inbox/gunkan.yaml" <<'PY'
import sys
import yaml

inbox = yaml.safe_load(open(sys.argv[1], encoding="utf-8"))
assert len(inbox["messages"]) == 1
PY
}

@test "gunkan_light_watch: unchanged finding is not re-alerted after cooldown" {
  cat > "$TEST_TMP/queue/reports/ashigaru1_report.yaml" <<'YAML'
worker_id: ashigaru1
status: done
verification: 未実行
parent_cmd: cmd_watch_1
YAML

  run "$PYTHON_BIN" "$PROJECT_ROOT/scripts/gunkan_light_watch.py" --project-root "$TEST_TMP" --alert-on-first-run --cooldown 0
  [ "$status" -eq 0 ]

  run "$PYTHON_BIN" "$PROJECT_ROOT/scripts/gunkan_light_watch.py" --project-root "$TEST_TMP" --alert-on-first-run --cooldown 0
  [ "$status" -eq 0 ]

  "$PYTHON_BIN" - "$TEST_TMP/queue/inbox/gunkan.yaml" <<'PY'
import sys
import yaml

inbox = yaml.safe_load(open(sys.argv[1], encoding="utf-8"))
assert len(inbox["messages"]) == 1
PY

  cat > "$TEST_TMP/queue/reports/ashigaru1_report.yaml" <<'YAML'
worker_id: ashigaru1
status: done
verification: 未確認
parent_cmd: cmd_watch_1
YAML

  run "$PYTHON_BIN" "$PROJECT_ROOT/scripts/gunkan_light_watch.py" --project-root "$TEST_TMP" --alert-on-first-run --cooldown 0
  [ "$status" -eq 0 ]

  "$PYTHON_BIN" - "$TEST_TMP/queue/inbox/gunkan.yaml" <<'PY'
import sys
import yaml

inbox = yaml.safe_load(open(sys.argv[1], encoding="utf-8"))
assert len(inbox["messages"]) == 2
PY
}

@test "gunkan_light_watch: first run baselines old findings without waking gunkan" {
  cat > "$TEST_TMP/queue/reports/ashigaru1_report.yaml" <<'YAML'
worker_id: ashigaru1
status: blocked
parent_cmd: old_cmd
YAML

  run "$PYTHON_BIN" "$PROJECT_ROOT/scripts/gunkan_light_watch.py" --project-root "$TEST_TMP"
  [ "$status" -eq 0 ]

  "$PYTHON_BIN" - "$TEST_TMP/queue/runtime/gunkan_watch.yaml" "$TEST_TMP/queue/inbox/gunkan.yaml" <<'PY'
import sys
import yaml

watch = yaml.safe_load(open(sys.argv[1], encoding="utf-8"))
inbox = yaml.safe_load(open(sys.argv[2], encoding="utf-8")) if __import__("pathlib").Path(sys.argv[2]).exists() else {"messages": []}
assert watch["status"] == "warn"
assert watch["alert_sent"] is False
assert len(inbox["messages"]) == 0
PY
}

@test "gunkan_light_watch: untracked sensitive path is detected" {
  git -C "$TEST_TMP" init -q
  git -C "$TEST_TMP" config user.email smoke@example.invalid
  git -C "$TEST_TMP" config user.name "Smoke Test"
  git -C "$TEST_TMP" add .
  git -C "$TEST_TMP" commit -q -m baseline
  printf 'TOKEN=placeholder\n' > "$TEST_TMP/.env"

  run "$PYTHON_BIN" "$PROJECT_ROOT/scripts/gunkan_light_watch.py" --project-root "$TEST_TMP" --alert-on-first-run
  [ "$status" -eq 0 ]

  "$PYTHON_BIN" - "$TEST_TMP/queue/runtime/gunkan_watch.yaml" "$TEST_TMP/queue/inbox/gunkan.yaml" <<'PY'
import sys
import yaml

watch = yaml.safe_load(open(sys.argv[1], encoding="utf-8"))
inbox = yaml.safe_load(open(sys.argv[2], encoding="utf-8"))
assert any(f["kind"] == "sensitive_path_changed" for f in watch["findings"])
assert watch["alert_sent"] is True
assert inbox["messages"][0]["type"] == "audit_requested"
PY
}

@test "gunkan_light_watch: CoDD config/frontmatter are present" {
  [ -f "$PROJECT_ROOT/.codd/codd.yaml" ]
  grep -q 'doc_dirs:' "$PROJECT_ROOT/.codd/codd.yaml"
  grep -q 'docs/codd/' "$PROJECT_ROOT/.codd/codd.yaml"
  grep -q 'node_id: "req:gunkan-monitoring"' "$PROJECT_ROOT/docs/codd/gunkan_monitoring.md"
  grep -q 'node_id: "design:gunkan-light-watch"' "$PROJECT_ROOT/docs/codd/gunkan_light_watch_design.md"
}

@test "codd_check wrapper exposes install scan validate and gunkan commands" {
  run bash -n "$PROJECT_ROOT/scripts/codd_check.sh"
  [ "$status" -eq 0 ]

  run bash "$PROJECT_ROOT/scripts/codd_check.sh" help
  [ "$status" -eq 0 ]
  [[ "$output" == *"install    Install/update codd-dev"* ]]
  [[ "$output" == *"scan       Run codd scan"* ]]
  [[ "$output" == *"gunkan     Run scripts/gunkan_codd_audit.py"* ]]

  grep -q '^codd:' "$PROJECT_ROOT/Makefile"
  grep -q '^codd-gunkan:' "$PROJECT_ROOT/Makefile"
}
