#!/usr/bin/env bats

setup() {
  TEST_TMP="$(mktemp -d)"
  PROJECT_ROOT="$(cd "$(dirname "$BATS_TEST_FILENAME")/../.." && pwd)"

  cat > "$TEST_TMP/settings.yaml" <<'YAML'
cli:
  default: gemini
  agents:
    gunshi:
      type: gemini
      model: gemini-3-pro-preview
      thinking_level: minimal
    ashigaru1:
      type: gemini
      model: gemini-3-flash-preview
      thinking_level: minimal
    ashigaru2:
      type: gemini
      model: gemini-2.5-pro
      thinking_budget: 0
    ashigaru3:
      type: gemini
      model: auto
      thinking_level: high
    karo:
      type: codex
YAML

  export MAS_SETTINGS_PATH="$TEST_TMP/settings.yaml"
  export MAS_GEMINI_SETTINGS_PATH="$TEST_TMP/.gemini/settings.json"
  export MAS_GEMINI_SUMMARY_PATH="$TEST_TMP/gemini_aliases.tsv"
}

teardown() {
  rm -rf "$TEST_TMP"
}

@test "sync_gemini_settings: per-agent alias を生成する" {
  run python3 "$PROJECT_ROOT/scripts/sync_gemini_settings.py"
  [ "$status" -eq 0 ]
  [ -f "$MAS_GEMINI_SETTINGS_PATH" ]
  [ -f "$MAS_GEMINI_SUMMARY_PATH" ]

  run python3 - "$MAS_GEMINI_SETTINGS_PATH" <<'PY'
import json, sys
with open(sys.argv[1], encoding='utf-8') as fh:
    cfg = json.load(fh)
aliases = cfg["modelConfigs"]["customAliases"]
assert aliases["mas-gunshi"]["modelConfig"]["model"] == "gemini-3-pro-preview"
assert aliases["mas-gunshi"]["modelConfig"]["generateContentConfig"]["thinkingConfig"]["thinkingLevel"] == "LOW"
assert aliases["mas-ashigaru1"]["modelConfig"]["generateContentConfig"]["thinkingConfig"]["thinkingLevel"] == "MINIMAL"
assert aliases["mas-ashigaru2"]["modelConfig"]["generateContentConfig"]["thinkingConfig"]["thinkingBudget"] == -1
assert aliases["mas-ashigaru3"]["modelConfig"]["model"] == "gemini-3-pro-preview"
print("ok")
PY
  [ "$status" -eq 0 ]
}

@test "sync_gemini_settings: summary に warning を書く" {
  run python3 "$PROJECT_ROOT/scripts/sync_gemini_settings.py"
  [ "$status" -eq 0 ]
  run rg -n "gemini-3-pro-preview は MINIMAL/MEDIUM 非対応|gemini-2.5-pro は thinkingBudget=0" "$MAS_GEMINI_SUMMARY_PATH"
  [ "$status" -eq 0 ]
}
