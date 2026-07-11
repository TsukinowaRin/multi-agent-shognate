# ExecPlan: Stress Bug Hunt

最終更新: 2026-06-27

## 目的

30分超soakで安定した Shogunate 構成に、段階的に高い負荷と異常系をかけ、API / package / queue / runtime-sync / watcher / 実AI導線のバグを掘り出して修正する。

## 制約

- 既存ユーザーprojectや secrets は読まない・壊さない。
- 実AIへの負荷は小さく始め、API / queue 層で再現できるものを優先する。
- MacAir の `test` はユーザー観察用の既存 runtime なので、停止操作は原則このPCの隔離projectで行う。
- このPCの破壊的操作は `<WORKSPACE_ROOT>/shogunate-dual-probe` または新規隔離projectに限定する。

## 方針

1. Baseline: このPC `dual-probe` と MacAir `test` の状態を取得する。
2. API stress: `battlefield list/status/roles/sessions/transcript/outbox` を反復実行し、JSON破損や例外を探す。
3. Local lifecycle stress: このPCの隔離projectで `stop/start/resume/send --start/outbox` を反復し、pending delivery と daemon 復帰を見る。
4. Queue/runtime-sync stress: 隔離runtimeに異常な report / stale task / failed audit 相当を作り、sync が落ちないことを確認する。
5. Real runtime light load: 実AIに小さな連続指示を投げ、inbox / command / Gunkan が詰まらないか見る。
6. 修正したら targeted unit と実機再確認を回す。

## 進捗ログ

### 2026-06-27 開始

- User request: `この調子でどんどん負荷をかけていって、テストをいっぱいしてみて、バグを洗い出して修正してみて`
- 前提:
  - このPC `dual-probe` と MacAir `test` は直前の30分超soakで running / 8 role / daemon 14 windows / pending 0 を維持した。
  - package distribution は `322` tests PASS、battlefield/runtime-sync は `10` tests PASS。

## 検証ログ

- API stress:
  - このPC `stress-probe`: `app capabilities`, `battlefield list/status/roles/sessions/transcript/outbox` を `80` 周回、合計 `560` JSON command 実行 -> PASS (`37.38s`)。
  - 直前の追加負荷として、このPC/MacAir で `50` 周回 x `7` command、およびこのPCで parallel `8` workers x `40` iterations x `4` commands -> PASS。
  - 追加 stress:
    - WSL `stress-probe`: `120` 周回 x `7` JSON commands -> PASS (`43.54s`)。
    - MacAir `test`: `80` 周回 x `7` JSON commands -> PASS (`33.44s`)。
    - 最終 package 反映後、WSL/MacAir とも `40` 周回 x `4` JSON commands -> PASS。
  - 2時間 soak:
    - 2026-06-27 15:00:07-17:00:07 JST。
    - WSL `stress-probe` / MacAir `test` を同時監視し、`status/roles/sessions/outbox/transcript`、project registry/sync、15周ごとの役職 direct send を反復。
    - `131` cycles、failures `0`。全サンプルで running / roles `8` / pending `0` / daemon windows `14` / bootstrap pending `0`。
  - 更新済み runtime 再起動後の1時間 soak:
    - 2026-06-27 17:55:18-18:55:18 JST。
    - WSL `stress-probe` / MacAir `test` を通常APIで stop -> `start --resume` し、古いpane履歴を切り離した状態で再監視。
    - `66` cycles、failures `0`。全サンプルで running / roles `8` / pending `0` / daemon windows `14` / bootstrap pending `0` / Codex transcript warning count `0`。
    - 5周ごとの `shogunate --project @... aliases` sync probe で dashboard preserved、rsync stderr empty。
    - 15周ごとの role direct send は Shogun / Gunkan / Gunshi / Karo まで通過。
  - 多種類実タスク:
    - WSL/MacAir へ小タスク、Gunkan監査、Gunshi設計相談、Shogun経由の実ファイル作成タスク、Karo/Ashigaru点呼を投入。
    - `12` sends、failures `0`。最終 `battlefield transcript --json` は WSL/MacAir とも success。
    - WSL: `<WORKSPACE_ROOT>/shogunate-stress-probe/e2e_workload/wsl_task_20260627` に Python CLI / unittest 3件 / README を作成し、`python3 -m unittest discover ...` -> OK。
    - MacAir: `/Users/fishorduck/projects/Test/e2e_workload/mac_task_20260627` に Python CLI / unittest 4件 / README を作成し、Mac上で `python3 -m unittest discover -v` -> OK。
