# ExecPlan: Dual Machine Stability Probe

最終更新: 2026-06-27

## 目的

修正後の Shogunate package/runtime 構成を MacAir とこのPCの両方に入れ、実機上で起動、watcher、runtime-sync、Gunkan audit、非ログイン shell PATH を確認し、残っているバグを掘る。

## 制約

- 既存 project や secrets は読まない・壊さない。
- 実タスクは隔離 project に限定する。
- MacAir の既存 `test` battlefield はユーザー観察用のため、停止が必要な場合は理由を残す。
- このPCでは `/mnt/d/Git_WorkSpace` 配下に検証用 project を作る。

## 手順

1. ローカル package を `npm pack` し、MacAir とこのPCへ同じ構成を導入する。
2. MacAir:
   - `test` battlefield の running / role / daemon / watcher を確認する。
   - 非ログイン SSH PATH でも `shogunate` / `tmux` / `npm` 相当が扱えるか確認する。
   - 短い追加命令を送って inbox / command / audit が詰まらないか見る。
3. このPC:
   - 隔離 project を作成・登録し、全Codex構成で起動する。
   - runtime / daemon / watcher / Codex process / Gunkan audit を確認する。
   - codd audit self re-exec と runtime-sync 再監査契約を確認する。
4. 見つかった問題は原因を切り、MOD側に狭く修正する。
5. ローカルテストと実機再確認を実施し、残リスクを記録する。
6. MacAir とこのPCを同時に30分以上監視し、runtime / daemon / role process / queue が自然停止しないことを確認する。

## 検証ログ

### 2026-06-26 開始

- User request: 修正後の構成で MacAir とこのPCをもう一度テストし、バグを掘る。
- 前提:
  - 前回検証で MacAir の `test` battlefield は全Codex構成で起動確認済み。
  - 修正済み内容は Gunkan audit self re-exec、runtime-sync再監査、macOS watcher/PATH補強。

### 2026-06-26 初期確認

- MacAir:
  - `codex-cli 0.142.2`
  - `/opt/homebrew/bin/tmux` 3.6b
  - `/opt/homebrew/bin/fswatch`
  - `/opt/homebrew/bin/npm` 11.12.1
- このPC / WSL:
  - `codex-cli 0.142.2`
  - `/usr/bin/tmux` 3.4
  - `/usr/bin/inotifywait`
  - `npm` 11.13.0
- 同一 tarball `@tsukinowarin/shogunate@5.2.0-9` を作り、MacAir とこのPCへ `SHOGUNATE_PACKAGE_URL=file:///... bootstrap.sh --no-setup` で導入した。

### 2026-06-26 MacAir 再検証

- `test` battlefield:
  - runtime: running
  - session: `shogunate-test-2eee080a`
  - daemon session: `goza-runtime-shogunate-test-2eee080a`
  - daemon windows: 14
  - role processes: Codex 8
  - inbox watcher: 8
- `shogunate battlefield send test --role shogun ...` で短い確認命令を投入。
- 観測:
  - Shogun が inbox を読み、Karo へ `cmd_20260626_232117_probe_state` を起票。
  - 足軽 report が返り、runtime-sync が Gunkan 監査へ進めた。
  - Gunkan は `queue/reports/shogun_probe_20260626.yaml` 未作成を理由に `failed` と判定。
  - command は `review` へ戻り、Karo へ `audit_failed` が通知された。
- 判定:
  - 監査失敗時に詰まらず Karo review へ戻る導線は動作。
  - 失敗理由は runtime ではなく、probe命令で要求した成果物を役職側が作らなかったこと。

### 2026-06-26 このPC / WSL 再検証

- 検証用 project:
  - `/mnt/d/Git_WorkSpace/shogunate-dual-probe`
  - registry name: `dual-probe`
  - runtime: `/home/muro/.shogunate/workspaces/shogunate-dual-probe-25426778`
