#!/usr/bin/env bats

setup() {
  TEST_TMP="$(mktemp -d)"
  PROJECT_ROOT="$(cd "$(dirname "$BATS_TEST_FILENAME")/../.." && pwd)"

  mkdir -p "$TEST_TMP/scripts" "$TEST_TMP/lib" "$TEST_TMP/config" "$TEST_TMP/queue/runtime"
  cp "$PROJECT_ROOT/scripts/configure_agents.sh" "$TEST_TMP/scripts/configure_agents.sh"
  cp "$PROJECT_ROOT/lib/topology_adapter.sh" "$TEST_TMP/lib/topology_adapter.sh"
  chmod +x "$TEST_TMP/scripts/configure_agents.sh"

  cat > "$TEST_TMP/config/settings.yaml" <<'YAML'
language: ja
shell: bash
multiplexer:
  default: zellij
startup:
  template: goza_room
topology:
  active_ashigaru:
    - ashigaru1
cli:
  default: gemini
  agents:
    shogun:
      type: codex
    gunshi:
      type: gemini
    karo:
      type: codex
    ashigaru1:
      type: gemini
  commands:
    gemini: "gemini --yolo"
    localapi: "python3 scripts/localapi_repl.py"
    opencode: "opencode"
    kilo: "kilo"
YAML
}

teardown() {
  rm -rf "$TEST_TMP"
}

@test "configure_agents: opencode_like設定とGemini thinking_levelを正しく保存する" {
  run bash -lc "cd '$TEST_TMP' && printf '%s\n' \
    'zellij' \
    'goza_room' \
    'opencode' \
    '1' \
    'opencode' \
    'ollama/qwen3-coder:30b' \
    'kilo' \
    'lmstudio/codellama-7b.Q4_0.gguf' \
    'codex' \
    'auto' \
    'auto' \
    'gemini' \
    'gemini-3-flash-preview' \
    'minimal' \
    'yes' \
    'openai-compatible' \
    'http://127.0.0.1:1234/v1' \
    'LOCALAI_API_KEY' \
    'AGENTS.md' | bash scripts/configure_agents.sh >/dev/null"
  [ "$status" -eq 0 ]

  run python3 - "$TEST_TMP/config/settings.yaml" <<'PY'
import sys, yaml
with open(sys.argv[1], encoding='utf-8') as fh:
    cfg = yaml.safe_load(fh)
ashigaru = cfg["cli"]["agents"]["ashigaru1"]
assert ashigaru["type"] == "gemini"
assert ashigaru["model"] == "gemini-3-flash-preview"
assert ashigaru["thinking_level"] == "minimal"
assert "reasoning_effort" not in ashigaru
shared = cfg["cli"]["opencode_like"]
assert shared["provider"] == "openai-compatible"
assert shared["base_url"] == "http://127.0.0.1:1234/v1"
assert shared["api_key_env"] == "LOCALAI_API_KEY"
assert shared["instructions"] == ["AGENTS.md"]
print("ok")
PY
  [ "$status" -eq 0 ]
}
