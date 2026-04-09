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
- [x] (2026-04-04 18:3x JST) `runtime_blocker_notice.py` が auth prompt / hard usage-limit の detail を issue 別の安定要約へ正規化し、pane capture の揺れだけで `dashboard.md` と watcher log を更新し続けないようにした。
- [x] (2026-04-04 20:4x JST) `runtime_blocker_notice.py` が壊れた `dashboard.md` の骨格も自動修復し、garbled auth detail と duplicate section を残さないようにした。
- [x] (2026-04-04 21:2x JST) main repo の実 Codex runtime で `cmd_001`, `cmd_002` を連続投入し、どちらも `shogun -> karo -> ashigaru -> karo -> shogun` の `cmd_done` 返却と将軍報告まで完了した。
- [x] (2026-04-04 21:4x JST) 共同開発 task `cmd_003` では `runtime_sandboxes/live_validation_probe/` へのファイル生成自体は成功した一方、report が主張した `python3 -m unittest` 成功を再現できず、verification contract 不足を実 runtime で確認した。
- [x] (2026-04-04 21:5x JST) 足軽 report に exact verification command / cwd / result を必須化し、家老が implementation task close 前に reported command を rerun する instruction 契約と build_system 回帰を追加した。
- [x] (2026-04-05 14:3x JST) main repo runtime の burn-in `cmd_900` で `shogun -> karo -> ashigaru1/2 -> karo -> shogun` の `cmd_done` 完走を再確認し、`runtime_sandboxes/burnin_probe_three/` に blocked 集計追加が反映された。
- [x] (2026-04-05 14:5x JST) `karo` pane に出た折返し `switch-confirm` / `Keep current model` prompt が watcher / startup の行単位 `grep` を抜けることを再現し、compact 判定へ修正した。
- [x] (2026-04-04 21:4x JST) clean start 後の main repo runtime で、old archive `cmd_003` が `karo_done_to_shogun_bridge` から再度 `cmd_done` として将軍 inbox へ戻ることを確認し、bridge state 持ち越しが restart 直後の stale replay を起こすと切り分けた。
- [x] (2026-04-04 21:5x JST) `shutsujin_departure.sh -c` が `queue/runtime/shogun_to_karo_bridge.tsv` と `queue/runtime/karo_done_to_shogun.tsv` を消すようにし、clean start 時の old archive replay 防止回帰を追加した。
- [x] (2026-04-04 22:0x JST) burn-in 2 本目で ashigaru2 pane が `codex --model left` で起動し、`The 'left' model ... account` 風の error で task 受領後に停止することを再現した。
- [x] (2026-04-04 22:0x JST) `sync_runtime_cli_preferences.py` の Codex parser が `context left` / `% left` を model と誤認しないよう修正し、起動側も invalid codex model を無視する回帰を追加した。
- [x] (2026-04-04 22:0x JST) 修正後の clean start で ashigaru2 pane の起動コマンドから `--model left` が消え、pane footer が `model: gpt-5.4` に戻ることを実機確認した。
- [x] (2026-04-05 13:0x JST) shared auth 導入後の live burn-in で、`karo` watcher の unread 停滞は unread 処理そのものではなく、`shutsujin_departure.sh` から起動した watcher / bridge / runtime sync が親シェル終了後に残らないことが主因と切り分けた。
- [x] (2026-04-05 13:0x JST) 常駐系を `goza-runtime` tmux daemon session へ移し、fresh runtime 後も `karo` watcher が timeout tick を跨いで生存し、`queue/inbox/karo.yaml` の unread を既読化することを main repo 実行で確認した。
- [x] (2026-04-09 01:2x JST) live burn-in `cmd_904` で、`ashigaru1` が app.py 改修と unittest 成功を pane 上で完了しても `queue/reports/ashigaru1_report.yaml` が `idle/null` のまま残り、家老 close が止まる failure class を確認した。
- [x] (2026-04-09 01:3x JST) `scripts/inbox_watcher.sh` に「open task はあるが report が未完で pane は idle」の ashigaru 専用 recovery を追加し、timeout fast-path でも auto-recovery `task_assigned` を再注入できる回帰を加えた。
- [x] (2026-04-09 01:3x JST) live runtime で実際に `ashigaru1` inbox へ auto-recovery `task_assigned` が再注入され、旧 `inbox1` だけでは弱いと分かったため、wake-up 文面を `queue/tasks/ashigaruN.yaml` / `queue/reports/ashigaruN_report.yaml` 明示へ強化した。
- [x] (2026-04-09 09:4x JST) `watcher_supervisor.sh` / `inbox_watcher.sh` に startup grace と initial bootstrap pending 抑止を入れ、fresh start 直後の shell-return recovery が Codex launch command を会話入力へ混線させないようにした。unit 回帰 147 件が通り、以後の clean start では `watcher_supervisor.log` に直後の `restarted shell-returned codex pane` が増えないことを確認した。
- [x] (2026-04-09 09:5x JST) main repo の fresh runtime で `cmd_001` を再投入し、`shogun -> karo -> ashigaru1/2` まで実経路を確認した。同時に、Codex pane に `Messages to be submitted after next tool call` が見えている間も watcher が `inboxN` を追加入力してしまう failure class を再現し、`lib/agent_status.sh` で queued follow-up / recent `Working (...)` を busy とみなす回帰を追加した。
- [x] (2026-04-09 10:0x JST) 上記 busy 判定強化後の再試験で、`shogun` watcher log は最初の `Wake-up sent` 後に `Agent shogun is busy (codex), deferring nudge` へ切り替わり、同一 turn への `inboxN` 追加入力が止まることを確認した。
- [x] (2026-04-09 10:0x JST) live pane で、将軍が通常開発 task を受けた際に `app.py` / tests / `git status` を掘ってしまう role drift を確認し、`shogun_role.md` と startup bootstrap を「routing 情報だけで即 cmd 起票、実装調査禁止」の dispatch fast path へ更新した。generated instruction と build_system 回帰も再生成済み。

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
- Observation: blocked notice helper 自体は duplicate を返せても、auth prompt の pane capture が毎回少しずつ揺れると detail 差分で `updated` 扱いになり、`dashboard.md` の `最終更新` と watcher log の `runtime blocker notice recorded ...` が 30 秒ごとに増え続けた。
  Evidence: `logs/inbox_watcher_shogun.log` に同じ `codex-auth-required` の `recorded` 行が連続し、既存 `dashboard.md` の shogun notice detail には sign-in menu 以外の garbled text が混ざっていた。helper 修正後は noisy な prompt 文字列 2 種を `python3 -m unittest tests.unit.test_runtime_blocker_notice` で同一 blocker として `duplicate` 判定できることを確認した。
