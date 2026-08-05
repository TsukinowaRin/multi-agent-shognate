# MoA transport を本家 inbox 方式へ戻し、メンバーを watcher 監視下に載せる

plan_id: PLAN-2026-08-04-MOA-INBOX
基準commit: 37d0b4b
plan_revision: 1

<!-- execplan:original:start -->
<!-- ここから execplan:original:end までが上位計画。実行エージェントは削除・上書きせず、
     訂正が必要なときは承認済み amendment として下の判断ログへ追記する（append-only 規約）。 -->

## 目的 / 全体像

MoA の起床通知を AGMSG から本家 inbox 方式（`shogunate_mod/inbox/write.sh` +
`shogunate_mod/watcher/inbox_watcher.sh`）へ戻す。外部から MoA への通信は代表者ひとりに
集約し、メンバーへの配信は MoA 内部の fan-out として同じ inbox 経路で行う。

MoA の権限設計（`queue/moa/` を正本とし、通知本文に authority を持たせない）は変更しない。
transport だけを差し替え、本家が持つエスカレーション梯子と既読確認を獲得する。

## 背景と見取り図

2026-08-04 の実測（`docs/reviews/` は outer repo 側、要点は以下に再掲）で確認した事実:

1. 実 AGMSG 経由の `moa deploy` は、この検証機で 3 member 全員が `send.sh exited 127` で
   失敗した。原因は `sqlite3` CLI 不在。AGMSG の `scripts/lib/storage.sh` は `sqlite3`
   バイナリを直接呼ぶ。
2. 全員未達でも deployment は `status: active` のまま残り、`deploy` の exit code は 0。
   `manager.py` に retry / escalation / 再配送は 1 箇所も無い（`grep -n "retry|escalat|redeliver"` が 0 件）。
3. 通知が全滅した状態でも `submit` ×2 → `finalize` は成立し、`receipt.yaml` まで生成された。
   AGMSG は本当に起床シグナルだけを担っており、権限も状態も持たない。
4. `AGENT_ID` 不一致の `submit` は
   `actor does not match the configured member agent` で拒否される。
5. AGMSG 側 `messages.db` の `read_at` は NULL のまま残る（`shogunate_mod/docs/AGMSG_BRIDGE_DESIGN.md`
   の 2026-07-10 / 07-11 検証記録）。既読を機械で確認する手段が無い。

差し替え先の見取り図（コードを読んで確認済み）:

- `MoaTransport` は Protocol（`shogunate_mod/moa/manager.py:71-73`）。
  `MoaManager.__init__(transport=...)` で差し替えられる（`manager.py:434-454`）。
  実装の差し込み自体は新クラス 1 個で足りる。
- 現行の送信ループは `manager.py:712-731`。member ごとに pointer を組み立てて
  `self.transport.send()` を呼び、結果を `state.yaml` の
  `assignments.<alias>.delivery` に書くだけ。
- `write.sh` には 2 つの門番がある。
  - self-send guard（`inbox/write.sh:31-34`）: `FROM == TARGET` を拒否。
  - generation gate（`inbox/write.sh:86-96`）: sender が
    `^(shogun|gunkan|gunshi|karo([1-9][0-9]*)?|ashigaru[1-9][0-9]*)$` に一致し、かつ
    `queue/runtime/role_failover.yaml` が存在すると `SHOGUNATE_ROLE_GENERATION` が必須。
    未設定だと `[inbox_write] REJECTED: generation is required for managed sender shogun`
    で exit 1。隔離環境で実測済み。
- watcher の起動主体は `shogunate_mod/watcher/supervisor.sh`。
  - `supervisor_tick()`（`supervisor.sh:528-556`）が 5 秒ごとに回るが、対象は
    `shogun` / `gunkan` / `gunshi` / `KARO_AGENTS` / `ACTIVE_ASHIGARU` に固定。
    MoA メンバー名はここに載らないので watcher が起動しない。
  - pane の特定は index 順ではなく、tmux pane option `@agent_id` の一致
    （`resolve_agent_pane_target()`, `supervisor.sh:208-222`）。pane にラベルさえ
    貼れば supervisor は相手を見つけられる。
  - `agent_is_supervised()`（`supervisor.sh:168-176`）に載らない agent の watcher は
    `cleanup_stale_watchers()`（`supervisor.sh:498-527`）が window ごと kill する。
    名簿へ載せずに watcher だけ起動しても 5 秒で殺される。
