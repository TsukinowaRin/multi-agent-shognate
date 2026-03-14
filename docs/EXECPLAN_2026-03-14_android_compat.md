# ExecPlan — upstream Android app compatibility check (2026-03-14)

## Goal
- Re-fetch upstream and verify whether the current tmux/goza architecture in this fork is compatible with the upstream Android companion app shipped in `android/release/multi-agent-shogun.apk`.

## Findings
- Upstream latest fetched: `upstream/main` = `7855af2` (`v4.1.3`).
- Upstream contains a full Android project under `android/` and a prebuilt APK at `android/release/multi-agent-shogun.apk`.
- Android app assumptions from source:
  - Shogun tab targets `"<shogunSession>:main"` and sends `tmux send-keys` / `capture-pane` there.
  - Agents tab targets `"<agentsSession>:0"` and enumerates pane indexes in that window.
  - Dashboard tab reads `<projectPath>/dashboard.md` over SSH.
  - Settings only expose two tmux session names: `shogun` and `multiagent`.
- Current fork assumptions:
  - Main runtime is `goza-no-ma` single session.
  - All agents live in one window (`goza-no-ma:overview`).
  - Direct pane focus is done with `@agent_id`, not by upstream session/window split.

## Compatibility judgment
- `dashboard.md` access remains compatible.
- Android app is **not directly compatible** with the current fork runtime.
- Main blockers:
  1. No `shogun:main` runtime target.
  2. No `multiagent:0` runtime target with agent-only panes.
  3. Android app cannot target `goza-no-ma` panes by `@agent_id`; it only knows session/window names.

## Options
1. Restore upstream-compatible split sessions (`shogun`, `multiagent`) and keep goza as mirror/view.
2. Add an Android compatibility mode that boots upstream-style tmux sessions in parallel.
3. Modify the Android app to understand `goza-no-ma` + `@agent_id` pane resolution.

## Recommendation
- Do not claim Android compatibility in the current fork.
- If compatibility is required, the least risky path is option 2 or 3.
- Option 1 reopens the runtime architecture split that this fork intentionally removed.