- Observation: `dashboard.md` が一度 3 行だけの中途半端な形に崩れると、旧 helper は heading の最低条件だけ満たしたファイルを valid 扱いし、末尾に duplicate section 残骸を抱えたまま運用が続いた。
  Evidence: 実 runtime の `dashboard.md` は `wc -l` で 3 行しかない状態から始まり、その後の helper 実行で `# 📊 戦況報告` は戻っても `## 🛠️ 生成されたスキル` 以降が重複していた。修正後は `python3 scripts/runtime_blocker_notice.py --project-root . --agent shogun --issue codex-auth-required ...` 実行後に、`dashboard.md` の既知 section が 1 回ずつの骨格へ戻り、garbled auth detail も generic detail へ正規化された。
- Observation: `shutsujin_departure.sh` が `watcher_supervisor` を background 起動しただけでは、初回 tick の前に runtime 観測を始めると「watcher 起動完了」と表示されていても実 watcher log がまだ増えていないことがあった。
  Evidence: fresh startup 直後の `logs/inbox_watcher_ashigaru2.log` に新しい `inbox_watcher started` 行が出ず、`timeout 3 bash scripts/watcher_supervisor.sh` を foreground で手動実行した瞬間に watcher start と restart log が追記された。
- Observation: main repo で auth 済み pane を使うと、`cmd_001` と `cmd_002` は連続で `cmd_done` まで完了し、`queue/shogun_to_karo_archive.yaml` と `queue/inbox/shogun.yaml` に終端状態が残った。
  Evidence: `queue/shogun_to_karo_archive.yaml` に `cmd_001` / `cmd_002` の `status: done`、`queue/inbox/shogun.yaml` に対応する `cmd_done` があり、shogun pane capture に完了報告が残った。
