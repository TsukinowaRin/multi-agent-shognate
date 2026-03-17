#!/usr/bin/env bats

setup() {
    export PROJECT_ROOT="$(cd "$(dirname "$BATS_TEST_FILENAME")/../.." && pwd)"
    export SCRIPT="$PROJECT_ROOT/scripts/ratelimit_check.sh"
    export TEST_TMP="$(mktemp -d "$BATS_TMPDIR/ratelimit_check.XXXXXX")"
    export HOME="$TEST_TMP/home"
    mkdir -p "$HOME/.gemini" "$HOME/.config/opencode" "$HOME/.config/kilo" "$TEST_TMP/bin"

    cat > "$HOME/.gemini/settings.json" <<'JSON'
{"model":{"name":"gemini-3.1-pro-preview"}}
JSON
    cat > "$HOME/.gemini/projects.json" <<'JSON'
{"projects":{}}
JSON

    cat > "$TEST_TMP/settings.yaml" <<'YAML'
cli:
  agents:
    shogun:
      type: gemini
      model: gemini-3.1-pro-preview
    karo:
      type: opencode
      model: ollama/qwen3-coder:30b
    ashigaru1:
      type: kilo
      model: lmstudio/codellama-7b
    gunshi:
      type: localapi
      model: custom-local
YAML
    export CLI_ADAPTER_SETTINGS="$TEST_TMP/settings.yaml"

    cat > "$TEST_TMP/bin/tmux" <<'SH'
#!/bin/bash
if [[ "$*" == *"list-panes -a -F"* ]]; then
  cat <<'OUT'
multiagent:0.0 karo
multiagent:0.1 ashigaru1
gunshi:0.0 gunshi
OUT
  exit 0
fi
if [[ "$*" == *"display-message -t shogun:main -p #{@agent_cli}"* ]]; then
  printf 'gemini\n'
  exit 0
fi
if [[ "$*" == *"display-message -t shogun:main -p #{@model_name}"* ]]; then
  printf 'gemini-3.1-pro-preview\n'
  exit 0
fi
if [[ "$*" == *"display-message -t multiagent:0.0 -p #{@agent_cli}"* ]]; then
  printf 'opencode\n'
  exit 0
fi
if [[ "$*" == *"display-message -t multiagent:0.0 -p #{@model_name}"* ]]; then
  printf 'ollama/qwen3-coder:30b\n'
  exit 0
fi
if [[ "$*" == *"display-message -t multiagent:0.1 -p #{@agent_cli}"* ]]; then
  printf 'kilo\n'
  exit 0
fi
if [[ "$*" == *"display-message -t multiagent:0.1 -p #{@model_name}"* ]]; then
  printf 'lmstudio/codellama-7b\n'
  exit 0
fi
if [[ "$*" == *"display-message -t gunshi:0.0 -p #{@agent_cli}"* ]]; then
  printf 'localapi\n'
  exit 0
fi
if [[ "$*" == *"display-message -t gunshi:0.0 -p #{@model_name}"* ]]; then
  printf 'custom-local\n'
  exit 0
fi
exit 0
SH
    chmod +x "$TEST_TMP/bin/tmux"
    export PATH="$TEST_TMP/bin:$PATH"
}

teardown() {
    rm -rf "$TEST_TMP"
}

@test "ratelimit_check: Gemini/OpenCode/Kilo を専用セクションで表示する" {
    run bash "$SCRIPT" --lang en
    [ "$status" -eq 0 ]

    [[ "$output" == *"── Gemini CLI"* ]]
    [[ "$output" == *"Workspace state: detected (~/.gemini)"* ]]
    [[ "$output" == *"Quota: unavailable"* ]]
    [[ "$output" == *"── OpenCode"* ]]
    [[ "$output" == *"Workspace state: detected (~/.config/opencode)"* ]]
    [[ "$output" == *"── Kilo"* ]]
    [[ "$output" == *"Workspace state: detected (~/.config/kilo)"* ]]
    [[ "$output" == *"gunshi: localapi (custom-local) — no rate limit data"* ]]
}
