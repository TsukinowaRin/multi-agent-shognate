#!/usr/bin/env bash
set -euo pipefail

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
cd "$ROOT_DIR"

fail() {
  printf '[FAIL] %s\n' "$1" >&2
  exit 1
}

printf '[INFO] prepublish check start\n'

tracked_forbidden="$(git ls-files | rg '^(Waste/|_trash/|_upstream_reference/|docs/(WORKLOG|HANDOVER|UPSTREAM_SYNC)|config/settings.yaml|dashboard.md|queue/)' || true)"
if [[ -n "$tracked_forbidden" ]]; then
  printf '[FAIL] forbidden tracked paths detected:\n%s\n' "$tracked_forbidden" >&2
  exit 1
fi

private_hits="$(git grep -n -I -E '/mnt/[a-z]/|[A-Za-z]:\\\\|192\\.168\\.|172\\.31\\.|100\\.[0-9]+\\.[0-9]+\\.[0-9]+|muro' -- . ':(exclude)docs/PUBLISHING.md' || true)"
if [[ -n "$private_hits" ]]; then
  printf '[FAIL] possible local/private values detected:\n%s\n' "$private_hits" >&2
  exit 1
fi

dirty="$(git status --short || true)"
if [[ -n "$dirty" ]]; then
  printf '[FAIL] worktree is dirty:\n%s\n' "$dirty" >&2
  exit 1
fi

printf '[PASS] prepublish check passed\n'
