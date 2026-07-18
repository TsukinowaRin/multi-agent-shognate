#!/usr/bin/env bash
set -euo pipefail

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)"
RUN_ID="${SHOGUNATE_UPSTREAM_OVERLAY_SMOKE_RUN_ID:-upstream-overlay-smoke-$(date +%Y%m%d%H%M%S)}"
UPSTREAM_REF="${SHOGUNATE_UPSTREAM_OVERLAY_REF:-upstream/main}"
WORKTREE="${SHOGUNATE_UPSTREAM_OVERLAY_WORKTREE:-$ROOT_DIR/runtime_sandboxes/$RUN_ID}"
SESSION="${SHOGUNATE_UPSTREAM_OVERLAY_SESSION:-shogunate-mod-$RUN_ID}"
DAEMON="${SHOGUNATE_UPSTREAM_OVERLAY_DAEMON_SESSION:-goza-runtime-shogunate-mod-$RUN_ID}"
TARGET_PROJECT="$WORKTREE/target-project"
KEEP_ON_FAIL="${SHOGUNATE_UPSTREAM_OVERLAY_KEEP_ON_FAIL:-1}"
KEEP_ALWAYS="${SHOGUNATE_UPSTREAM_OVERLAY_KEEP:-0}"
STUB_BIN=""

cleanup() {
  local status=$?
  if [[ "$KEEP_ALWAYS" = "1" || ( "$status" -ne 0 && "$KEEP_ON_FAIL" = "1" ) ]]; then
    printf '[INFO] keeping upstream overlay artifacts: worktree=%s session=%s daemon=%s\n' "$WORKTREE" "$SESSION" "$DAEMON" >&2
    return "$status"
  fi

  tmux kill-session -t "$SESSION" 2>/dev/null || true
  tmux kill-session -t "$DAEMON" 2>/dev/null || true
  git -C "$ROOT_DIR" worktree remove --force "$WORKTREE" >/dev/null 2>&1 || true
  git -C "$ROOT_DIR" worktree prune >/dev/null 2>&1 || true
  [[ -n "$STUB_BIN" ]] && rm -rf "$STUB_BIN"
}
trap cleanup EXIT

fail() {
  printf '[FAIL] %s\n' "$1" >&2
  exit 1
}

require_command() {
  command -v "$1" >/dev/null 2>&1 || fail "$1 is required"
}

require_file() {
  [[ -f "$1" ]] || fail "missing file: $1"
}

require_tmux_option() {
  local option="$1"
  local expected="$2"
  local actual
  actual="$(tmux show-options -t "$SESSION" -qv "$option" 2>/dev/null || true)"
  [[ "$actual" = "$expected" ]] || fail "$option mismatch: expected '$expected', got: '$actual'"
}

require_exact_lines() {
  local expected="$1"
  local actual="$2"
  [[ "$actual" = "$expected" ]] || fail "unexpected lines. expected: [$expected], got: [$actual]"
}

overlay_paths() {
  python3 - "$ROOT_DIR/shogunate_mod/manifest.yaml" <<'PY'
import sys

manifest = sys.argv[1]
paths = ["shogunate_mod"]
in_wrappers = False

with open(manifest, encoding="utf-8") as fh:
    for raw in fh:
        line = raw.rstrip("\n")
        if line == "compatibility_wrappers:":
            in_wrappers = True
            continue
        if in_wrappers:
            if line and not line.startswith("  "):
                break
            stripped = line.strip()
            if stripped.startswith("- "):
                paths.append(stripped[2:])

for path in paths:
    print(path)
PY
}

require_overlay_status_is_mod_only() {
  local status
  local bad
  status="$(git -C "$WORKTREE" status --short --untracked-files=all)"
  bad="$(
    OVERLAY_STATUS="$status" python3 - "$ROOT_DIR/shogunate_mod/manifest.yaml" <<'PY'
import os
import sys

manifest = sys.argv[1]
allowed = ["shogunate_mod/"]
in_wrappers = False

with open(manifest, encoding="utf-8") as fh:
    for raw in fh:
        line = raw.rstrip("\n")
        if line == "compatibility_wrappers:":
            in_wrappers = True
            continue
        if in_wrappers:
            if line and not line.startswith("  "):
                break
            stripped = line.strip()
            if stripped.startswith("- "):
                allowed.append(stripped[2:])

for raw in os.environ["OVERLAY_STATUS"].splitlines():
    path = raw[3:].strip()
    if " -> " in path:
        path = path.split(" -> ", 1)[1]
    if not any(path == item or path.startswith(item) for item in allowed):
        print(raw.rstrip("\n"))
PY
  )"
  [[ -z "$bad" ]] || fail "overlay changed non-MOD/non-wrapper root paths before runtime start:
