# ExecPlan: Isolated Runtime Validation In Workspace Sandbox

## Context
- ユーザー要求は、最新統合済みコードを元の作業ツリーとは別の隔離フォルダへコピーし、そのコピーで実起動と代表タスク実行まで確認すること。
- この repo は tmux session、`queue/`, `status/`, `logs/`, repo-local `HOME` など実行時副作用を持つため、元ツリーを直接使うと前回状態と混ざる。
- ワークスペース外参照は禁止されているため、隔離先は `/mnt/d/Git_WorkSpace/multi-agent-shognate` 配下に閉じ込める。

## Scope
- ワークスペース内に隔離コピーを作成する。
- 隔離コピー側で runtime を起動し、tmux session と代表タスク処理を確認する。
- 実 `codex` CLI でも runtime を起動し、認証待ちや起動失敗を観測して改善する。
- docs に検証結果、観測、残リスクを残す。

## Acceptance Criteria
1. 隔離コピーがワークスペース内に存在し、主要 runtime ファイルを含む。
2. 隔離コピー側で `bash shutsujin_departure.sh -s` が成功し、`goza-no-ma` と Android 互換 session が生成される。
3. 代表タスクを複数投入し、少なくとも単発タスクと並列タスクの配送結果を観測できる。
4. `tmux capture-pane`, `queue/`, `status/`, `dashboard.md` のいずれかで完了または失敗の理由を確認できる。
5. 必要な e2e / smoke コマンドを実行し、失敗時は環境依存か実装不良かを切り分けられる。
6. 実 `codex` pane の認証待ちや bootstrap 停止理由が log に残る。

## Work Breakdown
1. `REQS` と index を更新し、今回の検証を docs 上の正規要求にする。
2. ワークスペース内に隔離フォルダを作り、現在の最新コードをコピーする。
3. 隔離コピー側で runtime 用の環境変数と一時領域を閉じ込める。
4. 起動、session 確認、代表タスク投入、観測、必要な e2e 実行を行う。
5. `WORKLOG` と本 ExecPlan に結果を追記し、必要なら commit/push する。

