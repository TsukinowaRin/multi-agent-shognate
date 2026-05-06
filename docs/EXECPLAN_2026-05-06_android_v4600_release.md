# Android v4.6.0.0 Release

## Context

実 Git repo は `multi-agent-shognate/`。作業ブランチは `codex/upstream-v4.6.0-sync`。直前に `upstream/main` (`4ee1377`, tag `v4.6.0`) を merge 済みで、merge commit は `217e2fa`。

今回の release tag は、既存ルール `android-v<upstream-version>.<fork-revision>` に従い `android-v4.6.0.0` とする。配布 asset は `multi-agent-shognate-android-v4.6.0.0.apk` と `multi-agent-shognate-installer-v4.6.0.0.bat`。

## Scope

対象:
- 不要な一時フォルダ / ignored cache の削除。
- Android `versionCode` / `versionName` と release docs の `v4.6.0.0` 整合。
- Android unit test / release APK build。
- host 側 syntax / focused Bats / prepublish check。
- GitHub Release 作成と asset 添付。

対象外:
- main への直接 push。
- Android Play Store 署名。
- live tmux runtime の長時間 burn-in。

## Acceptance Criteria

- `template-temp` など不要一時ファイルを削除する。
- `android/app/build.gradle.kts` が `versionName = "4.6.0"` へ更新される。
- README / Android README / release workflow の古い `v4.4.1` 例が `v4.6.0.0` 基準へ更新される。
- `cd android && ./gradlew --no-daemon test assembleRelease` が PASS する。
- release asset を `dist/` に作成できる。
- `bash scripts/prepublish_check.sh` が PASS する。
- GitHub Release `android-v4.6.0.0` が作成され、APK / installer が添付される。

## Steps

1. release version と docs を更新する。
2. 不要な一時ファイルを削除する。
3. host 側の焦点テストを再実行する。
4. Android unit test と release APK build を実行する。
5. release assets を生成し、artifact 名を確認する。
6. commit して branch を push する。
7. GitHub Release `android-v4.6.0.0` を作成し、asset を upload する。

## Progress

- [x] 2026-05-06 20:18 JST: release tag は未作成であることを確認。
- [x] version / docs 更新。
- [x] 一時ファイル削除。
- [x] host / Android 検証。
- [x] release asset 生成。
- [ ] commit / push / release。

## Decision Log

- Decision: `android-v4.6.0.0` を今回の release tag とする。
  Rationale: upstream baseline が `v4.6.0` へ更新され、同 baseline の fork release 初回なので fork revision は `.0` が自然。
  Date/Author: 2026-05-06 Codex
- Decision: main へ直接 push せず、作業ブランチと tag / release で公開する。
  Rationale: repo rule が main/master 直接 push を禁止しているため。
  Date/Author: 2026-05-06 Codex

## Outcomes

- Temporary cleanup:
  - `../template-temp`, `.shogunate/codex_probe_home`, stale `android/app/build`, stale `android/.gradle-home/.tmp`, stale `android/.gradle-user-home/.tmp` を削除。
  - `../Shogunate-test/.codex-home/{.tmp,tmp}` は別 clone の local runtime state と判断し、触らず残した。
- Version / release alignment:
  - `android/app/build.gradle.kts`: `versionCode = 6`, `versionName = "4.6.0"`。
  - README / README_ja / Android release README / workflow examples を `android-v4.6.0.0` へ更新。
- Verification:
  - `python3 -m json.tool .claude/settings.json` → PASS
  - `bash -n scripts/inbox_write.sh scripts/inbox_watcher.sh lib/cli_adapter.sh shutsujin_departure.sh scripts/session_start_hook.sh scripts/switch_cli.sh` → PASS
  - `python3 -m py_compile scripts/dashboard-viewer.py` → PASS
  - `git diff --check` → PASS
  - `bats tests/test_inbox_write.bats tests/unit/test_cli_adapter.bats tests/unit/test_switch_cli.bats tests/unit/test_stop_hook.bats tests/agent_selfwatch.bats` → PASS (`177` tests)
  - `cd android && GRADLE_USER_HOME="$PWD/.gradle-user-home" ./gradlew --no-daemon test assembleRelease` → initial FAIL because `/home/muro/.gradle` was read-only.
  - `cd android && HOME="$PWD/.home" ANDROID_USER_HOME="$PWD/.android-user-home" GRADLE_USER_HOME="$PWD/.gradle-user-home" ./gradlew --no-daemon test assembleRelease` → PASS (`73` tasks; warnings only)
  - `aapt dump badging dist/multi-agent-shognate-android-v4.6.0.0.apk` → `versionCode='6'`, `versionName='4.6.0'`, `application-label:'multi-agent-shognate Android'`
- Release assets generated:
  - `dist/multi-agent-shognate-android-v4.6.0.0.apk`
  - `dist/multi-agent-shognate-installer-v4.6.0.0.bat`
  - APK sha256: `1b5357c70b64a31ad4d417686c3f78eb0729802fe51e517d8d4e799cc56a6bd8`
  - Installer sha256: `a65dd6856279adf8269145ffc9bf3fc21c402295019f184b92c4b30395112bca`
