# Android Agent Targeting

## Context

Android App には過去 release から `shogun` / `gunshi` / `multiagent` の Android 互換 tmux session を読む導線がある。現状の将軍タブは `shogun:main` 固定で、エージェントタブでは pane を開けば個別送信できるが、遠隔の司令画面として「任意の家来に話しかける」操作が分散している。

現在の runtime は `goza-no-ma` が正本で、Android 互換 session は proxy。したがって Android 側は pane 番号ではなく `@agent_id` を使って送信先を決める必要がある。

追加要求として、SSH 接続セットアップも楽にしたい。安全側に倒し、Android から host を勝手に設定するのではなく、host 側で Tailscale / USB adb reverse 用の接続プロファイル JSON を明示発行し、Android 側で取り込む。

## Scope

対象:
- Android 将軍タブの送信先選択 UI。
- Android `ShogunViewModel` の agent 一覧 / capture / send 経路。
- host 側 bridge script。
- Android README / docs / unit tests。
- Tailscale / USB 用の接続プロファイル発行 script。

対象外:
- Play Store 署名。
- Android 互換 session の廃止。
- live runtime の破壊的停止。
- password / private key / token の QR 化や自動配布。

## Acceptance Criteria

- `scripts/android_agent_bridge.sh list` が `@agent_id` ベースで agent 一覧を TSV 出力する。
- `scripts/android_agent_bridge.sh capture shogun` が将軍 pane を capture する。
- `scripts/android_agent_bridge.sh send-b64 <agent_id> <base64>` が本文を literal send して Enter を押す。
- Android 将軍タブは既定で将軍を選択し、agent chip で家老・軍師・足軽へ切り替えられる。
- bridge が使えない場合、既存の `shogun:main` fallback を維持する。
- `scripts/android_pairing_profile.sh --mode tailscale|usb` が secrets を含まない接続プロファイルを出力する。
- Android 設定画面で接続プロファイル JSON を取り込める。
- `bash -n`、Bats、Android unit test が PASS する。

## Work Breakdown

1. 要件を `docs/REQS.md` に正規化する。
2. host bridge script と Bats を追加する。
3. Android target parser utility と unit test を追加する。
4. `ShogunViewModel` を agent target aware にする。
5. `ShogunScreen` に target chips と接続表示を追加する。
6. USB / Tailscale 接続プロファイル script と Android import を追加する。
7. README を更新し、検証する。
8. commit / push する。

## Progress

- [x] 2026-05-13: 要件と計画を作成。
- [x] 2026-05-13: SSH セットアップ簡略化要求を計画へ追加。
- [x] 2026-05-13: bridge script / tests を追加。
- [x] 2026-05-13: Android ViewModel / UI に送信先 chip と `@agent_id` bridge 経路を追加。
- [x] 2026-05-13: pairing profile script / Android import を追加。
- [x] 2026-05-13: docs 更新。
- [x] 2026-05-13: shell / Bats / Android unit test / debug APK build を検証。
- [ ] commit / push。

## Surprises & Discoveries

- `scripts/` 配下の新規ファイルは repo の broad `.gitignore` により通常の `git status` へ出ないため、commit 時は `git add -f scripts/android_agent_bridge.sh scripts/android_pairing_profile.sh` が必要。

## Decision Log

- Decision: Android からは `@agent_id` を正として解決する bridge script を使う。
  Rationale: `goza-no-ma` の pane 配置や Android 互換 session の pane index に依存すると、複数家老や足軽数変更で送信先がずれやすいため。
  Date/Author: 2026-05-13 Codex
- Decision: 送信本文は base64 で host bridge に渡す。
  Rationale: SSH exec の shell quote だけでは日本語・引用符・改行を安全に扱いにくいため。
  Date/Author: 2026-05-13 Codex

## Outcomes & Retrospective

- Implemented:
  - `scripts/android_agent_bridge.sh`
  - `scripts/android_pairing_profile.sh`
  - Android Shogun tab target chips
  - Android connection profile import
- Verification:
  - `bash -n scripts/android_agent_bridge.sh scripts/android_pairing_profile.sh` → PASS
  - `bats tests/unit/test_android_agent_bridge.bats` → PASS (`5` tests)
  - `cd android && HOME="$PWD/.home" ANDROID_USER_HOME="$PWD/.android-user-home" GRADLE_USER_HOME="$PWD/.gradle-user-home" ./gradlew --no-daemon test` → PASS
  - `cd android && HOME="$PWD/.home" ANDROID_USER_HOME="$PWD/.android-user-home" GRADLE_USER_HOME="$PWD/.gradle-user-home" ./gradlew --no-daemon assembleDebug` → PASS
  - `cd android && HOME="$PWD/.home" ANDROID_USER_HOME="$PWD/.android-user-home" GRADLE_USER_HOME="$PWD/.gradle-user-home" ./gradlew --no-daemon testDebugUnitTest` → PASS
  - `git diff --check` → PASS
- Residual risk:
  - 実機 Android 操作は未確認。APK インストール後、接続プロファイル import と agent chip 切替送信を実機で確認する。