## Progress
- [x] (2026-03-29 15:0x) `REQS` / `INDEX` を更新し、本検証を docs 上の正規要求として追加。
- [x] (2026-03-29 15:1x) ワークスペース内に隔離コピー `runtime_sandboxes/isolated_runtime_validation_20260329_151700/repo` を作成。
- [x] (2026-03-29 16:07 JST) `/tmp/mas_isolated_runtime_validation_151700` を tmux socket 置き場として使い、隔離コピー側で `bash shutsujin_departure.sh -c` を完了。
- [x] (2026-03-29 16:08 JST) `queue/shogun_to_karo.yaml` への単発 command 投入で、`karo` が `cmd_new` を受信し、`ashigaru1` の task / report 生成まで確認。
- [x] (2026-03-29 16:09 JST) `ashigaru1` / `ashigaru2` へ並列 `task_assigned` を投入し、両方が `done` になることを確認。
- [x] (2026-03-29 16:1x) logs / pane capture / queue ファイルを採取し、結果整理を開始。
- [x] (2026-03-29 17:5x JST) 実 `codex` 用の隔離コピー `runtime_sandboxes/real_codex_validation_20260329_165500/repo` を作成し、`TMUX_TMPDIR=/tmp/real_codex_validation_165500 bash shutsujin_departure.sh -c` を実行。
- [x] (2026-03-29 17:5x JST) 実 `codex` pane で `Sign in with Device Code` / browser sign-in prompt まで進み、`CODEX_HOME` 不存在での即死ではなく認証待ちで停止することを確認。
- [x] (2026-03-29 18:0x JST) `lib/cli_adapter.sh` を `.shogunate/codex/agents/<agent>` へ変更し、起動前 `mkdir -p` を追加。
- [x] (2026-03-29 18:0x JST) `shutsujin_departure.sh` に Codex auth prompt 検知、bootstrap skip、`queue/runtime/goza_bootstrap_<run-id>.log` への status 記録を追加。
- [x] (2026-03-29 19:0x JST) `Shogunate-test` clone を GitHub から作成し、認証済み Codex state を workspace-local `CODEX_HOME` へ複製して WSL 実機検証を開始。
- [x] (2026-03-29 19:1x JST) 実機で `Do you trust the contents of this directory?` が update prompt 判定へ誤爆し、`No, quit` へ落ちる問題を再現・修正。
- [x] (2026-03-29 19:2x JST) 1 本目の top-level task について `shogun -> karo -> ashigaru1/2 -> karo -> shogun` の完了経路を確認。
- [x] (2026-03-29 19:2x JST) 2 本目の top-level task を投入し、少なくとも `shogun -> karo` までの再現性を確認。
- [x] (2026-03-29 20:2x JST) 実 Codex の多様タスク再試験で、将軍が初動で `projects.yaml` / `dashboard.md` まで広く探索し、家老も完了処理で sample/test/log を過読することを観測。
- [x] (2026-03-29 20:3x JST) `shutsujin_departure.sh` の bootstrap 文面へ役職別の「初動最適化」directive を追加し、起動直後の探索対象を自 inbox / 自 task 中心へ絞った。
- [x] (2026-03-29 20:3x JST) 実 Codex pane に出た `Approaching rate limits` / `Keep current model` prompt へ対処する自動dismiss を launcher 側と watcher 側へ追加。
- [x] (2026-03-29 20:4x JST) 実 Codex pane に出た `You've hit your usage limit` prompt を観測し、watcher から `gpt-5.1-codex-mini` への切替入力を自動送信する改善を追加。
- [x] (2026-03-29 20:4x JST) ただし hard usage-limit 自体は外部 quota 制約であり、`Shogunate-test` 上の実 task / 共同開発タスクはこの時点では再開不能なことを確認。
- [x] (2026-03-30 01:4x JST) `Shogunate-test` で単発 task を再試験し、家老の `report_received` 終盤寄り道を抑える instruction / bootstrap 文面を追加。
- [x] (2026-03-30 01:4x JST) `scripts/karo_done_to_shogun_bridge.py` が active queue しか見ず archive 済み `done` を拾えない不具合を修正し、`cmd_id+timestamp` 識別へ更新。
- [x] (2026-03-30 01:5x JST) 修正後の `Shogunate-test` で単発 task が再び `cmd_done` まで返ることを確認。
- [x] (2026-03-30 01:5x JST) handoff 推奨の共同開発 task を完了し、`playground/queue_summary/` に CLI / README / tests を生成、`python3 -m unittest` 3件 PASS を確認。
- [x] (2026-04-04 15:5x JST) Codex auth prompt に当たった agent の bootstrap を `.pending` marker として保持し、watcher が auth 解消後に literal 再配信できるようにした。
- [x] (2026-04-04 15:5x JST) `bash shutsujin_departure.sh -c` の最終案内を auth pending に追随させ、「全員 ready」と誤表示しないことを main repo 実行で確認した。
- [x] (2026-04-04 15:5x JST) `flock` が tmux server へ継承されて直列再起動まで塞ぐ問題を再現し、lock dir 方式へ置き換えて直列成功・並列拒否の両方を確認した。
- [x] (2026-04-04 16:2x JST) hard usage-limit だけでなく Codex auth prompt も `dashboard.md` の blocked notice へ載せ、bootstrap 再配信成功時に自動で除去する回帰を追加した。
- [x] (2026-04-04 16:3x JST) 実 runtime で auth notice が同一 agent / issue でも detail 違いで増殖することを確認し、1 notice 1行へ置換更新するよう修正した。
- [x] (2026-04-04 16:4x JST) `runtime_cli_pref_sync.log` が unchanged を毎秒吐き、Gemini alias 同期後も毎回 changed 扱いになることを確認し、no-op 時の stdout 抑止と alias 同期の idempotent 化を追加した。
- [x] (2026-04-04 17:0x JST) `runtime_blocker_notice.py` が過去 run の duplicate notice を残したまま `duplicate` / `not_found` を返すケースを確認し、record / clear 時に同一 agent / issue を自動正規化する回帰を追加した。
- [x] (2026-04-04 17:1x JST) 実 runtime で Codex update 完了後の shell 戻り pane に watcher が pending bootstrap を再送し、`--no-alt-screen【初動命令】...` の混線を起こすことを確認し、`pane_current_command=node` を満たさない限り Codex bootstrap を再送しない回帰を追加した。
- [x] (2026-04-04 18:0x JST) `watcher_supervisor.sh` と `inbox_watcher.sh` の両方に shell 戻り Codex pane の再起動導線を追加し、startup 側は `WATCHER_SUPERVISOR_ONCE=1` の同期 tick 後に常駐 supervisor を立てる形へ更新した。
- [x] (2026-04-04 18:2x JST) shell 戻り Codex pane の再起動時に、既配信扱いの `bootstrap_<agent>.delivered` を外して `bootstrap_<agent>.pending` を復元し、再ログイン後の bootstrap 再試行を可能にした。