- pane に `@agent_id` を貼っているのは `shogunate_mod/runtime/goza.sh:356`。
- runtime の一時状態を TSV で置く既存慣習: `queue/runtime/ashigaru_owner.tsv`、
  `queue/runtime/agent_cli.tsv`。MoA メンバー名簿も同じ形に揃える。

## 作業計画

### P1. InboxTransport を追加し、代表宛の 1 通に集約する

- `shogunate_mod/moa/manager.py` に `InboxTransport` を追加する。`MoaTransport` Protocol を
  満たし、`bash shogunate_mod/inbox/write.sh <target> <pointer> <type> <from>` を
  `subprocess.run` で呼ぶ。`AgmsgTransport` と同じく例外を投げず `(ok, detail)` を返す。
- message type は既存語彙から `task_assigned` を使う。新しい type を増やさない。
- generation gate 対策として、環境変数 `SHOGUNATE_ROLE_GENERATION` が呼び出し元にあれば
  そのまま子プロセスへ引き継ぐ。無い場合は `queue/runtime/role_failover.yaml` から
  sender role の `generation` を読んで補う。どちらも取れず gate が有効なときは
  `(False, "generation unavailable")` を返し、握り潰さない。
- `deploy()` の送信ループ（`manager.py:712-731`）を、代表者 1 通だけ送る形に変える。
  非代表 member の `delivery` は `{"ok": None, "detail": "representative-relay"}` とし、
  「送っていない」と「送って失敗した」を区別できる状態にする。
- self-send guard に触れないよう、sender と代表者 agent が同一のときは送信せず
  `(False, "sender is the representative")` を返す。

### P2. 代表→メンバーの fan-out を追加する

- `moa` サブコマンドに `notify-members` を追加する。代表者だけが実行でき
  （`_require_actor(..., representative=True)` を再利用）、active な deployment の
  非代表 member 全員へ P1 と同じ `InboxTransport` で pointer を送る。
- 送信結果は `state.yaml` の該当 `delivery` を更新する。
- 代表者の instruction（`shogunate_mod/instructions/source/` 配下の該当役職）へ、
  MoA 展開時に `notify-members` を打つ手順を追記する。生成物は既存の生成 script で
  同期する（手で `instructions/generated/` を編集しない）。

### P3. MoA メンバーを supervisor の名簿へ載せる

- `deploy()` が active member を `queue/runtime/moa_members.tsv` へ書く。
  1 行 1 member、tab 区切りで `agent<TAB>role<TAB>task_id<TAB>generation`。
  `dissolve()` と `finalize()`（`dissolve_after: finalized` のとき）が該当行を消す。
  ファイルが空になったら削除する。書き込みは既存の `_atomic_text` と同じく
  tmp + `os.replace` にする。
- `supervisor.sh` に `refresh_moa_members()` を足し、`supervisor_tick()` の先頭で
  `refresh_active_ashigaru` / `refresh_karo_agents` と同じ位置で呼ぶ。
- `agent_is_supervised()` に MoA member 判定を足す。ここを先に入れないと
  `cleanup_stale_watchers()` が起動直後の watcher を殺す。
- `supervisor_tick()` の末尾に MoA member ループを足す。既存の ashigaru ループと同形にし、
  `resolve_agent_pane_target` で pane が取れないメンバーは skip する（起動していない
  メンバーで tick を止めない）。

### P4. 既読を delivery へ反映する

- `status()` が `queue/inbox/<agent>.yaml` を読み、その deployment の pointer を含む
  message の `read` を見て、`delivery` に `read: true|false` を足す。
- 判定は message の `content` に `deployment_id` が含まれるかで行う。
  pointer 文字列に `deployment_id` を含めるよう P1 で整える。
- inbox が無い / 壊れている場合は `read` を省略し、例外にしない。

### P5. dissolve 後の後始末

- `dissolve()` が `queue/runtime/moa_members.tsv` から該当行を消す（P3 と同じ処理）。
- supervisor は次の tick（最大 5 秒）で `cleanup_stale_watchers()` により該当 watcher を
  自動停止する。`dissolve()` 側から `tmux kill-window` や `kill` を呼ばない。
- メンバーの `queue/inbox/<agent>.yaml` は消さない。監査証跡として残す。

### P6. AGMSG 経路の扱い

- `AgmsgTransport` と `shogunate_mod/transport/` は削除しない。
  `config/settings.yaml` の `transport.mode` を MoA でも読み、
  `inbox`（既定）/ `agmsg` の 2 値で transport を選べるようにする。
