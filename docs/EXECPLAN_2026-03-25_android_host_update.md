# ExecPlan: Android-triggered Host Update

- date: 2026-03-25
- status: completed

## Goal

Allow the Android APK to trigger **host-side Shogunate updates** without trying to hot-update a running tmux runtime.

## Decisions

1. The APK must not update itself. APK distribution remains GitHub Releases.
2. Host updates must be deferred until after Shogunate is stopped, or consumed on next startup.
3. The host-side source of truth is `scripts/update_manager.py`.
4. Android UI should stay inside `Settings` and remain minimal.

## Implemented

- Added pending update queue/apply subcommands to `scripts/update_manager.py`
  - `queue-update`
  - `apply-pending`
- Added pending update status output to `status`
- Added startup consumption in `shutsujin_departure.sh`
- Added `scripts/stop_and_apply_update.sh`
  - queue update
  - stop tmux sessions
  - apply pending update
  - optional restart
- Added Android Settings UI for:
  - status check
  - upstream dry-run preview
  - stop-and-apply Release update
  - stop-and-apply upstream import
- Added unit coverage for pending update queue/apply behavior

## Validation

- `python3 -m unittest tests.unit.test_update_manager`
- `bash -n shutsujin_departure.sh scripts/stop_and_apply_update.sh`
- `python3 -m py_compile scripts/update_manager.py`
- `cd android && GRADLE_USER_HOME=$PWD/.gradle-user-home ./gradlew --no-daemon assembleDebug`

## Notes

- The Android app now updates the **host** over SSH. It does not self-update.
- Running-session hot update remains intentionally unsupported.
