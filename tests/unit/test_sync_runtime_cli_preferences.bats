#!/usr/bin/env bats

source "$BATS_TEST_DIRNAME/../helpers/search_helper.bash"

setup() {
  TEST_TMP="$(mktemp -d)"
  PROJECT_ROOT="$(cd "$(dirname "$BATS_TEST_FILENAME")/../.." && pwd)"

  cat > "$TEST_TMP/settings.yaml" <<'YAML'
cli:
  default: gemini
  agents:
    shogun:
      type: gemini
      model: auto
    karo:
      type: codex
      model: auto
      reasoning_effort: auto
topology:
  active_ashigaru:
    - ashigaru1
YAML

  cat > "$TEST_TMP/gemini_aliases.tsv" <<'TSV'
agent_id	alias	base_model	thinking_level	thinking_budget	warnings
shogun	mas-shogun	gemini-3-pro-preview	HIGH		
TSV

  cat > "$TEST_TMP/tmux" <<'SH'
#!/usr/bin/env bash
set -euo pipefail
cmd="$1"
shift
case "$cmd" in
  has-session)
    target="$2"
    case "$target" in
      shogun|multiagent) exit 0 ;;
      *) exit 1 ;;
    esac
    ;;
  show-options)
    target="$3"
    option="${5:-}"
    case "$target:$option" in
      shogun:main:@agent_cli) printf 'gemini\n' ;;
      multiagent:agents.0:@agent_id) printf 'karo\n' ;;
      multiagent:agents.0:@agent_cli) printf 'codex\n' ;;
    esac
    ;;
  list-panes)
    printf 'multiagent:agents.0\n'
    ;;
  capture-pane)
    target="$4"
    case "$target" in
      shogun:main)
        cat <<'OUT'
YOLO ctrl+y
/model mas-shogun
OUT
        ;;
      multiagent:agents.0)
        cat <<'OUT'
gpt-5.4 high · 94% left · /mnt/d/repo
OUT
        ;;
    esac
    ;;
  *)
    exit 1
    ;;
esac
SH
  chmod +x "$TEST_TMP/tmux"

  export MAS_SETTINGS_PATH="$TEST_TMP/settings.yaml"
  export MAS_RUNTIME_PREFS_SUMMARY_PATH="$TEST_TMP/runtime_cli_prefs.tsv"
  export MAS_GEMINI_SUMMARY_PATH="$TEST_TMP/gemini_aliases.tsv"
  export TMUX_BIN="$TEST_TMP/tmux"
}

teardown() {
  rm -rf "$TEST_TMP"
}

@test "sync_runtime_cli_preferences: codex と gemini alias を settings へ同期する" {
  run python3 "$PROJECT_ROOT/scripts/sync_runtime_cli_preferences.py"
  [ "$status" -eq 0 ]

  run python3 - "$MAS_SETTINGS_PATH" <<'PY'
import sys, yaml
with open(sys.argv[1], encoding='utf-8') as fh:
    cfg = yaml.safe_load(fh) or {}
shogun = cfg['cli']['agents']['shogun']
karo = cfg['cli']['agents']['karo']
assert shogun['model'] == 'gemini-3-pro-preview'
assert shogun['thinking_level'] == 'high'
assert karo['model'] == 'gpt-5.4'
assert karo['reasoning_effort'] == 'high'
print('ok')
PY
  [ "$status" -eq 0 ]

  run bats_search "shogun\tgemini\tmas-shogun|karo\tcodex\tgpt-5.4\thigh" "$MAS_RUNTIME_PREFS_SUMMARY_PATH"
  [ "$status" -eq 0 ]
}

@test "sync_runtime_cli_preferences: session が無ければ no-op" {
  cat > "$TEST_TMP/tmux" <<'SH'
#!/usr/bin/env bash
exit 1
SH
  chmod +x "$TEST_TMP/tmux"

  run python3 "$PROJECT_ROOT/scripts/sync_runtime_cli_preferences.py"
  [ "$status" -eq 0 ]
  run bats_search "no-running-tmux-agents" "$MAS_RUNTIME_PREFS_SUMMARY_PATH"
  [ "$status" -eq 0 ]
}

@test "sync_runtime_cli_preferences: type は live pane から自動上書きしない" {
  cat > "$TEST_TMP/settings.yaml" <<'YAML'
cli:
  default: gemini
  agents:
    shogun:
      type: gemini
      model: auto
YAML
  cat > "$TEST_TMP/tmux" <<'SH'
#!/usr/bin/env bash
set -euo pipefail
cmd="$1"
shift
case "$cmd" in
  has-session)
    [[ "$2" == "shogun" ]] && exit 0 || exit 1
    ;;
  show-options)
    printf 'claude\n'
    ;;
  capture-pane)
    cat <<'OUT'
Claude Code running
OUT
    ;;
  *)
    exit 1
    ;;