$bad"
}

require_command git
require_command python3
require_command tar
require_command tmux

git -C "$ROOT_DIR" rev-parse --verify "$UPSTREAM_REF" >/dev/null 2>&1 \
  || fail "$UPSTREAM_REF is required; run: git fetch upstream main:refs/remotes/upstream/main"

if [[ -e "$WORKTREE" ]]; then
  fail "worktree already exists: $WORKTREE"
fi

printf '[INFO] adding upstream core worktree: %s (%s)\n' "$WORKTREE" "$UPSTREAM_REF"
git -C "$ROOT_DIR" worktree add --detach "$WORKTREE" "$UPSTREAM_REF"
mkdir -p "$TARGET_PROJECT"

printf '[INFO] overlaying Shogunate MOD and compatibility wrappers\n'
mapfile -t paths < <(overlay_paths)
git -C "$ROOT_DIR" archive --format=tar HEAD -- "${paths[@]}" | tar -xf - -C "$WORKTREE"
require_overlay_status_is_mod_only

# CI には実 CLI が存在せず、resolve_cli_type_for_agent の可用性フォールバックが
# localapi を選んで agent_cli.tsv の期待値(claude)と食い違う。この smoke の関心は
# 「設定どおりの CLI が選ばれること」なので、stub の claude を PATH 先頭へ置いて
# ホスト環境に依存せず可用性判定を通す(worktree 外に置き、overlay 検査を汚さない)。
STUB_BIN="$(mktemp -d "${TMPDIR:-/tmp}/shogunate-smoke-stub.XXXXXX")"
printf '#!/usr/bin/env bash\nexec sleep 3600\n' > "$STUB_BIN/claude"
chmod +x "$STUB_BIN/claude"

printf '[INFO] starting upstream-overlay runtime smoke: %s\n' "$SESSION"
(
  cd "$WORKTREE"
  PATH="$STUB_BIN:$PATH" \
  SHOGUNATE_PROJECT_DIR="$TARGET_PROJECT" \
  SHOGUNATE_SESSION_NAME="$SESSION" \
  GOZA_SESSION_NAME="$SESSION" \
  LEGACY_GOZA_SESSION_NAME="${SESSION}-legacy" \
  RUNTIME_DAEMON_SESSION="$DAEMON" \
  MAS_BOOTSTRAP_READY_TIMEOUT="${MAS_BOOTSTRAP_READY_TIMEOUT:-3}" \
    bash shutsujin_departure.sh -s -c
)

tmux has-session -t "$SESSION" 2>/dev/null || fail "tmux session was not created: $SESSION"
tmux list-windows -t "$SESSION" -F '#{window_name}' | grep -Fxq goza || fail "goza window missing"

require_tmux_option "@shogunate_project_dir" "$TARGET_PROJECT"
require_tmux_option "@shogunate_runtime_dir" "$WORKTREE"

agents="$(
  tmux list-panes -t "$SESSION:goza" -F '#{@agent_id}' \
    | sed '/^$/d' \
    | sort
)"
require_exact_lines $'ashigaru1\ngunkan\ngunshi\nkaro\nshogun' "$agents"

agent_cli="$WORKTREE/queue/runtime/agent_cli.tsv"
require_file "$agent_cli"
require_exact_lines $'ashigaru1\tclaude\ngunkan\tclaude\ngunshi\tclaude\nkaro\tclaude\nshogun\tclaude' "$(sort "$agent_cli")"

require_file "$WORKTREE/dashboard.md"
require_file "$WORKTREE/queue/inbox/gunkan.yaml"
require_file "$WORKTREE/queue/reports/gunkan_report.yaml"

printf '[PASS] upstream overlay runtime smoke passed: upstream=%s session=%s worktree=%s target=%s\n' "$UPSTREAM_REF" "$SESSION" "$WORKTREE" "$TARGET_PROJECT"