- Observation: 共同開発 task `cmd_003` の足軽 report は `python3 -m unittest` 成功を主張したが、実際に `runtime_sandboxes/live_validation_probe` で同コマンドを実行すると `ModuleNotFoundError: No module named 'runtime_sandboxes'` で失敗した。
  Evidence: `queue/reports/ashigaru1_report.yaml` の `notes` と、`cd runtime_sandboxes/live_validation_probe && python3 -m unittest` の実行結果が矛盾した。
- Observation: clean start 後でも `queue/shogun_to_karo_archive.yaml` の old `cmd_003` が `cmd_done` として将軍 inbox に再配送され、新しい task より先に stale 完了報告を処理し始めた。
  Evidence: `queue/inbox/shogun.yaml` に `msg_20260404_214258_4657c810` の `cmd_done` が再出現し、`queue/shogun_to_karo.yaml` は空なのに shogun pane が `cmd_003` の後始末を始めた。
- Observation: burn-in 2 本目で ashigaru2 pane は `codex --model left` で起動しており、pane capture に `The 'left' model ... account` 風の JSON error が出て task unread を処理できなかった。
  Evidence: `tmux capture-pane -pt goza-no-ma:overview.4 -S -200` に `NO_UPDATE_NOTIFIER=1 codex --model left ...` と error text が残り、`queue/inbox/ashigaru2.yaml` の `task_assigned` が unread のまま滞留した。
- Observation: `sync_runtime_cli_preferences.py` の `parse_codex_state()` は `context left · /model to change` や `% left` からも `left` を抜けてしまう。
  Evidence: 実 regex probe で `context left · /model to change` と `% left · ...` の両方が `('left', None)` に match した。
- Observation: shared auth 導入後の `bash shutsujin_departure.sh -c` では `goza-no-ma` の agent pane は生きていた一方、`logs/inbox_watcher_karo.log` は startup 行しか増えず、`queue/inbox/karo.yaml` の unread が残り続けた。
  Evidence: `ps` では `watcher_supervisor.sh` / `inbox_watcher.sh` が残らず、foreground で `timeout 8 bash -x scripts/inbox_watcher.sh karo %1 codex tmux` を回すと unread 処理自体は正常に動いた。
- Observation: 常駐系を `goza-runtime` tmux daemon session へ移した後は、`tmux list-windows -t goza-runtime` で `watcher`, `shogun-to-karo`, `karo-to-shogun` が残り、`karo` watcher が 30 秒 timeout ごとに unread を再処理して最終的に既読化した。
  Evidence: `logs/inbox_watcher_karo.log` に `13:07:31`, `13:08:00` の unread 処理と `13:08:28` の `All messages read` が残り、`queue/inbox/karo.yaml` は `read: true` へ変わった。
- Observation: `WATCHER_SUPERVISOR_ONCE=1 bash scripts/watcher_supervisor.sh` は backend pane がまだ無い状態だと exit code 1 で落ち、通常常駐 supervisor も startup race で即死しうる。
  Evidence: `tmux kill-session -t goza-no-ma ...; WATCHER_SUPERVISOR_ONCE=1 bash scripts/watcher_supervisor.sh; echo status:$?` で `status:1` を再現し、`supervisor_tick` 内の `pane="$(resolve_agent_pane_target ...)"` が `set -e` を踏むことを確認した。
- Observation: Codex の mini switch prompt には `Approaching rate limits` や `Keep current model` が出ず、`› 1. Switch to gpt-5.1-…` と `Press enter to confirm` だけの variant がある。
  Evidence: `tmux capture-pane -pt goza-no-ma:overview.3 | tail -n 40` と `.4` で switch-only prompt を確認し、既存 `dismiss_codex_rate_limit_prompt_if_present` の regex では未検知だった。
