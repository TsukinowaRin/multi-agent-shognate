# ExecPlan: MacAir All-Codex E2E

最終更新: 2026-06-26

## 目的

MacAir の `/Users/fishorduck/projects/Test` で、全役職を Codex CLI に揃えた Shogunate runtime を実起動し、実タスクと長めの観察で macOS 環境の破綻有無を確認する。

## 前提と制約

- MacAir には `tmux` / `flock` / `coreutils` / `fswatch` / `codex` がある。
- 対象 project はユーザー指定の `/Users/fishorduck/projects/Test`。
- 破壊的操作、既存成果物削除、secret 読み取りはしない。
- 検証で作った Shogunate runtime は、ユーザーが観察できるよう必要時まで残す。ただし誤って作った別 project runtime は停止する。

## 手順

1. MacAir の engine/runtime `config/settings.yaml` を全役職 `codex` に更新する。
2. `test` project の runtime を clean restart し、8 role と `cli: codex` を確認する。
3. Shogun に、小さすぎないテストプロジェクト作成タスクを投入する。
4. 5分間隔を目安に以下を観察する。
   - `shogunate battlefield status test --json`
   - tmux session / daemon session
   - `dashboard.md`
   - `queue/shogun_to_karo.yaml`
   - `queue/tasks/*.yaml`
   - `queue/reports/*.yaml`
   - `/Users/fishorduck/projects/Test` の成果物
5. 30分程度観察し、結果と残リスクを本ExecPlanに追記する。

## 検証ログ

### 2026-06-26 開始

- User request: 全エージェントを Codex にして、MacAir の Test folder で実タスクと長時間駆動を確認する。
- 初期確認:
  - `codex-cli 0.142.2`
  - `tmux`, `flock`, `fswatch` available
  - `/Users/fishorduck/projects/Test` runtime は running
  - 設定上は `ashigaru1/2: opencode`, `ashigaru4: gemini` が残っていたため、完全な all-Codex ではなかった。

### 2026-06-26 MacAir package/runtime 修正

- macOS で watcher / daemon が Linux 前提に寄りすぎていたため、MOD 側で以下を修正した。
  - `shogunate_mod/runtime/daemon.sh`
    - `/opt/homebrew/bin/bash` / `/usr/local/bin/bash` を優先する `runtime_bash_command` を追加。
    - `inotifywait` だけでなく `fswatch` でも watcher を起動する。
    - stale `fswatch` process も cleanup 対象にする。
  - `shogunate_mod/runtime/launch.sh`
    - agent launch script に `SHOGUNATE_ENGINE_DIR` を渡す。
    - runtime/engine `.venv/bin`、Homebrew coreutils、Homebrew bin、`/usr/local/bin` を PATH 先頭へ追加する。
  - `shogunate_mod/package/bootstrap.sh` / `npm_cli.js`
    - macOS の Homebrew / venv PATH を package install 後の command path に反映。
- MacAir へ `npm pack` したローカル package を `scp` し、`SHOGUNATE_PACKAGE_URL=file:///tmp/shogunate-local-e2e.tgz .../bootstrap.sh --no-setup` で再導入した。
- `shogunate battlefield start test --resume --launch-probe-timeout 10 --deliver-pending-timeout 0 --json` で `test` battlefield を起動。
- 観測:
  - `running_roles: 8`
  - `daemon_windows: 14`
  - inbox watcher count: 8
  - 全 role は Codex 設定。

### 2026-06-26 実AIタスク 1

- Shogun へ、`/Users/fishorduck/projects/Test/macair-codex-e2e` に小さな Node.js task manager を作るタスクを投入。
- 生成物:
  - `package.json`
  - `src/tasks.js`
  - `src/cli.js`
  - `public/index.html`
  - `README.md`
  - `test/tasks.test.js`
- 直接検証:
  - `npm test`: 4 tests PASS
- runtime flow:
  - Shogun -> Karo -> Ashigaru reports -> Gunkan audit -> command done まで到達。

### 2026-06-26 長めタスク監視

- 追加タスク:
  - dueDate / priority / tags / notes / update API
  - CLI `edit/search/export/import/stats`
  - Web UI 拡張
  - tests を 10 件以上へ増加
  - README 更新
  - Gunkan に dependency-free / `npm test` / CLI smoke / compatibility 監査を依頼
- 監視時間:
  - 18:34 JST 頃から 19:22 JST 頃まで、約48分観察。
- 安定性:
  - runtime は `running_roles: 8` を維持。
  - daemon session は 14 windows を維持。
  - watcher は 8 role 分を維持。
  - Shogun / Karo / Ashigaru1-4 / Gunkan の command-task-report-audit flow は継続。