## Surprises & Discoveries
- Observation: tmux socket を `/mnt/d/...` 配下へ置くと、WSL 側で `unsafe permissions` 扱いになり session 作成に失敗する。
  Evidence: `env TMUX_TMPDIR=... tmux new-session -d -s probe_goza 'sleep 3'` が `directory ... has unsafe permissions` を返した。
- Observation: 隔離コピー内で `PATH` を export しても、tmux pane 内の shell では bare `codex` が実 `codex` を解決した。
  Evidence: pane capture に `WARNING: ... CODEX_HOME points to ... does not exist` と実 `codex` のエラーが残った。
- Observation: sandbox 内の `lib/cli_adapter.sh` を一時的に絶対パスの `mock-bin/codex` へ向けると、pane 側は想定どおり mock Codex で待機・nudge 応答した。
  Evidence: pane capture に `[mock] Processed input`, `[mock] Task ... -> done` が出力された。
- Observation: `bats tests/e2e/e2e_inbox_delivery.bats tests/e2e/e2e_parallel_tasks.bats` は `tests/test_helper/bats-support/load` 欠落で setup_file 失敗した。
  Evidence: source repo 側でも `tests/test_helper/bats-support` / `bats-assert` は空 directory で、helper 実体が入っていなかった。
- Observation: 実 `codex` を隔離コピーで起動すると、各 pane は `Welcome to Codex` の sign-in menu または browser sign-in prompt まで進むが、未認証のため task 実行には入らない。
  Evidence: `tmux capture-pane -pt goza-no-ma:overview.0..4` に `Sign in with ChatGPT`, `Sign in with Device Code`, `Finish signing in via your browser`, `auth.openai.com/oauth/authorize` が出力された。
- Observation: 従来の repo-local `CODEX_HOME=.codex/agents/<agent>` は、この fork 直下の `.codex` ファイルと衝突し、pane 内で `CODEX_HOME points to ".../.codex/agents/..." but that path does not exist` を起こし得る。
  Evidence: 実 Codex 起動前の pane capture と CLI probe で、`.codex` が directory ではない前提のエラーを観測した。
- Observation: auth prompt は `Codex` 文字列を含むため、ready 判定だけでは「起動済み」と誤認しやすい。
  Evidence: sign-in menu 表示中でも screen content に `Codex` が含まれる一方、実際には prompt 入力や task 実行に進まない。
- Observation: 認証済み Codex を repo-local `CODEX_HOME` で使うには、既存 auth state を workspace-local home へ複製する必要がある。
  Evidence: `CODEX_HOME=<workspace-local> codex --search exec ... "返答は READY のみ。"` は `READY` を返した一方、空の local home では 401 だった。
- Observation: 実機の Codex は update prompt の後に workspace trust prompt を出すことがあり、従来の `Press enter to continue` 判定だと trust prompt まで update prompt 扱いして `2=No, quit` を送ってしまう。
  Evidence: pane 履歴に `Do you trust the contents of this directory?` と `1. Yes, continue / 2. No, quit` が出た直後、shell prompt へ戻り bootstrap が `command not found` になった。
- Observation: trust prompt を自動承認した後は 5/5 agent が bootstrap を消化し、`ready:*` を返して実 task を処理できた。
  Evidence: `queue/runtime/goza_bootstrap_20260329_190940.log` は全 agent `bootstrap-delivered`、pane capture に `ready:shogun`, `ready:karo`, `ready:gunshi`, `ready:ashigaru1` が残った。
- Observation: 1 本目の実 task は `cmd_20260329_191634` として家老へ委譲され、`ashigaru1` / `ashigaru2` の report 完了後に `cmd_done` が将軍 inbox へ戻った。
  Evidence: `queue/shogun_to_karo.yaml`, `queue/tasks/ashigaru1.yaml`, `queue/tasks/ashigaru2.yaml`, `queue/reports/ashigaru1_report.yaml`, `queue/reports/ashigaru2_report.yaml`, `queue/inbox/shogun.yaml` の遷移で確認した。