- Observation: `WATCHER_SUPERVISOR_ONCE` が spawn した `inbox_watcher` は startup 中の bootstrap 再配信までは動くが、その後は残らず、`goza-runtime:watcher` だけが残って child watcher が消えることがあった。
  Evidence: `logs/inbox_watcher_shogun.log` には `13:38:55` 前後の `inbox_watcher started` と `bootstrap retried and delivered` が出る一方、`ps -ef | grep '[i]nbox_watcher.sh'` は空で、`tmux list-windows -t goza-runtime` に per-agent watcher window が無かった。

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
- Decision: watcher / bridge / runtime sync の常駐系は `nohup/disown` ではなく、`goza-runtime` tmux daemon session の window として管理する。
  Rationale: 起動元シェルや外側の process cleanup に巻き込まれず、fresh runtime 後も watcher timeout tick と bridge relay を継続させるため。
  Date/Author: 2026-04-05 / Codex
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
- Decision: `runtime_blocker_notice.py` は issue ごとに detail を正規化し、`codex-auth-required` は login menu / browser auth / login server error、`codex-hard-usage-limit` は retry 時刻などの安定要約だけを保持する。
- Observation: `karo` pane の hard `usage-limit` が折返しで `You've hit your` / `usage limit` / `try ag` / `ain at ...` に分断されると、watcher / startup の単純 `grep` が取りこぼし、`Wake-up sent to karo` を繰り返した。
  Evidence: `logs/inbox_watcher_karo.log` に 30 秒ごとの nudge が並び、pane capture では footer ではなく usage-limit 画面だった。compact 判定追加後は `tests/unit/test_send_wakeup.bats` の wrapped fixture が hard block として PASS した。
- Observation: `runtime_cli_pref_daemon` は isolated tmux probe では残る一方、fresh start では `goza-runtime` から消えることがあり、起動後の self-heal が必要だった。
  Evidence: `tmux list-windows -t goza-runtime` では `watcher` / bridge / `inbox-*` だけが残り、`runtime-pref` が欠落していた。manual `tmux new-window ... runtime_cli_pref_daemon.sh` では残った。
- Decision: hard `usage-limit` 判定は raw pane text ではなく compact 文字列で行い、空白・折返しを落として `youvehityourusagelimit` / `tryagainat` を拾う。
- Decision: `runtime-pref` は startup 後に `ensure_tmux_runtime_daemon_window` で再補充し、legacy cleanup の `pkill runtime_cli_pref_daemon.sh` は前段 cleanup のみに寄せる。
  Rationale: watcher が毎周生の pane capture を渡すと detail が揺れやすく、同じ blocker でも helper が `updated` を返して dashboard 更新と log 出力が止まらなくなるため。
  Date/Author: 2026-04-04 / Codex
- Decision: `runtime_blocker_notice.py` は既知 section の本文を抽出して `dashboard.md` 全体を再構築できるようにし、壊れた runtime 生成物も natural update の中で自己修復させる。
  Rationale: `dashboard.md` は tracked file ではない runtime 生成物なので、別コマンドでの手動掃除に頼るより helper 自体が骨格を戻せる方が実運用で安全なため。
  Date/Author: 2026-04-04 / Codex
- Decision: `sync_runtime_cli_preferences.py` は changed が無い run を既定では無言にし、verbose が必要な時だけ env で no-op 出力を有効化する。
  Rationale: daemon 常駐時の log 増加を防ぎつつ、調査時だけ挙動を見られるようにするため。
  Date/Author: 2026-04-04 / Codex
- Decision: Gemini alias 同期は `alias -> base_model` の 2 段書き換えをやめ、最終的に settings へ保存したい `base_model` を直接比較する。
  Rationale: alias 表示は pane footer 用であり、settings 側は base model を持っていれば十分なので、毎回 changed 判定になる必要がないため。
  Date/Author: 2026-04-04 / Codex
