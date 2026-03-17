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

if ! git check-ignore -q config/settings.yaml; then
  fail "config/settings.yaml must remain ignored (local values such as ntfy_topic must not be published)"
fi

private_hits="$(
  git grep -n -I -E \
    '/mnt/d/Git_WorkSpace|D:\\\\Git_WorkSpace|/mnt/c/Users/muro|100\\.71\\.16\\.5|172\\.31\\.8\\.112|192\\.168\\.1\\.2|muro@MURO' \
    -- . ':(exclude)docs/PUBLISHING.md' ':(exclude)scripts/prepublish_check.sh' || true
)"
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