- Lifecycle / pending delivery:
  - このPC隔離 project `<WORKSPACE_ROOT>/shogunate-stress-probe` を `stress-probe` として登録。
  - 停止中に `20` messages を `shogunate battlefield send` で保存し、`start --resume --deliver-pending-timeout 10` で `attempted=20, delivered=20, remaining=0` を確認。
- Package / unit:
  - `python3 -m unittest tests.unit.test_package_distribution shogunate_mod.tests.unit.test_package_distribution` -> PASS (`322` tests, `468.312s`)。
  - `bats tests/unit/test_mux_parity.bats shogunate_mod/tests/unit/test_mux_parity.bats` -> PASS (`150` tests)。
  - `python3 -m py_compile shogunate_mod/battlefield/api.py shogunate_mod/gunkan/codd_audit.py shogunate_mod/runtime/sync_state.py` -> PASS。
- cURL/package route:
  - `npm pack --pack-destination /tmp` -> `/tmp/tsukinowarin-shogunate-5.2.0-9.tgz` 作成。
  - `SHOGUNATE_PACKAGE_URL=file:///tmp/tsukinowarin-shogunate-5.2.0-9.tgz bash shogunate_mod/package/bootstrap.sh --no-setup` -> PASS。
  - installed shim `/home/muro/.local/bin/shogunate` に `rsync -a --checksum --delete` が入ることを確認。
  - MacAir にも同 package を scp し、`SHOGUNATE_PACKAGE_URL=file:///tmp/tsukinowarin-shogunate-5.2.0-9.tgz bash /tmp/shogunate-bootstrap-final.sh --no-setup` -> PASS。
- 実機 runtime:
  - `stress-probe` を `stop` -> `start --new --launch-probe-timeout 25 --deliver-pending-timeout 0`。
  - 生成済み `queue/runtime/launch_*.sh` 全8役職に startup prompt / `ready:*` directive が入ることを確認。
  - 2分観察後、bootstrap pending `0`、roles `8`、daemon windows `14`、全8 pane が `ready:*` 応答済み。
  - 全8役職へ小さな直接指示を送信し、outbox `0`、roles `8`、pending `0`。Gunkan は軍監口調で直接応答。`ashigaru2` は `1m18s` で完了し待機へ戻った。
  - MacAir `test` に全8役職へ小さな直接指示を送信し、全 message `queued=false`, `returncode=0`。90秒観察後、roles `8`, pending `0`。
  - 最終 package 反映後、WSL `stress-probe` / MacAir `test` とも daemon windows `14`, bootstrap pending `0`。

## 発見事項

### 既存 project workspace が更新されない

- 症状:
  - package 再導入後も、既存 workspace `/home/muro/.shogunate/workspaces/shogunate-stress-probe-3305417d` の `shogunate_mod/runtime/bootstrap.sh` が古い `MAS_CODEX_STARTUP_PROMPT_MODE:-tmux` のままだった。
  - その結果、clean start しても `queue/runtime/launch_*.sh` に Codex startup prompt が入らず、一部 Ashigaru の bootstrap pending が残った。
- 原因:
  - project runtime 同期が `rsync -a --delete` だった。
  - release/package 由来ファイルは mtime が固定されやすく、`tmux` -> `argv` のような同じ長さの変更では size/mtime が同じになり、rsync が内容差分を見ずに skip した。
- 修正:
  - `shogunate_mod/package/bootstrap.sh` の project runtime 同期を `rsync -a --checksum --delete` に変更。
  - package distribution contract に `rsync -a --checksum --delete` の期待を追加。
- 再確認:
  - reinstall 後、`shogunate --project @3305417dfd6d aliases` による workspace 同期で既存 workspace の `bootstrap.sh` が `MAS_CODEX_STARTUP_PROMPT_MODE:-argv` へ更新された。
  - clean start 後、全8役職が startup prompt を受け取り `ready:*` を返した。

### 起動中 workspace 同期が `.shogunate/codex` を削除しに行く

- 症状:
  - MacAir で `test` runtime が起動中のまま package 再導入後に `shogunate --project @test aliases` を実行すると、`rsync ... .shogunate/codex ... Directory not empty` が stderr に出た。
  - status は running / roles `8` / pending `0` を維持していたが、起動中 agent の Codex home / auth symlink を package sync が削除対象にするのは危険。
- 原因:
  - project runtime 同期の `rsync --delete` exclude に runtime local state である `/.shogunate/` が入っていなかった。
