# ExecPlan — upstream Android app compatibility (2026-03-14)

## Goal
- Keep `goza-no-ma` as the real tmux runtime.
- Add Android-compatible tmux targets without breaking the existing goza workflow.

## Constraints
- Android app expects fixed tmux targets:
  - `shogun:main`
  - `multiagent:0`
- `goza-no-ma` must remain the primary session used by `cgo` and direct operator control.

## Decision
- Restore `goza-no-ma:overview` as the real runtime.
- Add proxy sessions `shogun`, `gunshi`, `multiagent` that mirror input/output for the Android app.
- Keep watcher/runtime sync/focus helpers anchored on `goza-no-ma`.

## Implemented
- `shutsujin_departure.sh` now rebuilds `goza-no-ma:overview` as the main runtime.
- `scripts/goza_no_ma.sh` now opens the real `goza-no-ma` session again.
- `scripts/android_tmux_proxy.py` bridges Android `capture-pane` / `send-keys` to the real goza panes.
- `shutsujin_departure.sh` now also creates Android-compatible proxy sessions:
  - `shogun:main`
  - `gunshi:main`
  - `multiagent:agents`
- `scripts/focus_agent_pane.sh`, `scripts/watcher_supervisor.sh`, and `scripts/sync_runtime_cli_preferences.py` now treat `goza-no-ma` as the source of truth.

## Verification
- Static tests and tmux smoke must confirm:
  - `goza-no-ma:overview` contains the real agent panes
  - Android-compatible proxy sessions exist
  - watcher/runtime sync resolve panes from `goza-no-ma` first
