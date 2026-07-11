# ExecPlan: cwd-first project runtime / parallel Shogunate

最終更新: 2026-06-16

## 目的

Package install 後の `shogunate` を Codex / opencode と同じ cwd-first UX に寄せる。Shogunate 本体は engine として保持し、ユーザーが `cd` した project ごとに runtime state と tmux session を分離する。

## 進捗

- [x] 要求を `docs/REQS.md` に正規化。
- [x] package command shim に project runtime copy、session 名生成、`shogunate where` を追加。
- [x] launchers / pair server に target project 情報を通す。
- [x] agent CLI の作業 cwd と bootstrap 文言を target project 対応にする。
- [x] README / help / tests を更新。
- [x] Android app の Pair 結果表示と project 固有 target 保存を検証。
- [x] shell / Python / package / Android tests を実行。

## 判断

- 本家思想は Shogunate 本体 repo を command center にする方式だが、配布版 Shogunate は非エンジニアと Android 連携を考え、cwd-first を正本にする。
- 既存 scripts は `SCRIPT_DIR` 配下に `queue/`, `logs/`, `dashboard.md` を置く前提が強い。単に `cd "$PWD"` へ変えると複数 project の runtime state が混ざるため、package shim が project ごとの runtime copy を `~/.shogunate/workspaces/<slug>-<hash>/` に作る。
- Android app は Pair response の `project` を dashboard / screenshot の root として使うため、互換のため `project` は runtime root のまま返す。実作業対象は追加 field `target_project` で返す。
- Pair 後の Android target は `agent:shogun` の全 session 検索ではなく、`<project-session>:goza.0` / `<project-session>:goza` を保存する。これにより並列 Shogunate で別 project の shogun pane を拾わない。

## 実装手順

1. `scripts/shogunate_package_bootstrap.sh` の生成 shim に project path 解決、workspace id/session id 生成、runtime copy sync を追加する。
2. `Shogunate-Runtime.sh` / `Shutsujin.sh` で `--project` を受け取り、`SHOGUNATE_PROJECT_DIR` を `shutsujin_departure.sh` へ渡す。
3. `shutsujin_departure.sh` の agent launch cwd、command shell cwd、bootstrap message に target project を反映する。
4. `scripts/shogunate_pair_server.py` に `--target-project` を追加し、runtime 起動時にも env として渡す。
5. README / README_ja / Android docs / tests を更新する。
6. Android unit/build check と、接続可能な実機 smoke を実施する。

## 検証

- PASS: `bash -n Shogunate-Runtime.sh Shutsujin.sh shutsujin_departure.sh scripts/shogunate_package_bootstrap.sh`
- PASS: `python3 -m py_compile scripts/shogunate_pair_server.py`
- PASS: `python3 -m unittest tests.unit.test_shogunate_pair_server tests.unit.test_package_distribution`
- PASS: `bats tests/unit/test_runtime_launchers.bats tests/unit/test_shell_aliases.bats`
- PASS: local fake package bootstrap smoke. Generated `shogunate` passed `bash -n`; `shogunate --project <tmp>/project where` printed project/runtime/engine/session and created `queue/runtime/target_project`, `engine_dir`, and `session_name` under a project workspace.
- PASS: isolated runtime smoke. A tracked-file runtime copy launched `Shogunate-Runtime.sh --project <sandbox>/project --clean --no-attach -s` with session `shogunate-cwd-smoke-*`; tmux options `@shogunate_project_dir` and `@shogunate_runtime_dir` matched the sandbox paths. The smoke-created tmux sessions were cleaned up.
- PASS: `./gradlew testDebugUnitTest` in `android/`.
- PASS: `./gradlew assembleDebug` in `android/`.
- PASS: real Android device `661ecd40` installed `android/app/build/outputs/apk/debug/app-debug.apk` with `adb install -r` and launched `com.shogun.android/.MainActivity`; `pidof` returned a running process and `dumpsys activity` showed `MainActivity` resumed.
- PARTIAL: USB Pair infrastructure smoke on real device. `scripts/shogunate_pair_server.py` configured `adb reverse` for a test port and host `/health` returned JSON containing `target_project` and project-specific fields. Android shell `toybox nc` connected with exit 0 but did not return response body, so full in-app Pair button flow remains manual verification.
- PASS: `git diff --check`

## 復旧

Package shim の cwd-first runtime copy が不調な場合は、`SHOGUNATE_PROJECT_DIR` を未設定にして workspace copy を使わず、従来どおり `~/.shogunate/shogunate` から `./Shogunate-Runtime.sh` を直接実行すれば旧挙動へ戻せる。
