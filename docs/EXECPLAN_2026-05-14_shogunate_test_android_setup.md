# ExecPlan: Shogunate-test runtime validation and Android setup UX

作成日: 2026-05-14

## 目的

`Shogunate-test` に最新の開発版を反映し、Shogun へ小さなデモプログラム制作を依頼して実運用経路を確認する。同時に Android App の SSH / Tailscale / USB 接続セットアップ UI を改善し、実機または可能な範囲のテストで UX と回帰を確認する。

## 制約

- 既存の tmux session は `Shogunate-test` 由来のものだけ停止する。無関係な tmux session は触らない。
- `Shogunate-test` の `.git`、`.shogunate`、`config/settings.yaml`、`queue/`、`logs/`、`dashboard.md` など local state は原則保持する。
- Android の secrets、SSH key、password、token は読まない・出力しない。
- Gemini CLI は UI レビュー相手として使う。認証・quota・headless 実行に失敗した場合は、その理由を記録して Codex 単独で進める。

## 手順

1. `Shogunate-test` の git 状態と既存 tmux session の current path を確認する。
2. 現行 repo の最新 tracked / whitelisted code を `Shogunate-test` へ反映する。local state は除外する。
3. Shogunate-test の runtime を起動し、Shogun へ「小さなデモプログラムを全員で作る」指示を `inbox_write.sh` 経由で渡す。
4. Android App の接続設定画面、connection profile、deep link、README / tests を調査する。
5. Gemini CLI に Android セットアップ UX のレビューを依頼し、実装方針へ取り込む。
6. Android UI / copy / parser / tests を改善する。
7. Gradle unit test、必要な shell / Bats / Android bridge tests を実行する。
8. 可能なら emulator / connected device でスクリーンショット確認する。不可なら理由を明記する。
9. Shogunate-test の成果物、agent 進捗、Android 変更、検証結果、残リスクを報告する。

## 検証

- `bash -n` for touched shell scripts.
- `bats` for bridge / watcher / mux tests touched by this work.
- `cd android && HOME="$PWD/.home" ANDROID_USER_HOME="$PWD/.android-user-home" GRADLE_USER_HOME="$PWD/.gradle-user-home" ./gradlew --no-daemon test`
- Shogunate-test: tmux session / queue / dashboard / generated demo artifacts inspection.

## 進捗

- 2026-05-14: plan 作成。既存 `goza-no-ma` / `goza-runtime` は `Shogunate-test` 由来で稼働中と確認済み。
- 2026-05-14: `Shogunate-test` へ現行 repo の tracked files を反映。`config/settings.yaml` と Android local config は保持。
- 2026-05-14: `./Shogunate-Runtime.sh --clean --no-attach` で起動成功。Shogun へ `demo-collab-program/` のミニ進捗ボード作成を `scripts/inbox_write.sh` 経由で指示。
- 2026-05-14: Shogun -> Karo -> Gunshi / Ashigaru1-4 の分担は成立。成果物 `demo-collab-program/index.html` と `README.md` は生成された。
- 2026-05-14: 実運用上の懸念を観測。Ashigaru3 / Ashigaru4 が Ashigaru1 の `index.html` 完成前に検証・統合報告へ進み、早すぎる `failed` / 補足報告を残した。Karo は dashboard に「未完了」として残し、cmd を完了扱いにしなかった。
- 2026-05-14: Android 設定画面に初回セットアップ導線、接続リンク / JSON 貼り付け欄、クリップボード import、必須項目表示、保存して接続テストを追加。
- 2026-05-14: Gemini CLI で Android UX レビューを試みたが、`gemini-2.5-pro` / `gemini-2.5-flash` とも server capacity 429 で実行不可。Codex 単独で実装継続。
- 2026-05-14: Android 実機確認は ADB device `661ecd40` が `unauthorized` のため install / screenshot 不可。Gradle test と debug APK build は成功。