- Observation: 2 本目の実 task は `cmd_20260329_192317` として新規起票され、`queue/inbox/karo.yaml` に `cmd_new` 2 件が未読着弾した。
  Evidence: `Shogunate-test/queue/shogun_to_karo.yaml` と `Shogunate-test/queue/inbox/karo.yaml` に second command の entry が残った。
- Observation: Codex の初期 sign-in menu（`Sign in with ChatGPT` / `Provide your own API key`）は、browser auth prompt とは別画面のため、これも auth-required に含めないと pane ごとに 30 秒待たされる。
  Evidence: 実測では `karo`, `ashigaru1`, `ashigaru2`, `gunshi` が sign-in menu で停止し、検知条件を広げる前は個別待機が長引いた。
- Observation: auth-required を `deliver_bootstrap_tmux` の非0 return で返すだけだと、起動元の `set -e` により runtime 全体が abort した。
  Evidence: 修正途中の実行で `real_codex_startup.log` が `各エージェントに指示書を読み込ませ中...` 直後に止まり、再試験で `bootstrap 未配信でも継続` 分岐を入れると最後まで起動した。
- Observation: 実 task を `queue/inbox/shogun.yaml` へ投入しても、未認証のままでは message は `read: false` のまま残り、`queue/reports/karo_report.yaml` は生成されない。
  Evidence: `msg_20260329_180458_ed4bb65d` を投入後、10 秒以上待っても inbox は未読のままで report 不在だった。
- Observation: 実 Codex の将軍は、初動命令だけでは `config/projects.yaml` / `dashboard.md` / repo-wide search まで寄り道しやすく、最初の `task_assigned` 着手が 1 分以上遅れた。
  Evidence: `Shogunate-test` pane capture で、task 投入前後に `projects.yaml`, `dashboard.md`, repo listing へ広く探索していた。
- Observation: 家老は report 受領後も `logs/daily`, `streaks.yaml.sample`, `test_karo_done_to_shogun_bridge.bats` など補助資料へ寄り道し、`cmd_done` まで閉じるのが遅かった。
  Evidence: `goza-no-ma:0.1` pane capture と `queue/inbox/karo.yaml` の unread 滞留で確認した。
- Observation: Codex は `Approaching rate limits` prompt を会話中に差し込み、未読処理より prompt 応答を優先させるため、watcher が nudge しても task が進まないことがある。
  Evidence: pane capture に `Approaching rate limits` と `Keep current model (never show again)` が表示され、task unread が残留した。
- Observation: さらに `You've hit your usage limit` が出ると、`1. Switch to gpt-5.1-codex-mini` を送っても即時復帰せず、外部 quota 回復時刻まで hard-block する場合がある。
  Evidence: `Shogunate-test` の将軍 pane に `You've hit your usage limit ... try again at 10:46 PM` が出続け、watcher log では `Switching Codex to mini after usage-limit prompt` を繰り返しても `queue/inbox/shogun.yaml` が未読のままだった。
- Observation: `karo_done_to_shogun_bridge.py` は active `queue/shogun_to_karo.yaml` しか見ないため、家老が `done` cmd を archive へ移した後は `noop empty` となり `cmd_done` relay が欠落した。
  Evidence: `Shogunate-test/logs/karo_done_to_shogun_bridge.log` が `noop empty` を繰り返す一方で、`queue/shogun_to_karo_archive.yaml` には `status: done` の `cmd_002` が存在した。
- Observation: 家老の終盤遅延は bridge script 自体より、instruction 上の read scope が広過ぎることでも悪化していた。
  Evidence: 修正前は `streaks.yaml.sample` / bridge script / relay state TSV へ寄り道したが、`report_received` fast closure を追加後は `dashboard` 更新と archive 化まで一直線で進んだ。
- Observation: 共同開発 task では `ashigaru1` が `app.py` + tests、`ashigaru2` が README を担当する 2 段分割で、標準ライブラリのみの CLI + `python3 -m unittest` 成功まで通った。
  Evidence: `playground/queue_summary/app.py`, `playground/queue_summary/README.md`, `playground/queue_summary/tests/test_app.py` が生成され、`python3 -m unittest` が `Ran 3 tests ... OK` を返した。
- Observation: auth-required を skip だけで終えると、ログイン後も bootstrap が未配信のまま取り残され、pane が ready に戻っても初動に入れない。
  Evidence: main repo の `bash shutsujin_departure.sh -c` で auth prompt を検知した run では、watcher 側に再送処理が無い限り初動文面が pane へ入らなかった。
