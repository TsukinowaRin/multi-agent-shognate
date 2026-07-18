#!/usr/bin/env bats

setup() {
  TEST_TMP="$(mktemp -d)"
  PROJECT_ROOT="$(cd "$(dirname "$BATS_TEST_FILENAME")/../.." && pwd)"

  mkdir -p "$TEST_TMP/scripts" "$TEST_TMP/config" "$TEST_TMP/shogunate_mod/configure"
  cp "$PROJECT_ROOT/scripts/configure_runtime_roles.py" "$TEST_TMP/scripts/configure_runtime_roles.py"
  cp "$PROJECT_ROOT/shogunate_mod/configure/runtime_roles.py" "$TEST_TMP/shogunate_mod/configure/runtime_roles.py"
  chmod +x "$TEST_TMP/scripts/configure_runtime_roles.py"
  chmod +x "$TEST_TMP/shogunate_mod/configure/runtime_roles.py"

  cat > "$TEST_TMP/config/settings.yaml" <<'YAML'
language: ja
shell: bash
multiplexer:
  default: tmux
topology:
  active_ashigaru:
    - ashigaru1
cli:
  default: codex
  agents:
    shogun:
      type: codex
      model: gpt-5.5
      reasoning_effort: high
      thinking: false
      fallback:
        type: opencode
        model: fallback/model
    gunkan:
      type: codex
      model: gpt-5.5
    gunshi:
      type: codex
      model: gpt-5.5
    karo:
      type: codex
      model: gpt-5.5
      reasoning_effort: high
    ashigaru1:
      type: antigravity
      model: gemini-3.1-pro-preview
    ashigaru2:
      type: codex
      model: gpt-5.5
    ashigaru4:
      type: opencode
      model: stale/model
  commands:
    antigravity: "agy --dangerously-skip-permissions"
    opencode: "opencode"
YAML
}

teardown() {
  rm -rf "$TEST_TMP"
}

@test "configure_runtime_roles: CLI種別と足軽数だけを保存し model prefs を削除する" {
  run bash -lc "cd '$TEST_TMP' && python3 scripts/configure_runtime_roles.py --ashigaru-count 3 --shogun antigravity --gunkan codex --karo codex --gunshi codex --ashigaru1 codex --ashigaru2 opencode --ashigaru3 opencode"
  [ "$status" -eq 0 ]

  run python3 - "$TEST_TMP/config/settings.yaml" <<'PY'
import sys, yaml
with open(sys.argv[1], encoding='utf-8') as fh:
    cfg = yaml.safe_load(fh)
assert cfg["cli"]["default"] == "codex"
assert cfg["topology"]["active_ashigaru"] == ["ashigaru1", "ashigaru2", "ashigaru3"]
assert cfg["topology"]["karo"] == {"mode": "auto", "max_ashigaru_per_karo": 6}
agents = cfg["cli"]["agents"]
assert agents["shogun"] == {"type": "antigravity", "fallback": {"type": "opencode", "model": "fallback/model"}}
assert agents["gunkan"] == {"type": "codex"}
assert agents["gunshi"] == {"type": "codex"}
assert agents["karo"] == {"type": "codex"}
assert agents["ashigaru1"] == {"type": "codex"}
assert agents["ashigaru2"] == {"type": "opencode"}
assert agents["ashigaru3"] == {"type": "opencode"}
assert "ashigaru4" not in agents
assert cfg["cli"]["commands"]["opencode"] == "opencode"
print("ok")
PY
  [ "$status" -eq 0 ]
}

@test "configure_runtime_roles: 対話入力でも model 入力なしで保存する" {
  run bash -lc "cd '$TEST_TMP' && printf '%s\n' \
    'codex' \
    'antigravity' \
    'codex' \
    'opencode' \
    'kilo' \
    '2' \
    'claude' \
    'localapi' \
    | python3 scripts/configure_runtime_roles.py >/dev/null"
  [ "$status" -eq 0 ]

  run python3 - "$TEST_TMP/config/settings.yaml" <<'PY'
import sys, yaml
with open(sys.argv[1], encoding='utf-8') as fh:
    cfg = yaml.safe_load(fh)
assert cfg["cli"]["default"] == "codex"
assert cfg["topology"]["active_ashigaru"] == ["ashigaru1", "ashigaru2"]
agents = cfg["cli"]["agents"]
assert agents["shogun"] == {"type": "antigravity", "fallback": {"type": "opencode", "model": "fallback/model"}}
assert agents["gunkan"] == {"type": "codex"}
assert agents["karo"] == {"type": "opencode"}
assert agents["gunshi"] == {"type": "kilo"}
assert agents["ashigaru1"] == {"type": "claude"}
assert agents["ashigaru2"] == {"type": "localapi"}
print("ok")
PY
  [ "$status" -eq 0 ]
}