esac
SH
  chmod +x "$TEST_TMP/tmux"

  run python3 "$PROJECT_ROOT/scripts/sync_runtime_cli_preferences.py"
  [ "$status" -eq 0 ]

  run python3 - "$MAS_SETTINGS_PATH" <<'PY'
import sys, yaml
with open(sys.argv[1], encoding='utf-8') as fh:
    cfg = yaml.safe_load(fh) or {}
assert cfg['cli']['agents']['shogun']['type'] == 'gemini'
assert cfg['cli']['agents']['shogun']['model'] == 'auto'
print('ok')
PY
  [ "$status" -eq 0 ]

  run bats_search "configured-type=gemini, running-cli=claude" "$MAS_RUNTIME_PREFS_SUMMARY_PATH"
  [ "$status" -eq 0 ]
}

@test "sync_runtime_cli_preferences: 非アクティブ足軽は再生成しない" {
  cat > "$TEST_TMP/settings.yaml" <<'YAML'
cli:
  default: codex
  agents:
    karo:
      type: codex
      model: auto
      reasoning_effort: auto
topology:
  active_ashigaru:
    - ashigaru1
    - ashigaru2
YAML
  cat > "$TEST_TMP/tmux" <<'SH'
#!/usr/bin/env bash
set -euo pipefail
cmd="$1"
shift
case "$cmd" in
  has-session)
    [[ "$2" == "multiagent" ]] && exit 0 || exit 1
    ;;
  list-panes)
    printf 'multiagent:agents.0\nmultiagent:agents.1\n'
    ;;
  show-options)
    target="$3"
    option="${5:-}"
    case "$target:$option" in
      multiagent:agents.0:@agent_id) printf 'karo\n' ;;
      multiagent:agents.0:@agent_cli) printf 'codex\n' ;;
      multiagent:agents.1:@agent_id) printf 'ashigaru8\n' ;;
      multiagent:agents.1:@agent_cli) printf 'codex\n' ;;
    esac
    ;;
  capture-pane)
    target="$4"
    case "$target" in
      multiagent:agents.0)
        printf 'gpt-5.4 high · 94%% left · /mnt/d/repo\n'
        ;;
      multiagent:agents.1)
        printf 'gpt-5.4 low · 90%% left · /mnt/d/repo\n'
        ;;
    esac
    ;;
  *)
    exit 1
    ;;
esac
SH
  chmod +x "$TEST_TMP/tmux"

  run python3 "$PROJECT_ROOT/scripts/sync_runtime_cli_preferences.py"
  [ "$status" -eq 0 ]

  run python3 - "$MAS_SETTINGS_PATH" <<'PY'
import sys, yaml
with open(sys.argv[1], encoding='utf-8') as fh:
    cfg = yaml.safe_load(fh) or {}
agents = cfg['cli']['agents']
assert 'ashigaru8' not in agents
assert agents['karo']['model'] == 'gpt-5.4'
print('ok')
PY
  [ "$status" -eq 0 ]

  run bats_search "ashigaru8\tcodex\t\t\t\t\tnot-configured-skip" "$MAS_RUNTIME_PREFS_SUMMARY_PATH"
  [ "$status" -eq 0 ]
}

@test "sync_runtime_cli_preferences: gemini に不正な gpt 系 model が入っていても auto に矯正する" {
  cat > "$TEST_TMP/settings.yaml" <<'YAML'
cli:
  default: gemini
  agents:
    shogun:
      type: gemini
      model: gpt-5.4
YAML
  cat > "$TEST_TMP/tmux" <<'SH'
#!/usr/bin/env bash
set -euo pipefail
cmd="$1"
shift
case "$cmd" in
  has-session)
    [[ "$2" == "shogun" ]] && exit 0 || exit 1
    ;;
  show-options)
    target="$3"
    option="${5:-}"
    case "$target:$option" in
      shogun:main:@agent_cli) printf 'gemini\n' ;;
    esac
    ;;
  capture-pane)
    cat <<'OUT'
YOLO ctrl+y
/model Auto (Gemini 3)
OUT
    ;;
  *)
    exit 1
    ;;
esac
SH
  chmod +x "$TEST_TMP/tmux"

  run python3 "$PROJECT_ROOT/scripts/sync_runtime_cli_preferences.py"
  [ "$status" -eq 0 ]

  run python3 - "$MAS_SETTINGS_PATH" <<'PY'
import sys, yaml
with open(sys.argv[1], encoding='utf-8') as fh:
    cfg = yaml.safe_load(fh) or {}
assert cfg['cli']['agents']['shogun']['type'] == 'gemini'
assert cfg['cli']['agents']['shogun']['model'] == 'auto'
print('ok')
PY
  [ "$status" -eq 0 ]

  run bats_search "invalid-gemini-model-reset=gpt-5.4" "$MAS_RUNTIME_PREFS_SUMMARY_PATH"
  [ "$status" -eq 0 ]
}