- Observation: `flock` 方式の起動 lock は file descriptor を引き継いだ tmux server が保持し続け、先行起動終了後の直列再実行まで「実行中」扱いにしうる。
  Evidence: `lsof .shogunate/locks/shutsujin.lock` で tmux の FD 保持を確認し、直列 2 回実行で 2 回目が誤って lock に弾かれた。
- Observation: auth-required は bootstrap log と startup stdout にしか残らず、runtime 継続中に殿が `dashboard.md` だけ見ても誰がログイン待ちなのか分からなかった。
  Evidence: 既存の blocked notice は `codex-hard-usage-limit` しか扱っておらず、`codex-auth-required` 導線が watcher / startup のどちらにも無かった。
- Observation: blocked notice を detail 文字列込みの完全一致でしか dedupe していないと、同じ agent / issue でも startup と watcher の detail 差分で行が増殖する。
  Evidence: 実 `bash shutsujin_departure.sh -c` 後の `dashboard.md` に、`runtime-blocked/shogun` の auth notice が detail 違いで複数行残った。
- Observation: 1 行置換に直した後も、過去 run で既に増殖した duplicate notice は、その agent / issue に再度触らない限り `dashboard.md` に残り続けた。
  Evidence: helper 修正後でも既存 `dashboard.md` に `runtime-blocked/shogun` / `runtime-blocked/karo` の auth notice 重複が残り、exact match 時は `duplicate` で早期 return して正規化されなかった。
- Observation: `runtime_cli_pref_daemon` は no-op 時も `sync_runtime_cli_preferences.py` の stdout を毎秒 log へ流し、さらに Gemini alias (`mas-shogun` など) を毎回 changed 扱いして settings を更新し続けていた。
  Evidence: `logs/runtime_cli_pref_sync.log` に `[INFO] runtime CLI preferences unchanged` が大量に残り、再現コマンドでも 2 回目の sync が `unchanged` ではなく `synced` を返した。
- Observation: Codex pane が update 完了や launch error で shell に戻ると、watcher の bootstrap retry は screen text だけで ready と誤認し、pending bootstrap を shell へ打ち込んでしまった。
  Evidence: 実 pane に `error: unexpected argument '--no-alt-screen【初動命令】あなたはashigaru2...` が残り、同時に `logs/inbox_watcher_ashigaru2.log` に `bootstrap retried and delivered` が出ていた。
- Observation: shell 戻り pane の自動再起動だけでは、過去 run で `bootstrap_<agent>.delivered` が残っていると、再ログイン後に bootstrap が再送されず auth menu で停止し続けた。
  Evidence: 実 runtime で `queue/runtime/bootstrap_ashigaru2.delivered` が残り `bootstrap_ashigaru2.pending` が無い状態から pane を shell に落とすと、再起動後は `node` に戻っても bootstrap marker が復元されなかった。修正後は同条件で `WATCHER_SUPERVISOR_ONCE=1 bash scripts/watcher_supervisor.sh` 実行後に `bootstrap_ashigaru2.pending` が再作成され、`bootstrap_ashigaru2.delivered` が消えた。
- Observation: `shutsujin_departure.sh` が `watcher_supervisor` を background 起動しただけでは、初回 tick の前に runtime 観測を始めると「watcher 起動完了」と表示されていても実 watcher log がまだ増えていないことがあった。
  Evidence: fresh startup 直後の `logs/inbox_watcher_ashigaru2.log` に新しい `inbox_watcher started` 行が出ず、`timeout 3 bash scripts/watcher_supervisor.sh` を foreground で手動実行した瞬間に watcher start と restart log が追記された。

## Decision Log
- Decision: 隔離先は repo の外だが同一ワークスペース配下の sibling directory とする。
  Rationale: `.git` 管理対象外にでき、元 repo の untracked/ignored 状態を汚さずに runtime 副作用を閉じ込めやすい。
  Date/Author: 2026-03-29 / Codex
- Decision: tmux socket だけは、ユーザー許可を得たうえで `/tmp/mas_isolated_runtime_validation_151700` を使う。
  Rationale: `/mnt/d` 配下では tmux の secure permission 要件を満たせず、実起動が不可能だったため。
  Date/Author: 2026-03-29 / Codex
- Decision: 隔離コピーの `lib/cli_adapter.sh` は検証用に限り `mock-bin/codex` の絶対パスを優先する。
  Rationale: pane shell が bare `codex` を実環境の CLI へ解決して即死し、queue / watcher 検証が進まないため。元 repo は変更しない。
  Date/Author: 2026-03-29 / Codex