### 2026-06-26 発見した停止点

- Gunkan 監査が一度 `failed` になった。
  - 理由1: `npm test` が 13/14 PASS。`notes` trim の期待値不一致。
  - 理由2: `codd_audit.py` が system Python で起動され、`ModuleNotFoundError: yaml` で失敗。
- Ashigaru4 が `src/tasks.js` の `normalizeNotes` を修正し、MacAir 直接 `npm test` は 14/14 PASS へ回復した。
- ただし runtime-sync が「失敗監査後に足軽 report が更新された」状態を自動再監査へ進めず、command が `audit_requested` 付近で詰まり得ることを確認した。

### 2026-06-26 再発防止修正

- `shogunate_mod/gunkan/codd_audit.py`
  - `yaml` import を遅延化。
  - 現在の Python に PyYAML が無い場合、以下の候補から `import yaml` 可能な Python を探して self re-exec する。
    - `$SHOGUNATE_RUNTIME_DIR/.venv/bin/python3`
    - `$SHOGUNATE_ENGINE_DIR/.venv/bin/python3`
    - `cwd/.venv/bin/python3`
    - `cwd/queue/runtime/engine_dir` が指す engine `.venv/bin/python3`
- `shogunate_mod/runtime/sync_state.py`
  - Gunkan 監査失敗後、足軽 report が監査 report より新しければ Gunkan へ強制再監査を依頼する。
  - 足軽 report が更新されていなければ command を `review` にし、Karo へ `audit_failed` として修正差配する。
  - 再監査判定は `st_mtime_ns` を使い、同一秒内の report 更新を見落とさない。
- 契約テスト:
  - `test_failed_gunkan_audit_requests_karo_review`
  - `test_worker_report_update_after_failed_audit_requests_gunkan_reaudit`
  - agent launch script が runtime/engine venv と Homebrew PATH を含むことを mux parity test に追加。

### 2026-06-26 復旧確認

- 修正済み package を MacAir へ再導入し、`test` battlefield を resume。
- runtime-sync が既存の失敗監査状態から Karo review / Gunkan re-audit へ進み、最終的に対象 command は `done` になった。
- 最終状態:
  - `cmd_20260626_183516_macair_codex_e2e`: `done`, completed at `2026-06-26T18:40:23+09:00`
  - `cmd_20260626_185527_macair_codex_e2e_extend`: `done`, completed at `2026-06-26T19:16:42+09:00`
  - Gunkan final report: `status: passed`, `parent_cmd: cmd_20260626_185527_macair_codex_e2e_extend`
  - `npm test` in `/Users/fishorduck/projects/Test/macair-codex-e2e`: 14 tests PASS
  - `PATH=/usr/bin:/bin SHOGUNATE_ENGINE_DIR=/Users/fishorduck/.shogunate/shogunate python3 shogunate_mod/gunkan/codd_audit.py --help`: PASS

### 2026-06-26 最終再導入確認

- `st_mtime_ns` の再監査判定修正後、再度 `npm pack` して MacAir へ `file:///tmp/shogunate-local-e2e.tgz` から導入した。
- `shogunate battlefield start test --resume --launch-probe-timeout 10 --deliver-pending-timeout 0 --json` で遠隔 resume 起動を確認した。
- MacAir の非ログイン SSH では `tmux` / `npm` / `shogunate` が PATH に出ないため、確認コマンドでは `~/.local/bin:/opt/homebrew/bin:/usr/local/bin:$PATH` または `/opt/homebrew/bin/tmux` を明示した。
- 最終確認:
  - `/opt/homebrew/bin/tmux list-sessions`: `shogunate-test-2eee080a` と `goza-runtime-shogunate-test-2eee080a` が存在。
  - daemon windows: 14
  - Codex role processes: 8
  - inbox watcher processes: 8
  - Shogun / Karo / Gunkan unread inbox: empty
  - command statuses: both E2E commands are `done`
  - `/Users/fishorduck/projects/Test/macair-codex-e2e npm test`: 14 tests PASS

## 結果

- MacAir の `/Users/fishorduck/projects/Test` で、全役職 Codex の実AI runtime が起動し、2件の実タスクを完了した。
- 長めのタスク中に Gunkan 監査失敗からの詰まりを再現し、MOD 側で復旧導線を実装して実機で回復を確認した。
- 約48分の観察では、tmux runtime / daemon / watcher 自体の落ちは確認されなかった。

## 残リスク

- 24時間以上の soak test は未実施。
- Android / desktop app からこの MacAir battlefield を操作する E2E は今回の範囲外。
- 生成された Web UI はファイル生成と Node test は確認したが、ブラウザ操作での手動確認は未実施。