- Decision: `ashigaru` の close 漏れは instruction 文面だけに頼らず、watcher が `queue/tasks/ashigaruN.yaml` と `queue/reports/ashigaruN_report.yaml` の current `task_id` 不一致を見て auto-recovery `task_assigned` を再投入する。
  Rationale: live burn-in では test pass を出した後に report YAML だけ落とすケースがあり、event-driven を崩さず recovery するには idle timeout tick に current task/report mismatch を乗せるのが最小修正だったため。
  Date/Author: 2026-04-09 / Codex
- Decision: `ashigaru` の unread `task_assigned` と auto-recovery は generic な `inboxN` ではなく、`queue/tasks/ashigaruN.yaml` と `queue/reports/ashigaruN_report.yaml` を明示する wake-up 文面で起こす。
  Rationale: live runtime では auto-recovery 自体は届いても、generic nudge だと足軽が task close ではなく周辺 docs 探索へ流れやすく、再着手の焦点が弱かったため。
  Date/Author: 2026-04-09 / Codex
- Decision: implementation 系 task の close 契約は、report 要約の自然言語ではなく `result.verification.command` / `cwd` / `result` を正本とし、家老が reported command を rerun してから close する。
  Rationale: 実 runtime の共同開発 task で、足軽 report が test pass を主張しても実コマンドが失敗する false-positive を確認し、report 文面だけでは品質を担保できないと分かったため。
  Date/Author: 2026-04-04 / Codex
- Decision: `shutsujin_departure.sh -c` は queue だけでなく bridge state も捨て、restart 後は archive を再 prime させる。
  Rationale: active queue を空にしても `karo_done_to_shogun.tsv` を持ち越すと、clean start 直後に old archive `done` が新着 `cmd_done` として shogun inbox へ戻り、fresh run の初動を汚すため。
  Date/Author: 2026-04-04 / Codex
- Decision: Codex runtime preference sync は `% left` を含む status line だけを parse 対象とし、`left` / `context` など UI 断片は invalid codex model として settings 保存も launch 時指定も拒否する。
  Rationale: 実 burn-in で ashigaru2 が `--model left` に壊れ、auth や usage-limit ではない model corruption で停止したため。
  Date/Author: 2026-04-04 / Codex
- Decision: Codex の rate-limit prompt dismiss は `Approaching rate limits` だけでなく、`2. Keep current model` と `3. Hide future rate limit` を含む新しい prompt variant も検知対象に含める。
  Rationale: 実 burn-in で karo pane に新 variant が出た際、watcher / startup の既存 regex が一致せず、dismiss が走らない repo bug を確認したため。
  Date/Author: 2026-04-04 / Codex
- Decision: `scripts/inbox_watcher.sh` は unread 件数に関係なく startup / idle loop ごとに `maintain_codex_runtime_prompt` を通し、Codex runtime prompt を事前掃除する。
  Rationale: 実 runtime で karo / gunshi / ashigaru2 の rate-limit prompt が idle 中に差し込まれ、未読が来るまで dismiss が走らず将来の task を待ち伏せで詰まらせることを確認したため。
  Date/Author: 2026-04-04 / Codex
- Decision: `watcher_supervisor.sh` は pane 未生成を正常系として扱い、`resolve_agent_pane_target` の失敗で supervisor 全体を終了させない。
  Rationale: startup race は fresh runtime で必ず起こりうるため、次 tick で自己回復できる設計の方が practical だから。
  Date/Author: 2026-04-05 / Codex
- Decision: Codex の switch-only confirm prompt は `3` や `1` を再送せず、`Enter` だけを送って確定する。
  Rationale: 現物 pane では選択肢が 1 つに絞られており、`Press enter to confirm` が UI 契約になっていたため。
  Date/Author: 2026-04-05 / Codex
- Decision: `inbox_watcher` は background `nohup` child ではなく、`goza-runtime` 配下の `inbox-<agent>` tmux window として管理する。
  Rationale: startup one-shot 由来の watcher は shell 寿命や runtime 観測条件に引きずられやすく、supervisor から再生成可能な tmux window の方が practical だから。
  Date/Author: 2026-04-05 / Codex