- Decision: 本体 repo の Codex 用 `CODEX_HOME` は `.codex/agents/<agent>` ではなく `.shogunate/codex/agents/<agent>` に移す。
  Rationale: repo 直下 `.codex` は directory 前提を満たさず、Codex 側の state 隔離と起動前 directory 作成を両立するため。
  Date/Author: 2026-03-29 / Codex
- Decision: 実 Codex の sign-in menu / browser auth prompt を ready と見なさず、bootstrap を送らずに `auth-required` として runtime log に残す。
  Rationale: 未認証 pane へ bootstrap を送っても task 実行に入らず、失敗理由が見えなくなるため。
  Date/Author: 2026-03-29 / Codex
- Decision: `auth-required` は runtime 全体の致命エラーにせず、watcher / bridge / proxy session は起動継続する。
  Rationale: 認証完了後に同じ runtime を再利用でき、少なくとも未読 queue と session 構成を保持できるため。
  Date/Author: 2026-03-29 / Codex
- Decision: Codex の workspace trust prompt は update prompt と別処理に分け、常に `1. Yes, continue` を送る。
  Rationale: 実機では trust prompt が bootstrap 前に現れ、generic `Press enter to continue` 条件だと `2=No, quit` で Codex を落としてしまうため。
  Date/Author: 2026-03-29 / Codex
- Decision: bootstrap へ役職別の「初動最適化」文面を追加し、起動直後の探索対象を自 inbox / 自 task と役職指示書に限定する。
  Rationale: 実 task 投入前の寄り道探索が長く、将軍・家老とも event-driven へ戻るまで遅かったため。
  Date/Author: 2026-03-29 / Codex
- Decision: `scripts/inbox_watcher.sh` は unread 起動前に Codex の rate-limit / usage-limit prompt を検知し、必要に応じて `3` または `1` を送ってから nudge を続行する。
  Rationale: launcher 起動時だけでは runtime 中に出る Codex UI prompt を除去できず、未読処理が止まるため。
  Date/Author: 2026-03-29 / Codex
- Decision: 家老の `report_received` fast path は「relevant report YAML / parent cmd / dashboard.md」へ read scope を限定し、bridge / ntfy / streaks / sample は異常時以外読まない。
  Rationale: 終盤の不要探索で `cmd_done` 返却が遅れ、実検証の throughput を落としていたため。
  Date/Author: 2026-03-30 / Codex
- Decision: `karo_done_to_shogun_bridge.py` は active queue と archive file の両方を監視し、state key は `cmd_id+timestamp` とする。
  Rationale: 家老が `done` cmd を archive へ移す運用と両立しつつ、`cmd_001` のような再利用 ID でも別 run の完了を relay できるようにするため。
  Date/Author: 2026-03-30 / Codex
- Decision: auth prompt にぶつかった bootstrap は失敗扱いで捨てず、`queue/runtime/bootstrap_<agent>.pending` として保持して watcher に再配信させる。
  Rationale: 実運用では起動後にユーザーがログインを完了することがあり、その時点で runtime を立て直さなくても初動へ戻れる方が実用的なため。
  Date/Author: 2026-04-04 / Codex
- Decision: bootstrap 再配信は `tmux send-keys -l` の literal 送信を使い、通常の nudge と分けて扱う。
  Rationale: 初動文面は複数行・記号入りであり、通常の key sequence 送信だと崩れるため。
  Date/Author: 2026-04-04 / Codex
- Decision: 出陣スクリプトの二重起動ガードは `flock` ではなく lock dir + pid file へ置き換える。
  Rationale: tmux server への FD 継承で lock 解放タイミングが読めず、直列再起動まで不安定になるため。
  Date/Author: 2026-04-04 / Codex
- Decision: auth-required も hard usage-limit と同じ blocked notice helper に載せ、bootstrap 再配信成功時に clear する。
  Rationale: 起動後の運用面では「quota block」と「login待ち」はどちらも人手対応が要る blocked state であり、dashboard 上で同じ場所に集約した方が判断しやすいため。
  Date/Author: 2026-04-04 / Codex
- Decision: blocked notice の重複判定は「同じ agent / issue の既存行があるか」で行い、detail が変わった場合は追記ではなく 1 行置換にする。
  Rationale: detail は最新状態を反映したいが、同一 blocker が複数行に増えると dashboard の実用性を落とすため。
  Date/Author: 2026-04-04 / Codex
