#!/usr/bin/env bats

source "$BATS_TEST_DIRNAME/../helpers/search_helper.bash"

setup() {
  TEST_TMP="$(mktemp -d)"
  PROJECT_ROOT="$(cd "$(dirname "$BATS_TEST_FILENAME")/../.." && pwd)"

  cat > "$TEST_TMP/settings.yaml" <<'YAML'
cli:
  default: opencode
  agents:
    shogun:
      type: opencode
      model: ollama/qwen3-coder:30b
    gunshi:
      type: kilo
      model: lmstudio/codellama-7b.Q4_0.gguf
  opencode_like:
    provider: openai-compatible
    base_url: http://127.0.0.1:1234/v1
    api_key_env: LOCALAI_API_KEY
    instructions:
      - AGENTS.md
YAML

  export MAS_SETTINGS_PATH="$TEST_TMP/settings.yaml"
  export MAS_OPENCODE_CONFIG_PATH="$TEST_TMP/opencode.json"
  export MAS_OPENCODE_SUMMARY_PATH="$TEST_TMP/opencode_summary.tsv"
}

teardown() {
  rm -rf "$TEST_TMP"
}

@test "sync_opencode_config: project config を生成する" {
  run python3 "$PROJECT_ROOT/scripts/sync_opencode_config.py"
  [ "$status" -eq 0 ]
  [ -f "$MAS_OPENCODE_CONFIG_PATH" ]
  [ -f "$MAS_OPENCODE_SUMMARY_PATH" ]

  run python3 - "$MAS_OPENCODE_CONFIG_PATH" <<'PY'
import json, sys
with open(sys.argv[1], encoding='utf-8') as fh:
    cfg = json.load(fh)
assert cfg["permission"] == "allow"
assert cfg["instructions"] == ["AGENTS.md"]
provider = cfg["provider"]["openai-compatible"]["options"]
assert provider["baseURL"] == "http://127.0.0.1:1234/v1"
assert provider["apiKey"] == "{env:LOCALAI_API_KEY}"
print("ok")
PY
  [ "$status" -eq 0 ]
}

@test "sync_opencode_config: 対象CLIが無ければ skip する" {
  cat > "$TEST_TMP/settings.yaml" <<'YAML'
cli:
  default: codex
  agents:
    shogun:
      type: codex
YAML
  run python3 "$PROJECT_ROOT/scripts/sync_opencode_config.py"
  [ "$status" -eq 0 ]
  [ ! -f "$MAS_OPENCODE_CONFIG_PATH" ]
  run bats_search "skipped|noop" "$MAS_OPENCODE_SUMMARY_PATH"
  [ "$status" -eq 0 ]
}

@test "sync_opencode_config: ollama は base_url 未指定でも既定URLを補完する" {
  cat > "$TEST_TMP/settings.yaml" <<'YAML'
cli:
  default: opencode
  agents:
    shogun:
      type: opencode
      model: ollama/qwen3-coder:30b
  opencode_like:
    provider: ollama
YAML
  run python3 "$PROJECT_ROOT/scripts/sync_opencode_config.py"
  [ "$status" -eq 0 ]

  run python3 - "$MAS_OPENCODE_CONFIG_PATH" <<'PY'
import json, sys
with open(sys.argv[1], encoding='utf-8') as fh:
    cfg = json.load(fh)
assert cfg["provider"]["ollama"]["options"]["baseURL"] == "http://127.0.0.1:11434/v1"
print("ok")
PY
  [ "$status" -eq 0 ]
}

@test "sync_opencode_config: lmstudio は base_url 未指定でも既定URLを補完する" {
  cat > "$TEST_TMP/settings.yaml" <<'YAML'
cli:
  default: kilo
  agents:
    gunshi:
      type: kilo
      model: lmstudio/codellama-7b.Q4_0.gguf
  opencode_like:
    provider: lmstudio
YAML
  run python3 "$PROJECT_ROOT/scripts/sync_opencode_config.py"
  [ "$status" -eq 0 ]

  run python3 - "$MAS_OPENCODE_CONFIG_PATH" <<'PY'
import json, sys
with open(sys.argv[1], encoding='utf-8') as fh:
    cfg = json.load(fh)
assert cfg["provider"]["lmstudio"]["options"]["baseURL"] == "http://127.0.0.1:1234/v1"
print("ok")
PY
  [ "$status" -eq 0 ]
}

@test "sync_opencode_config: permission は allow を既定出力する" {
  run python3 "$PROJECT_ROOT/scripts/sync_opencode_config.py"
  [ "$status" -eq 0 ]

  run python3 - "$MAS_OPENCODE_CONFIG_PATH" <<'PY'
import json, sys
with open(sys.argv[1], encoding='utf-8') as fh:
    cfg = json.load(fh)
assert cfg["permission"] == "allow"
print("ok")
PY
  [ "$status" -eq 0 ]
}