- 修正:
  - `shogunate_mod/package/bootstrap.sh` の rsync / tar fallback に `/.shogunate/` / `./.shogunate` exclude を追加。
  - package distribution contract に `.shogunate` 除外を追加。
- 再確認:
  - WSL / MacAir の両方で修正版 package を再導入し、起動中 workspace に対して `shogunate --project @... aliases` を実行しても stderr は空。

### project registry の JSON API 不足

- 症状:
  - `shogunate projects add ... --json` が `unrecognized arguments: --json` で失敗した。
  - Android/desktop app や自動化から登録済み project を追加する場合、`projects list --json` だけでは操作結果を扱いにくい。
- 修正:
  - `shogunate_mod/projects/registry.py` の `add/select/current/resolve/remove` に `--json` を追加。既存のプレーン出力は維持。
  - package distribution contract に registry JSON 操作の確認を追加。
- 再確認:
  - WSL: `shogunate projects add <WORKSPACE_ROOT>/shogunate-stress-probe --name stress-probe --select --json` -> valid JSON。
  - MacAir: `shogunate projects add /Users/fishorduck/projects/Test --name test --select --json` -> valid JSON。

### 古い blocked report が完了 command を error に戻す

- 症状:
  - WSL の大きめ実タスクで、成果物と unittest は通過し `queue/shogun_to_karo.yaml` も `completed` / verification pass になった。
  - しかし先に走った統合確認担当 `ashigaru4_report.yaml` が古い `blocked` のまま残り、Gunkan light watcher が `done_command_with_failed_report` を `error` として検出した。
- 原因:
  - 並列足軽で「早すぎる検証」が失敗 report を残したあと、家老が再検証して親 command に成功証跡を書いても、watcher が親 command の `result.verification` を見ずに古い子 report だけで error 判定していた。
- 修正:
  - `shogunate_mod/gunkan/light_watch.py` に `command_has_success_evidence()` を追加。
  - 親 command が done/completed かつ `result.verification` に pass/OK 等の成功証跡があり、失敗語を含まない場合は、古い bad report だけでは `done_command_with_failed_report` を出さない。
  - 本物の「done command + failed report」検知は既存テストで維持。
- 再確認:
  - 実 runtime に対して修正版 `light_watch.py --project-root ... --no-inbox` を実行し、status は `error` から `warn` へ低下。`done_command_with_failed_report` は消え、残る警告は report様式/古い report 由来のみ。
  - `bats tests/unit/test_gunkan_audit.bats` -> PASS (`16` tests)。

### workspace sync が `dashboard.md` を削除し得る

- 症状:
  - MacAir `test` runtime で `battlefield status` は running / roles `8` だが、`/Users/fishorduck/.shogunate/workspaces/test-2eee080a/dashboard.md` が存在しなかった。
  - Gunkan report / queue は成立していたが、スマホ/デスクトップアプリの戦況表示に必要な dashboard が欠落する状態。
- 原因:
  - project runtime sync は `rsync -a --checksum --delete` で engine から workspace へ同期する。
  - `dashboard.md` は package 側で `export-ignore` される runtime-local file だが、sync exclude に入っておらず、`shogunate --project @... aliases` などの同期で削除され得た。
- 修正:
  - `shogunate_mod/package/bootstrap.sh` の rsync / tar fallback に `dashboard.md` exclude を追加。
  - `shogunate_mod/runtime/state.sh` は clean start だけでなく `dashboard.md` 欠落時も初期dashboardを再生成する。
  - package distribution contract に `dashboard.md` exclude と欠落復旧条件を追加。
- 再確認:
  - `python3 -m unittest ...test_curl_bootstrap_installs_command_before_first_setup ...test_runtime_state_recreates_missing_dashboard` -> PASS (`4` targeted tests, root/MOD copy)。
  - `bash -n shogunate_mod/runtime/state.sh shogunate_mod/package/bootstrap.sh` -> PASS。

## 残リスク

- `rsync --checksum` は既存 workspace 同期を堅牢にする代わりに、project runtime 更新時のファイル比較コストが少し増える。現在の package size では実測上問題なし。
- MacAir の古い Codex pane に残っていた `Failed to save the conversation transcript; invalid thread-store request: no rollout found...` は、更新済み runtime の stop/start 後には再発しなかった。現時点では古いpane履歴由来として扱う。
- `dashboard.md` 欠落復旧は、targeted test / package再導入 / aliases sync probe / 更新済みruntime再起動後の1時間soakで確認済み。