- Decision: blocked notice helper は対象 issue だけでなく要対応セクション全体を走査し、record / clear のたびに `runtime-blocked/<agent>` の duplicate を最後の 1 行へ畳み込む。
  Rationale: 過去 run の残骸を手動清掃に頼ると `dashboard.md` の実用性が戻らないため、運用中の自然な更新で自動修復させる方が安全なため。
  Date/Author: 2026-04-04 / Codex
- Decision: Codex の pending bootstrap 再送と startup の bootstrap 配信では、screen text だけでなく `#{pane_current_command}` が `node` であることも確認し、shell 戻り pane には送らない。
  Rationale: auth / update / usage error の後に Codex が終了して shell に戻るケースでは、screen text だけでは ready と非-ready を分け切れず、bootstrap 混線の実害が出るため。
  Date/Author: 2026-04-04 / Codex
- Decision: Codex shell-return の自動回復は `watcher_supervisor` と `inbox_watcher` の両方に持たせ、前者を高速経路、後者を timeout tick の保険とする。
  Rationale: detached supervisor の初回起動確認だけに頼ると実環境差で回復開始が遅れるため、per-agent watcher 側にも restart command を持たせた方が実用上安全なため。
  Date/Author: 2026-04-04 / Codex
- Decision: `shutsujin_departure.sh` は常駐 supervisor の前に `WATCHER_SUPERVISOR_ONCE=1` を同期実行し、初回 watcher 起動と shell-return recovery の最初の 1 回を startup 成功条件に含める。
  Rationale: background process のスケジュール待ちに依存すると「起動完了」と実際の監視開始時刻がずれるため。
  Date/Author: 2026-04-04 / Codex
- Decision: shell-return recovery が Codex 再起動を行う前に、当該 agent の `bootstrap_<agent>.pending` を再武装し、`bootstrap_<agent>.delivered` を除去する。
  Rationale: いったん初動命令を配信した agent でも、Codex 再起動後は auth / trust prompt を経て再び bootstrap 再試行が必要になるため、既配信 marker を残したままだと post-login の復帰導線が失われるため。
  Date/Author: 2026-04-04 / Codex
- Decision: `sync_runtime_cli_preferences.py` は changed が無い run を既定では無言にし、verbose が必要な時だけ env で no-op 出力を有効化する。
  Rationale: daemon 常駐時の log 増加を防ぎつつ、調査時だけ挙動を見られるようにするため。
  Date/Author: 2026-04-04 / Codex
- Decision: Gemini alias 同期は `alias -> base_model` の 2 段書き換えをやめ、最終的に settings へ保存したい `base_model` を直接比較する。
  Rationale: alias 表示は pane footer 用であり、settings 側は base model を持っていれば十分なので、毎回 changed 判定になる必要がないため。
  Date/Author: 2026-04-04 / Codex