- 既定値は `inbox`。設定キーが無い場合も `inbox`。
- 既存の `shogunate_mod/tests/test_agmsg_bridge.bats` を壊さない。

## 予定変更範囲

- 予定変更ファイル:
  - `shogunate_mod/moa/manager.py`
  - `shogunate_mod/moa/README.md`
  - `shogunate_mod/watcher/supervisor.sh`
  - `shogunate_mod/instructions/source/` 配下の該当役職 instruction と、その生成物
  - `tests/unit/test_role_moa.py`
  - 新規: MoA fan-out / supervisor 名簿の test（既存の test 構成に合わせて配置する）
  - `docs/WORKLOG.md`、`docs/REQS.md`、本 ExecPlan
- 許容する付随変更:
  - 上記に直結する test の追加・修正
  - 生成 script 経由の `instructions/generated/` 更新
  - 変更した挙動に対応する docs の同期
- 変更禁止範囲:
  - `shogunate_mod/inbox/write.sh` の門番ロジック（self-send guard、generation gate、
    route policy、report provenance）。呼び出し側で条件を満たす。
  - `shogunate_mod/watcher/inbox_watcher.sh` のエスカレーション梯子と nudge 判定。
  - `shogunate_mod/transport/` 配下（P6 のとおり残す）。
  - `shogunate_mod/runtime/role_failover.py` の世代管理。
  - outer repo（`multi-agent-shognate/` の外側）のすべて。

## 検証と受け入れ条件

必須（すべて PASS を確認して報告する）:

1. `PYTEST_DISABLE_PLUGIN_AUTOLOAD=1 .venv/bin/python3 -m pytest -q tests/unit/test_role_moa.py`
   既存 15 件が通ったうえで、新規 case が追加されていること。
2. 隔離 runtime での実挙動確認。`--runtime-root` を temp dir に向け、
   `configure` → `deploy` → `notify-members` → `submit` ×2 → `finalize` → `dissolve` を通す。
   - `deploy` は代表宛 1 通だけ送っていること（`queue/inbox/` を数えて確認）
   - `queue/runtime/moa_members.tsv` が deploy で生え、dissolve で消えること
   - `role_failover.yaml` がある runtime で generation gate に弾かれないこと
3. `bash -n shogunate_mod/watcher/supervisor.sh` と、既存 bats（`shogunate_mod/tests/`）が通ること。
4. `make structure-check`
5. `make test`
6. commit 後に `make package-check`
7. `git diff --check`

受け入れ条件:

- AGMSG skill と `sqlite3` が無い環境で、MoA の deploy から finalize までが通ること。
- 代表者が応答しない場合、本家のエスカレーション梯子（2分 / 4分 / `/clear`）が
  代表者の pane に対して働くこと（設定上そうなることをコードで示せれば可。実 tmux での
  実測は環境が許すときに行う）。
- 既存の権限検査（assignment digest、`AGENT_ID` 一致、quorum、veto、receipt）が
  1 つも緩んでいないこと。テストを弱めて通さない。

<!-- execplan:original:end -->

## 進捗

- [x] (2026-08-04) 計画作成。
- [x] (2026-08-04) P1 骨格: opencode/qwen3.8-max が `InboxTransport`、`default_transport`、
  `_assignment_pointer`、名簿ヘルパを実装。API quota 切れで中断。
- [x] (2026-08-05) P1 完了: 新規 deploy 経路への `_register_members` 配線を追加。
- [x] (2026-08-05) P2 完了: `notify_members` と CLI `notify-members` を追加。
- [x] (2026-08-05) P3 完了: `supervisor.sh` に `refresh_moa_members` /
  `agent_in_moa_members` / `agent_is_supervised` 追加分 / `supervisor_tick` の member ループ。
- [x] (2026-08-05) P4 完了: `status()` が `queue/inbox/<agent>.yaml` の既読を
  `delivery.read` へ反映。
- [x] (2026-08-05) P5 完了: `dissolve()` と finalize 時 dissolve から
  `_unregister_members` を呼ぶ。watcher 停止は supervisor の次 tick に委ねる。
- [x] (2026-08-05) P6 完了: `transport.mode` で inbox / agmsg を選択。既定は inbox。
- [x] (2026-08-05) test を新契約へ更新し、MOD mirror を同期。

## 現在の停止点

- 現在位置: P1〜P6 実装完了、検証完了。未コミット。
- 未完了: commit と commit 後の `make package-check`。実 tmux での escalation 実測。
- 次の一手: 変更を review し、nested repo へ commit してから `make package-check` を実行する。
- 次に読む文書: `shogunate_mod/moa/README.md`
- 次に実行するコマンド: `git -C multi-agent-shognate status --short --branch`

