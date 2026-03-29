# ExecPlan: Isolated Runtime Validation In Workspace Sandbox

## Context
- ユーザー要求は、最新統合済みコードを元の作業ツリーとは別の隔離フォルダへコピーし、そのコピーで実起動と代表タスク実行まで確認すること。
- この repo は tmux session、`queue/`, `status/`, `logs/`, repo-local `HOME` など実行時副作用を持つため、元ツリーを直接使うと前回状態と混ざる。
- ワークスペース外参照は禁止されているため、隔離先は `/mnt/d/Git_WorkSpace/multi-agent-shognate` 配下に閉じ込める。

## Scope
- ワークスペース内に隔離コピーを作成する。
- 隔離コピー側で runtime を起動し、tmux session と代表タスク処理を確認する。
- docs に検証結果、観測、残リスクを残す。

## Acceptance Criteria
1. 隔離コピーがワークスペース内に存在し、主要 runtime ファイルを含む。
2. 隔離コピー側で `bash shutsujin_departure.sh -s` が成功し、`goza-no-ma` と Android 互換 session が生成される。
3. 代表タスクを複数投入し、少なくとも単発タスクと並列タスクの配送結果を観測できる。
4. `tmux capture-pane`, `queue/`, `status/`, `dashboard.md` のいずれかで完了または失敗の理由を確認できる。
5. 必要な e2e / smoke コマンドを実行し、失敗時は環境依存か実装不良かを切り分けられる。

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

## Surprises & Discoveries
- Observation: tmux socket を `/mnt/d/...` 配下へ置くと、WSL 側で `unsafe permissions` 扱いになり session 作成に失敗する。
  Evidence: `env TMUX_TMPDIR=... tmux new-session -d -s probe_goza 'sleep 3'` が `directory ... has unsafe permissions` を返した。
- Observation: 隔離コピー内で `PATH` を export しても、tmux pane 内の shell では bare `codex` が実 `codex` を解決した。
  Evidence: pane capture に `WARNING: ... CODEX_HOME points to ... does not exist` と実 `codex` のエラーが残った。
- Observation: sandbox 内の `lib/cli_adapter.sh` を一時的に絶対パスの `mock-bin/codex` へ向けると、pane 側は想定どおり mock Codex で待機・nudge 応答した。
  Evidence: pane capture に `[mock] Processed input`, `[mock] Task ... -> done` が出力された。
- Observation: `bats tests/e2e/e2e_inbox_delivery.bats tests/e2e/e2e_parallel_tasks.bats` は `tests/test_helper/bats-support/load` 欠落で setup_file 失敗した。
  Evidence: source repo 側でも `tests/test_helper/bats-support` / `bats-assert` は空 directory で、helper 実体が入っていなかった。

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

## Outcomes & Retrospective
- Outcomes:
  - 隔離コピー側で `goza-no-ma`, `shogun`, `gunshi`, `multiagent` session 生成を確認した。
  - 単発 task では `cmd_new -> karo decomposition -> ashigaru1 task_assigned -> ashigaru1 done/report` を確認した。
  - 並列 task では `ashigaru1` / `ashigaru2` が別々に unread を受け、両方 `done` になった。
- Gaps:
  - 今回の agent 実行は sandbox-local mock Codex を使ったため、実 `codex` SaaS 応答品質までは保証しない。
  - E2E bats は test helper 実体が repo に無いため、この環境では補強できなかった。
- Lessons:
  - WSL の `/mnt/d` 配下で tmux を使う検証は、socket を Linux 側 filesystem へ逃がす前提で考えた方が早い。
  - bare command 解決に依存する CLI 起動は、tmux pane shell の PATH 差異で検証が揺れる。隔離検証では絶対パスが安全。
- Against Purpose:
  - 「隔離コピーで実起動し、複数 task の流れを確認する」という目的は達成。