@test "configure_runtime_roles: 対話プロンプトは core roles の後に足軽人数を聞く" {
  run bash -lc "cd '$TEST_TMP' && printf '%s\n' \
    'codex' \
    'antigravity' \
    'codex' \
    'opencode' \
    'kilo' \
    '1' \
    'claude' \
    | python3 scripts/configure_runtime_roles.py"
  [ "$status" -eq 0 ]

  run python3 - "$output" <<'PY'
import sys
out = sys.argv[1]
labels = [
    "cli.default を選択",
    "shogun の CLI を選択",
    "gunkan の CLI を選択",
    "karo の CLI を選択",
    "gunshi の CLI を選択",
    "足軽人数を入力",
    "ashigaru1 の CLI を選択",
]
positions = [out.index(label) for label in labels]
assert positions == sorted(positions), positions
PY
  [ "$status" -eq 0 ]
}

@test "configure_runtime_roles: --preserve-model-prefs では既存詳細設定を残す" {
  run bash -lc "cd '$TEST_TMP' && python3 scripts/configure_runtime_roles.py --preserve-model-prefs --ashigaru-count 1 --shogun codex --gunkan codex --gunshi codex --karo codex --ashigaru1 antigravity"
  [ "$status" -eq 0 ]

  run python3 - "$TEST_TMP/config/settings.yaml" <<'PY'
import sys, yaml
with open(sys.argv[1], encoding='utf-8') as fh:
    cfg = yaml.safe_load(fh)
agents = cfg["cli"]["agents"]
assert agents["shogun"]["type"] == "codex"
assert agents["shogun"]["model"] == "gpt-5.5"
assert agents["shogun"]["thinking"] is False
assert agents["shogun"]["fallback"] == {"type": "opencode", "model": "fallback/model"}
assert agents["gunkan"]["type"] == "codex"
assert agents["gunkan"]["model"] == "gpt-5.5"
assert agents["ashigaru1"]["type"] == "antigravity"
assert agents["ashigaru1"]["model"] == "gemini-3.1-pro-preview"
assert "thinking_level" not in agents["ashigaru1"]
print("ok")
PY
  [ "$status" -eq 0 ]
}

@test "configure_runtime_roles: Fallbackを明示設定・解除できる" {
  run bash -lc "cd '$TEST_TMP' && python3 scripts/configure_runtime_roles.py --ashigaru-count 1 --shogun codex --shogun-fallback kilo --gunkan codex --gunkan-fallback none --karo codex --gunshi codex --ashigaru1 antigravity --ashigaru1-fallback cursor"
  [ "$status" -eq 0 ]

  run python3 - "$TEST_TMP/config/settings.yaml" <<'PY'
import sys, yaml
cfg = yaml.safe_load(open(sys.argv[1], encoding='utf-8'))
agents = cfg["cli"]["agents"]
assert agents["shogun"]["fallback"] == {"type": "kilo", "model": "fallback/model"}
assert agents["gunkan"]["fallback"] is None
assert agents["ashigaru1"]["fallback"] == {"type": "cursor"}
PY
  [ "$status" -eq 0 ]
}

@test "configure_runtime_roles: 壊れた設定は上書きしない" {
  printf 'cli: [broken\n' > "$TEST_TMP/config/settings.yaml"
  before="$(sha256sum "$TEST_TMP/config/settings.yaml" | awk '{print $1}')"
  run bash -lc "cd '$TEST_TMP' && python3 scripts/configure_runtime_roles.py --ashigaru-count 1 --shogun codex"
  [ "$status" -ne 0 ]
  after="$(sha256sum "$TEST_TMP/config/settings.yaml" | awk '{print $1}')"
  [ "$before" = "$after" ]
}

@test "configure_runtime_roles: secret-like Fallback fieldを含む設定は上書きしない" {
  python3 - "$TEST_TMP/config/settings.yaml" <<'PY'
import sys, yaml
path = sys.argv[1]
cfg = yaml.safe_load(open(path, encoding='utf-8'))
cfg['cli']['agents']['shogun']['fallback']['api_token'] = 'do-not-copy'
open(path, 'w', encoding='utf-8').write(yaml.safe_dump(cfg, sort_keys=False))
PY
  before="$(sha256sum "$TEST_TMP/config/settings.yaml" | awk '{print $1}')"
  run bash -lc "cd '$TEST_TMP' && python3 scripts/configure_runtime_roles.py --ashigaru-count 1 --shogun codex"
  [ "$status" -ne 0 ]
  after="$(sha256sum "$TEST_TMP/config/settings.yaml" | awk '{print $1}')"
  [ "$before" = "$after" ]
}