- Decision: `shutsujin_departure.sh` は runtime daemon session を起こした後に、`WATCHER_RUNTIME_SESSION="$RUNTIME_DAEMON_SESSION"` 付きで watcher one-shot seed をもう一度流す。
  Rationale: startup 前半の one-shot だけでは pane/daemon session の安定化前に走ってしまい、fresh start 完了時点で `inbox-<agent>` window が無いことがあったため。
  Date/Author: 2026-04-05 / Codex
- Decision: `goza-runtime:watcher` 自体も long-lived `bash scripts/watcher_supervisor.sh` ではなく、`WATCHER_SUPERVISOR_ONCE=1` の periodic tick loop として起動する。
  Rationale: 実観測で one-shot は効く一方、常駐 supervisor 本体は startup race 後に tick を継続していない疑いがあり、実績のある one-shot 実行を daemon 化する方が安定だから。
  Date/Author: 2026-04-05 / Codex
- Decision: Codex ready 判定は裸の `codex` 文字列を使わず、`OpenAI Codex` header、`/model to change`、`Use /skills`、`Working ... esc to interrupt` など UI ready 文面に限定する。
  Rationale: 実 pane で起動コマンド行の `codex --model ... --no-alt-screen` を ready と誤認し、`--no-alt-screeninbox1` のような bootstrap 混線を再現したため。
  Date/Author: 2026-04-08 / Codex
- Decision: startup 側の Codex bootstrap wait は既定 30 秒の full wait をやめ、短い wait 後に `ready-pending` として watcher retry へ委譲する。
  Rationale: fresh start の実測で `goza-runtime` 起動が各 pane の逐次 30 秒待機に引きずられ、runtime daemon の立ち上がりが数分単位で遅れたため。
  Date/Author: 2026-04-08 / Codex
- Decision: startup 側 `deliver_bootstrap_tmux()` は送信直前にも `bootstrap_<agent>.pending` を再確認し、watcher が先に配信済みなら `already-delivered` として no-op に切り替える。
  Rationale: fresh runtime 実観測で watcher が先に `bootstrap retried and delivered` を出した後も startup 側が blind に再送し、`karo` pane に初動文面が二重注入されていたため。
  Date/Author: 2026-04-09 / Codex
- Decision: Codex bootstrap 後に pane が `Pasted Content ...` composer のままなら、startup / watcher は追い `Enter` を送り、それでも残る場合は `bootstrap-send-failed` として扱う。
  Rationale: fresh runtime 実観測で二重送信とは別に、単発の bootstrap 自体が `Pasted Content 1442 chars` の未送信状態で止まっていたため。
  Date/Author: 2026-04-09 / Codex

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
  - 2026-04-08 の runtime 再検証で `ashigaru1` の `--no-alt-screeninbox1` 混線を再現し、Codex ready 誤判定を修正した結果、同 pane は通常の `OpenAI Codex` footer で待機するところまで戻せた。
  - 同日の startup 修正では `goza-runtime` が fresh start 後に再び作成され、`watcher_supervisor 起動完了（tmux daemon session: goza-runtime）` と `runtime_cli_pref_daemon 起動完了` を trace 上で確認した。
  - 2026-04-09 の fresh runtime では watcher が `bootstrap retried and delivered for karo/gunshi` を startup より先に実行しうることを確認し、startup 側に `pending` 再確認を追加して二重 bootstrap 注入の経路を塞いだ。
  - 同日の fresh runtime で `karo` pane が `› m[Pasted Content 1442 chars]` の未送信状態で止まることも再現し、Codex bootstrap 後の pasted-content confirm を startup / watcher の双方に追加した。
  - main repo の auth 済み実 Codex runtime では、`cmd_001` と `cmd_002` の 2 本を連続で `cmd_done` まで完了できた。
  - 共同開発 task `cmd_003` の実観測から、検証結果の虚偽報告を instruction / protocol 契約で抑止する必要があることを特定し、exact command/cwd 記録と karo rerun-before-close を導入した。
  - clean start で old archive `cmd_done` が shogun inbox へ戻る replay も確認し、bridge state を clean start で捨てる修正を追加した。
  - burn-in 2 本目で見つかった `--model left` corruption も修正し、ashigaru2 の fresh start が `model: gpt-5.4` へ戻ることを実機確認した。
  - burn-in 継続中に出た新しい Codex rate-limit prompt variant も watcher / startup で dismiss できるようにし、`Keep current model` / `Hide future rate limit` 文言差分で止まらない回帰を追加した。
  - watcher の idle loop でも Codex runtime prompt を proactive に掃除するようにし、fresh runtime の実 pane で karo / ashigaru2 の rate-limit prompt が通常 footer へ戻ることを確認した。