- engine `config/settings.yaml` を全Codexへ変更。
- `shogunate battlefield start dual-probe --new --launch-probe-timeout 10 --deliver-pending-timeout 0 --json` を実行。
- 最終状態:
  - runtime: running
  - session: `shogunate-shogunate-dual-probe-25426778`
  - daemon session: `goza-runtime-shogunate-shogunate-dual-probe-25426778`
  - daemon windows: 14
  - roles: Shogun / Gunkan / Karo / Gunshi / Ashigaru1-4 が全て `cli: codex`
  - App API: 全roleで `current_command: codex`, `pane_current_command: bash`
- `shogunate battlefield send dual-probe --role shogun ...` で短い確認命令を投入。
- 観測:
  - Shogun -> Karo -> 足軽 report -> Gunkan audit まで進行。
  - Gunkan は `queue/reports/shogun_probe_local_20260626.yaml` 未作成などを理由に `failed`。
  - command は `review` へ戻った。
  - CoDD audit は `queue/runtime/codd/gunkan_audit.yaml` へ出力され `passed`。

### 2026-06-26 掘り出したバグと修正

1. `shogunate where` が project runtime を生成していた。
   - 症状: 情報表示だけのつもりで `where` を実行した時点の古い `config/settings.yaml` が project runtime に固定され、後で engine を全Codexに変えても runtime が混在構成になった。
   - 修正: `print_project_info` は `prepare_project_runtime` を呼ばず、slug/hash から runtime path を表示するだけに変更。
   - 検証: `shogunate --project /mnt/d/Git_WorkSpace/shogunate-where-probe where` 後、runtime `config/settings.yaml` が作られないことを確認。

2. App API の `current_command` が実CLIではなく常に `bash` に見える。
   - 症状: tmux `pane_current_command` は launch script の shell を返すため、Codexが動いていても `bash` 表示になる。
   - 修正: `shogunate_mod/battlefield/api.py` で pane PID 配下の子プロセスを読み、`codex` / `claude` / `opencode` などの agent CLI descendant を `current_command` として返す。元の値は `pane_current_command` に残す。
   - 検証: MacAir とこのPCの両方で全roleが `current_command: codex`, `pane_current_command: bash` と表示。

3. `codd_audit.py` の venv self re-exec が target project cwd からの絶対パス実行で失敗する。
   - 症状: `cd /Users/fishorduck/projects/Test && PATH=/usr/bin:/bin python3 /Users/.../workspace/shogunate_mod/gunkan/codd_audit.py --help` が PyYAML 不足で失敗。
   - 原因: fallback探索が cwd と env だけを見ており、script path から runtime root を推定していなかった。
   - 修正: `Path(__file__).resolve().parents[2]` から runtime root を推定し、runtime `.venv` と `queue/runtime/engine_dir` の engine `.venv` を候補に追加。
   - 検証:
     - MacAir target cwd 絶対パス実行: `target_abs_codd_help=ok`
     - このPC target cwd 絶対パス実行: `local_target_abs_codd_help=ok`

### 2026-06-27 長時間soak開始と中断

- User request: `長時間で確認してみて`
- 受け入れ条件を `docs/REQS.md` へ追加し、MacAir とこのPCの同時30分以上soakを今回の追加確認として明示した。
- 00:26 JST に35分程度の監視 loop を開始したが、ユーザーがPC再起動を希望したため停止した。
- 停止前の観測:
  - このPC / `dual-probe`: `runtime=running`, `roles=8`, `current_command=['codex']`, pending message `0`, daemon windows `14`
  - MacAir / `test`: `runtime=running`, `roles=8`, `current_command=['codex']`, pending message `0`, daemon windows `14`
  - このPC queue: inbox unread は全role `0`、command tail は `cmd_20260626_233030_runtime_probe_local:done`、Gunkan report は `failed`
  - MacAir queue: inbox unread は全role `0`、command tail は `cmd_20260626_232117_probe_state:done`, `cmd_20260626_185527_macair_codex_e2e_extend:done`, `cmd_20260626_183516_macair_codex_e2e:done`、Gunkan report は `passed`
