# ExecPlan — upstream Android app compatibility (2026-03-14)

## Goal
- Make this fork work with the upstream Android app without modifying the app.

## Constraints
- Android app expects fixed tmux targets:
  - `shogun:main`
  - `multiagent:0`
- The app does not understand `goza-no-ma` or pane lookup by `@agent_id`.

## Decision
- Restore upstream-compatible split sessions as the real runtime.
- Demote `goza-no_ma.sh` to a view session over the existing backend.
- Keep this fork's CLI extensions, bridges, watcher hardening, and runtime preference sync.

## Implemented
- `shutsujin_departure.sh` now builds:
  - `shogun:main`
  - `gunshi:main`
  - `multiagent:agents`
- `scripts/goza_no_ma.sh` now opens a view session over the split backend.
- `scripts/focus_agent_pane.sh` now jumps to the real split-session targets.
- `scripts/watcher_supervisor.sh` and `scripts/sync_runtime_cli_preferences.py` now prefer split sessions over `goza-no-ma`.

## Verification
- Static tests and tmux setup smoke must confirm the split targets exist and carry `@agent_id`/`@model_name`.