- Gaps:
  - 今回の agent 実行は sandbox-local mock Codex を使ったため、実 `codex` SaaS 応答品質までは保証しない。
  - 実 `codex` での本当の task 実行完了は、認証が済んだ環境で再試験が必要。
  - E2E bats は test helper 実体が repo に無いため、この環境では補強できなかった。
  - 長時間連続運用で rate-limit / usage-limit が再発した場合の throughput 低下は、引き続き外部 quota 依存で残る。
  - `cmd_003` 自体は旧 instruction のまま進行した task なので、新しい verification contract が live runtime で closure を止められるかは次回 task で再確認が必要。
  - 新しい rate-limit prompt variant の live dismiss は対象回帰までは通したが、fresh runtime の burn-in 本番では次の task で再確認が必要。
  - fresh runtime の task 投入直後、shogun 自体は 2026-04-05 01:55 AM 再試行の hard usage-limit に入ったため、`cmd_done` までの burn-in 継続は外部 quota 復帰待ちで止まっている。
- Lessons:
  - WSL の `/mnt/d` 配下で tmux を使う検証は、socket を Linux 側 filesystem へ逃がす前提で考えた方が早い。
  - bare command 解決に依存する CLI 起動は、tmux pane shell の PATH 差異で検証が揺れる。隔離検証では絶対パスが安全。
  - 実 Codex 検証では「pane が起動した」だけでは不十分で、認証待ちか prompt ready かを screen content と runtime log の両方で分けて観測する必要がある。
  - 認証済み state を local `CODEX_HOME` へ複製すれば、repo-local state 分離を保ったまま実 WSL Codex を使える。
  - update prompt と trust prompt を混同すると、実機だけで Codex が即終了する。prompt 判定は generic 文言より選択肢の固有文言で切る方が安全。
  - Codex の runtime blocker は auth / trust だけではなく、rate-limit warning と hard usage-limit もある。前者は code で捌けるが、後者は外部 quota が戻るまで repo 側だけでは突破できない。
  - Codex の rate-limit warning は prompt 文言が固定ではなく、選択肢表示の差分で regex を外すことがある。dismiss 判定は単一文言ではなく、選択肢セットも含めて持った方が安全。
  - Codex の runtime prompt は unread 到来時だけ処理していると遅い。idle 巡回で事前掃除しておくと、次の task 到来時に prompt 残骸を踏みにくい。
  - bridge daemon は active queue 前提にせず、archive 運用とセットで設計しないと `cmd_done` が静かに欠落する。
  - `report_received` の closure 手順は「何を読むか」だけでなく「何を読まないか」まで明示した方が、Codex の寄り道を抑えやすい。
- Against Purpose:
  - 「隔離コピーで実起動し、複数 task の流れを確認する」という目的は mock Codex で達成。
  - 「実 Codex で task を回す」という追加目的は、未認証環境のため task 完了までは未達。ただし阻害要因の切り分けと起動導線の改善は完了。
  - その後の認証済み WSL 実機検証により、少なくとも 1 本は end-to-end 完了、2 本目も再委譲再現まで確認できた。
  - 2026-03-30 の再開検証により、単発 task と共同開発 task の両方で end-to-end 完了を再確認し、当初 handoff の成功条件 1〜4 はこの時点で満たせた。
