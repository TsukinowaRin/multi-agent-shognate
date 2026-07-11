# ExecPlan: Real Machine Harness Verification

最終更新: 2026-06-21

## 目的

Role / CLI harness refresh 後、生成 instruction、package 導線、source runtime、Android build、実機 Android 接続前提がこのPC上で破綻しないことを確認する。

## 前提

- 既存の未コミット変更は巻き戻さない。
- secrets、認証 token、秘密鍵の内容は読まない。
- 実AI CLIは存在確認と runtime 起動確認を優先し、追加の課金・長時間タスクは必要最小限にする。
- 既存 tmux session は kill しない。

## 検証手順

1. 環境確認: `tmux`, `adb`, `codex`, `claude`, `opencode`, `agy`, `kilo`, `node`, `java`。
2. Harness生成確認: `bash scripts/build_instructions.sh`、Bats build system tests。
3. 構造・配布確認: `make structure-check`, `make package-check`, `make package-curl-smoke`。
4. Runtime確認: `make source-smoke`, `make upstream-overlay-smoke`。
5. Android確認: `adb devices`, `make android-check`。
6. 必要なら隔離 project で実 runtime を起動し、pane / dashboard / queue を確認する。

## 検証結果

- `bash scripts/build_instructions.sh`、root / MOD `test_build_system.bats` は PASS。
- `make structure-check` は PASS。最新差分後に `make source-smoke`、`make upstream-overlay-smoke` を再実行して PASS。
- `make android-check` は PASS。Android 実機 `661ecd40` へ debug APK を install / launch し、`com.shogun.android.MainActivity` の foreground を確認。
- 実機 runtime を隔離 target project で複数回起動し、最終確認 `real-machine-e2e-final3-20260621212523` で以下を確認。
  - `agent_cli.tsv`: shogun / gunkan / gunshi / karo = `codex`、ashigaru1 / ashigaru2 = `opencode`、ashigaru3 = `claude`、ashigaru4 = `antigravity`。
  - tmux pane 実体で 8/8 ready を確認。Claude は `● ready:ashigaru3` を出すため、ready 判定を `•` / `●` 両対応に修正。
  - OpenCode 通常待機画面の例文 `What is the tech stack of this project?` を project prompt と誤判定しないよう修正。
  - OpenCode update prompt を起動 gate / watcher retry で自動 skip する導線を追加。
  - bootstrap は全 CLI で短い file-reference prompt を送る方式へ統一し、Claude / Antigravity への長文起動引数埋め込みを停止。
- Targeted verification:
  - `bash -n shogunate_mod/runtime/bootstrap.sh shogunate_mod/runtime/prompts.sh shogunate_mod/runtime/launch.sh shogunate_mod/watcher/inbox_watcher.sh` PASS。
  - `bats tests/unit/test_mux_parity.bats shogunate_mod/tests/unit/test_mux_parity.bats tests/unit/test_send_wakeup.bats shogunate_mod/tests/unit/test_send_wakeup.bats` PASS（374 tests）。
  - `make test` PASS（root-level 33 + unit 649）。
  - `make source-smoke` PASS（source runtime, session `shogunate-mod-source-runtime-smoke-20260621222546`）。
  - `make upstream-overlay-smoke` PASS（upstream `upstream/main` overlay, session `shogunate-mod-upstream-overlay-smoke-20260621222546`）。
  - `make package-curl-smoke` PASS（HEAD archive から cURL package install）。
  - `git diff --check` PASS。
- 以前の広範囲確認:
  - `python3 -m unittest tests.unit.test_shogunate_pair_server` PASS。
  - working-tree package cURL smoke PASS。

## 残リスク

- `make package-check` は HEAD commit gate で FAIL。新規 canonical files 18件が未コミットのためで、実装挙動の失敗ではない。コミット後に再実行が必要。
  - `shogunate_mod/instructions/source/harnesses/cli/*.md`
  - `shogunate_mod/instructions/source/harnesses/common/*.md`
  - `shogunate_mod/instructions/source/harnesses/roles/*.md`
  - `shogunate_mod/runtime/sync_state.py`
  - `shogunate_mod/tests/unit/test_runtime_sync_state.py`
- 実機 runtime の最終起動ログは修正前プロセス由来で `7/8 ready` timeout を表示したが、tmux pane 実体は 8/8 ready。修正後コードでは `● ready` を拾うため同条件で解消見込み。
- 長時間の実タスク遂行までは未実施。今回は起動、bootstrap、watcher、Android launch、unit / smoke の確認を範囲とした。
