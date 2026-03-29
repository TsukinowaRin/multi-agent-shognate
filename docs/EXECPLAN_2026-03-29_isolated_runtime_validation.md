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
- Observation: Codex の初期 sign-in menu（`Sign in with ChatGPT` / `Provide your own API key`）は、browser auth prompt とは別画面のため、これも auth-required に含めないと pane ごとに 30 秒待たされる。
  Evidence: 実測では `karo`, `ashigaru1`, `ashigaru2`, `gunshi` が sign-in menu で停止し、検知条件を広げる前は個別待機が長引いた。
- Observation: auth-required を `deliver_bootstrap_tmux` の非0 return で返すだけだと、起動元の `set -e` により runtime 全体が abort した。
  Evidence: 修正途中の実行で `real_codex_startup.log` が `各エージェントに指示書を読み込ませ中...` 直後に止まり、再試験で `bootstrap 未配信でも継続` 分岐を入れると最後まで起動した。
- Observation: 実 task を `queue/inbox/shogun.yaml` へ投入しても、未認証のままでは message は `read: false` のまま残り、`queue/reports/karo_report.yaml` は生成されない。
  Evidence: `msg_20260329_180458_ed4bb65d` を投入後、10 秒以上待っても inbox は未読のままで report 不在だった。

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
- Gaps:
  - 今回の agent 実行は sandbox-local mock Codex を使ったため、実 `codex` SaaS 応答品質までは保証しない。
  - 実 `codex` での本当の task 実行完了は、認証が済んだ環境で再試験が必要。
  - E2E bats は test helper 実体が repo に無いため、この環境では補強できなかった。
- Lessons:
  - WSL の `/mnt/d` 配下で tmux を使う検証は、socket を Linux 側 filesystem へ逃がす前提で考えた方が早い。
  - bare command 解決に依存する CLI 起動は、tmux pane shell の PATH 差異で検証が揺れる。隔離検証では絶対パスが安全。
  - 実 Codex 検証では「pane が起動した」だけでは不十分で、認証待ちか prompt ready かを screen content と runtime log の両方で分けて観測する必要がある。
- Against Purpose:
  - 「隔離コピーで実起動し、複数 task の流れを確認する」という目的は mock Codex で達成。
  - 「実 Codex で task を回す」という追加目的は、未認証環境のため task 完了までは未達。ただし阻害要因の切り分けと起動導線の改善は完了。