## Outcomes & Retrospective
- Outcomes:
  - 隔離コピー側で `goza-no-ma`, `shogun`, `gunshi`, `multiagent` session 生成を確認した。
  - 単発 task では `cmd_new -> karo decomposition -> ashigaru1 task_assigned -> ashigaru1 done/report` を確認した。
  - 並列 task では `ashigaru1` / `ashigaru2` が別々に unread を受け、両方 `done` になった。
  - 実 `codex` でも pane 自体は起動し、認証待ち画面まで進むことを確認した。
  - 実 `codex` で task 実行に入れない主因は未認証であり、少なくとも `CODEX_HOME` 不存在による即死ではないことを切り分けた。
  - `queue/runtime/goza_bootstrap_<run-id>.log` へ `auth-required` / `bootstrap-delivered` を残す改善方針を実装した。
  - 実 `codex` 検証用に `queue/inbox/shogun.yaml` へ task を投入し、未認証状態では未読のまま滞留することを確認した。
  - sign-in menu 検知と `bootstrap 未配信でも継続` を追加し、runtime 起動自体は最後まで完了するようになった。
  - 認証済み WSL Codex を使う `Shogunate-test` 実機検証では、1 本目の task を end-to-end で完了できた。
  - 2 本目の task も `shogun -> karo` の再委譲まで進み、同じ経路が再利用できることを確認した。
  - 2026-03-30 の再開検証で、単発 task は修正後に再度 `cmd_done` まで完了した。
  - handoff 推奨の共同開発 task では `playground/queue_summary/` に `app.py` / `README.md` / `tests/test_app.py` を生成し、`python3 -m unittest` 3件 PASS まで確認した。
  - `scripts/karo_done_to_shogun_bridge.py` の archive relay 欠落を修正し、実機でも `cmd_done` が将軍 inbox へ戻ることを確認した。
  - 2026-04-04 の main repo 実行では、auth prompt が残っていても runtime 全体は最後まで起動し、最終案内が auth pending を正しく表示した。
  - 同日の watcher 単体回帰では、pending bootstrap を auth 解消後に literal 再配信し、`.pending` から `.delivered` へ進める経路を確認した。
  - 二重起動ガードは lock dir 方式へ更新し、直列 2 回実行は成功、並列実行は後続だけ fail-fast する状態にできた。
  - `codex-auth-required` も dashboard blocked notice へ記録し、bootstrap 再配信成功時に stale notice を除去する回帰を追加した。
  - 同一 agent / issue の auth notice は detail が変わっても 1 行更新に揃え、dashboard 上で増殖しないようにした。
  - record / clear のたびに要対応セクション内の既存 duplicate blocked notice も自動で 1 行へ正規化されるようになり、過去 run の残骸が dashboard に残り続けにくくなった。
  - Codex process が shell に戻った pane では pending bootstrap を保留するようにし、`codex --no-alt-screen` コマンド行へ初動命令が混線する実害を止めた。
  - shell に戻った Codex pane は `watcher_supervisor` / `inbox_watcher` の双方から restart command を再投入できるようになり、実観測でも `logs/inbox_watcher_ashigaru2.log` に `restarted shell-returned Codex pane` を確認した。
  - startup は `WATCHER_SUPERVISOR_ONCE=1` の同期 tick を挟むようになり、初回 watcher 起動を detached supervisor の初回 loop に依存しない形へ寄せた。
  - `runtime_cli_pref_daemon` の no-op / unchanged は既定で静かになり、Gemini alias 同期後の 2 回目 sync は `unchanged` 扱いへ戻せた。
- Gaps:
  - 今回の agent 実行は sandbox-local mock Codex を使ったため、実 `codex` SaaS 応答品質までは保証しない。
  - 実 `codex` での本当の task 実行完了は、認証が済んだ環境で再試験が必要。
  - E2E bats は test helper 実体が repo に無いため、この環境では補強できなかった。
  - 長時間連続運用で rate-limit / usage-limit が再発した場合の throughput 低下は、引き続き外部 quota 依存で残る。
- Lessons:
  - WSL の `/mnt/d` 配下で tmux を使う検証は、socket を Linux 側 filesystem へ逃がす前提で考えた方が早い。
  - bare command 解決に依存する CLI 起動は、tmux pane shell の PATH 差異で検証が揺れる。隔離検証では絶対パスが安全。
  - 実 Codex 検証では「pane が起動した」だけでは不十分で、認証待ちか prompt ready かを screen content と runtime log の両方で分けて観測する必要がある。
  - 認証済み state を local `CODEX_HOME` へ複製すれば、repo-local state 分離を保ったまま実 WSL Codex を使える。
  - update prompt と trust prompt を混同すると、実機だけで Codex が即終了する。prompt 判定は generic 文言より選択肢の固有文言で切る方が安全。
  - Codex の runtime blocker は auth / trust だけではなく、rate-limit warning と hard usage-limit もある。前者は code で捌けるが、後者は外部 quota が戻るまで repo 側だけでは突破できない。
  - bridge daemon は active queue 前提にせず、archive 運用とセットで設計しないと `cmd_done` が静かに欠落する。
  - `report_received` の closure 手順は「何を読むか」だけでなく「何を読まないか」まで明示した方が、Codex の寄り道を抑えやすい。
- Against Purpose:
  - 「隔離コピーで実起動し、複数 task の流れを確認する」という目的は mock Codex で達成。
  - 「実 Codex で task を回す」という追加目的は、未認証環境のため task 完了までは未達。ただし阻害要因の切り分けと起動導線の改善は完了。
  - その後の認証済み WSL 実機検証により、少なくとも 1 本は end-to-end 完了、2 本目も再委譲再現まで確認できた。
  - 2026-03-30 の再開検証により、単発 task と共同開発 task の両方で end-to-end 完了を再確認し、当初 handoff の成功条件 1〜4 はこの時点で満たせた。