- 00:27:51 JST の最終クイック確認:
  - このPC: `running 8 ['codex'] 0`
  - MacAir: `running 8 ['codex'] 0`
- 判定:
  - 再起動前の短時間サンプルでは両機とも正常。
  - 30分以上のsoak完走は未実施。再起動後に再開する。

### 2026-06-27 再起動後の30分超soak

- User request: `再起動したから、作業を続けて`
- 再開時の状態:
  - このPC / `dual-probe`: 再起動後に `runtime=stopped`, `roles=[]`。想定通り tmux session が消えていた。
  - MacAir / `test`: `runtime=running`, `roles=8`, 全role `current_command=codex`。
- 復旧:
  - このPCで `shogunate battlefield start dual-probe --resume --launch-probe-timeout 20 --deliver-pending-timeout 0 --json` を実行。
  - 約1分後に `runtime=running`, `roles=8`, 全role `current_command=codex`, daemon windows `14` を確認。
- Soak:
  - 12:47:05 JST から 13:19:44 JST まで、MacAir とこのPCを同時監視した。
  - 取得点: 12:47:05, 12:51:43, 12:56:20, 13:00:58, 13:05:36, 13:10:13, 13:14:51, 13:19:44。
  - このPC / `dual-probe`: 全サンプルで `runtime=running`, `roles=8`, `all_codex=True`, `current=['codex']`, `pending=0`, daemon windows `14`。
  - MacAir / `test`: 全サンプルで `runtime=running`, `roles=8`, `all_codex=True`, `current=['codex']`, `pending=0`, daemon windows `14`。
  - inbox unread は全サンプルで増えず、このPCは全role `0`、MacAirも全role `0`。
  - command tail は変化せず、勝手な再実行や重複処理は見えなかった。
- 判定:
  - 再起動後の resume から30分超の放置監視で、runtime / daemon / role process / App API / SSH status取得は維持された。
  - 新しい停止、詰まり、pending増加、未読inbox増加、role消失は観測されなかった。
- 追加修正:
  - `test_battlefield_api.py` に既存契約と同じ repo-root 解決 helper を追加し、MOD copy からも import できる形へ揃えた。
  - macOS対応で watcher supervisor を `runtime_bash` 経由起動にしたため、package distribution 契約テストの期待文字列を更新した。
- 検証:
  - `python3 -m py_compile shogunate_mod/gunkan/codd_audit.py shogunate_mod/battlefield/api.py shogunate_mod/runtime/sync_state.py` -> PASS
  - `python3 -m unittest tests.unit.test_battlefield_api shogunate_mod.tests.unit.test_battlefield_api tests.unit.test_runtime_sync_state shogunate_mod.tests.unit.test_runtime_sync_state` -> PASS (`10` tests)
  - `python3 -m unittest tests.unit.test_package_distribution shogunate_mod.tests.unit.test_package_distribution` -> PASS (`322` tests)
  - `git diff --check` -> PASS

## 現時点の判定

- MacAir とこのPCの両方で、修正後構成の package 導入、runtime 起動、全Codex role、daemon 14 windows、App API の実CLI表示、CoDD venv復帰を確認した。
- 役職に投げた probe はどちらも「指定reportファイル未作成」でGunkanが `failed` にしたが、これは監査が働いている状態であり、runtime停止や同期停止ではない。
- command は `review` に戻り、Karoへ修正差配されている。
- 2026-06-27 の再起動後に MacAir とこのPCを同時に30分超soak監視し、両方で running / 8 role / daemon 14 windows / pending 0 を維持した。

## 残リスク

- 今回の追加probeは意図的に短い確認命令であり、長時間soakではない。
- 役職側が「将軍自身に report file 作成を求める」指示をKaro配下へ委譲したため、probe報告fileが未作成になった。これはruntimeバグではないが、将軍への直接運用指示としては文面調整余地がある。
- runtime-sync は足軽report更新ごとにGunkan再監査を依頼するため、短時間に複数reportが更新されると再監査依頼が複数並ぶことがある。致命的ではないが、UI上の重複感は今後改善候補。
