#!/usr/bin/env bash
set -euo pipefail

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)"
RUN_ID="${SHOGUNATE_SOURCE_SMOKE_RUN_ID:-source-runtime-smoke-$(date +%Y%m%d%H%M%S)}"
REF="${SHOGUNATE_SOURCE_SMOKE_REF:-HEAD}"
WORKTREE="${SHOGUNATE_SOURCE_SMOKE_WORKTREE:-$ROOT_DIR/runtime_sandboxes/$RUN_ID}"
SESSION="${SHOGUNATE_SOURCE_SMOKE_SESSION:-shogunate-mod-$RUN_ID}"
DAEMON="${SHOGUNATE_SOURCE_SMOKE_DAEMON_SESSION:-goza-runtime-shogunate-mod-$RUN_ID}"
TARGET_PROJECT="$WORKTREE/target-project"
KEEP_ON_FAIL="${SHOGUNATE_SOURCE_SMOKE_KEEP_ON_FAIL:-1}"
KEEP_ALWAYS="${SHOGUNATE_SOURCE_SMOKE_KEEP:-0}"

cleanup() {
  local status=$?
  if [[ "$KEEP_ALWAYS" = "1" || ( "$status" -ne 0 && "$KEEP_ON_FAIL" = "1" ) ]]; then
    printf '[INFO] keeping smoke artifacts: worktree=%s session=%s daemon=%s\n' "$WORKTREE" "$SESSION" "$DAEMON" >&2
    return "$status"
  fi

  tmux kill-session -t "$SESSION" 2>/dev/null || true
  tmux kill-session -t "$DAEMON" 2>/dev/null || true
  git -C "$ROOT_DIR" worktree remove --force "$WORKTREE" >/dev/null 2>&1 || true
  git -C "$ROOT_DIR" worktree prune >/dev/null 2>&1 || true
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
  [[ "$actual" = "$expected" ]] || fail "$option mismatch: expected '$expected', got '$actual'"
}

require_exact_lines() {
  local expected="$1"
  local actual="$2"
  [[ "$actual" = "$expected" ]] || fail "unexpected lines. expected: [$expected], got: [$actual]"
}

require_command git
require_command tmux

if [[ -e "$WORKTREE" ]]; then
  fail "worktree already exists: $WORKTREE"
fi

printf '[INFO] adding detached worktree: %s (%s)\n' "$WORKTREE" "$REF"
git -C "$ROOT_DIR" worktree add --detach "$WORKTREE" "$REF"
mkdir -p "$TARGET_PROJECT"

printf '[INFO] starting setup-only runtime smoke: %s\n' "$SESSION"
(
  cd "$WORKTREE"
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

printf '[PASS] source runtime smoke passed: session=%s worktree=%s target=%s\n' "$SESSION" "$WORKTREE" "$TARGET_PROJECT"