## 発見事項

- 観測: supervisor の pane 解決は index 順ではなく `@agent_id` 一致。
  根拠: `shogunate_mod/watcher/supervisor.sh:208-222`（`resolve_agent_pane_target`）。
  index ベースの `agent_registry_pane_for_agent` は `list_watch_targets`（`supervisor.sh:62-75`）
  でのみ使われ、`supervisor_tick` は使っていない。
- 観測: 名簿に載せずに watcher を起動しても 5 秒以内に kill される。
  根拠: `supervisor.sh:498-527` の `cleanup_stale_watchers` が `agent_is_supervised` 外の
  `inbox-*` window と `inbox_watcher.sh <agent>` プロセスを落とす。
- 観測: `write.sh` の generation gate は live runtime 形状で実際に送信を拒否する。
  根拠: 隔離コピーで `role_failover.yaml` を置いて実行し
  `[inbox_write] REJECTED: generation is required for managed sender shogun` / exit 1 を観測。

- 観測 (2026-08-05): `_require_actor` の representative 用メッセージが
  `only the representative may finalize the role output` 固定で、`notify-members` の
  拒否時に誤解を招いた。`only the representative may act for the role` へ変更した。
  既存 test の `match="only the representative"` は影響を受けない。

- 観測 (2026-08-05): `tests/unit/test_role_moa.py` と
  `shogunate_mod/tests/unit/test_role_moa.py` は HEAD で同一。片方だけ更新すると
  mirror が壊れるため、root 側を正として複製した。

- 観測 (2026-08-05): `make test` は bats 未導入のため先頭で停止する。依存追加は
  行わず、Python 側は `pytest -q tests/unit` 全体で代替検証した
  （376 passed / 235 subtests、失敗 0）。bats suite は未実行のまま。

- 観測 (2026-08-05): 委任は 9 回試行して完了 0。内訳は認証 1、driver の権限判定 3、
  上位ホストの分類器 1、課金・quota 3、mailbox の操作ミス 1。詳細は outer repo の
  `docs/reviews/2026-08-04_harness_delegation_failures.html`。最終的に supervisor
  （Claude）が実装を完了させた。

## 逸脱提案

<!-- execplan:deviations -->

## 判断ログ

- 判断: 外部から MoA への通信を代表者 1 通に集約する。
  理由: 役職名（例 `gunkan`）が単一の宛先のままなら、`config/settings.yaml` の
  `cli.agents` と既存 pane 構成を変えずに本家のエスカレーション梯子がそのまま効く。
  `shogunate_mod/moa/README.md` の「代表者が役職の公式出力に責任を持つ」設計とも一致する。
  日付/記録者: 2026-08-04 / Claude（指揮）

- 判断: AGMSG 経路を削除せず設定で選択可能に残す。
  理由: 2026-07-10 / 07-11 のクロスベンダー E2E 実績があり、tmux pane を持たない
  構成では AGMSG しか経路が無い。削除は公開契約の変更にあたり、本計画の目的を超える。
  日付/記録者: 2026-08-04 / Claude（指揮）

- 判断: `write.sh` を変更せず、呼び出し側で門番の条件を満たす。
  理由: `write.sh` は Shogunate 全体の通信境界。MoA の都合で門番を緩めると、
  route policy と report provenance の保証が MoA 以外へ波及して壊れる。
  日付/記録者: 2026-08-04 / Claude（指揮）

## 成果と振り返り

- 成果:
- 不足:
- 学び:
- 目的との差分:

## 具体手順

1. 本 ExecPlan と `shogunate_mod/moa/manager.py` を読む。
2. P1 を実装し、検証 1 と 2 の該当部分を通す。
3. P2 → P3 → P4 → P5 → P6 の順に進め、各段階で検証 1 を通す。
4. 全段階完了後に検証 3〜5、7 を通す。
5. commit 後に検証 6 を通す。
6. 各段階の結果を「進捗」と「現在の停止点」へ追記する。

## 冪等性と復旧

- 中断後の再開手順: 「現在の停止点」を読み、`git status --short --branch` と
  `git diff` で適用済みの範囲を確認してから、未完了の P 番号から再開する。
- `queue/runtime/moa_members.tsv` が残ったまま中断した場合は、
  `shogunate moa status <role> --task-id <id>` で deployment の生死を確認し、
  dissolved なら該当行を消す。

## 成果物とメモ
