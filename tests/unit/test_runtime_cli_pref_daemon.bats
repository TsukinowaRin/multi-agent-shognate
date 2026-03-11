#!/usr/bin/env bats

setup() {
  TEST_TMP="$(mktemp -d)"
  PROJECT_ROOT="$(cd "$(dirname "$BATS_TEST_FILENAME")/../.." && pwd)"

  mkdir -p "$TEST_TMP/scripts"
  cat > "$TEST_TMP/scripts/sync_runtime_cli_preferences.py" <<'PY'
#!/usr/bin/env python3
from pathlib import Path
Path("daemon_once_ran.txt").write_text("ok\n", encoding="utf-8")
PY
  chmod +x "$TEST_TMP/scripts/sync_runtime_cli_preferences.py"
}

teardown() {
  rm -rf "$TEST_TMP"
}

@test "runtime_cli_pref_daemon --once は同期スクリプトを1回実行する" {
  run env \
    MAS_RUNTIME_PREF_SYNC_PYTHON=python3 \
    MAS_RUNTIME_PREF_SYNC_SCRIPT="$TEST_TMP/scripts/sync_runtime_cli_preferences.py" \
    bash "$PROJECT_ROOT/scripts/runtime_cli_pref_daemon.sh" --once

  [ "$status" -eq 0 ]
  [ -f "$PROJECT_ROOT/daemon_once_ran.txt" ]
  rm -f "$PROJECT_ROOT/daemon_once_ran.txt"
}
