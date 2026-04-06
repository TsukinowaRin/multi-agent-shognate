# Handoff: 2026-03-29 Resume

> 注記: この文書は旧 handoff です。最新の正本は `docs/HANDOFF_2026-04-06_runtime_resume.md` を参照してください。

最終更新: 2026-03-30 01:05 JST

## 目的

新しいチャットで `AGENTS.md` と `docs/INDEX.md` を読んだあと、そのまま `Shogunate-test` の実 `codex` 検証へ戻れるようにする。

## 今の主目的

WSL 上の認証済み実 `codex` を使い、`Shogunate` runtime が実タスクを安定して処理できるか確認する。

確認対象:

1. 単発 task が `shogun -> karo -> ashigaru -> karo -> shogun` で完了すること
2. 小規模な共同開発 task でファイル作成・テスト・report 回収まで進むこと
3. 必要なら runtime / watcher / bootstrap の改善を本体 repo に戻すこと

## 現在の作業場所

- main repo:
  - `/mnt/d/Git_WorkSpace/multi-agent-shognate/multi-agent-shognate`
- 検証用 clone:
  - `/mnt/d/Git_WorkSpace/multi-agent-shognate/Shogunate-test`
- branch:
  - `codex/upstream-sync-2026-03-29`

## 最新確認済みコミット

- `2a849a7`
  - 実 `codex` の trust prompt / rate-limit warning / usage-limit prompt 対応
  - 将軍・家老・足軽・軍師の startup fastpath 追加

## 既に直した点

対象ファイル:

- `shutsujin_departure.sh`
- `scripts/inbox_watcher.sh`
- `tests/unit/test_mux_parity.bats`
- `tests/unit/test_send_wakeup.bats`

反映済み挙動:

- `Do you trust the contents of this directory?` を update prompt と誤認しない
- `Approaching rate limits` を自動 dismiss する
- `You've hit your usage limit` で mini への切替を試みる
- 将軍/家老の初動探索を減らし、task 着手までの寄り道を減らす

## 既に確認できている事実

- `Shogunate-test` 上で、実 `codex` による単発 task 1 本の完走は以前に確認済み
- その後の追加試験では `You've hit your usage limit` が hard blocker になり、共同開発 task までは未達だった
- ユーザー申告ではその 5 時間制限は解除済み
- 直前の失敗は repo 由来ではなく、この会話スレッドの `exec_command` 障害だった
- アプリ再起動後、`exec_command` は再び正常化した
- `docs/INDEX.md` からこの handoff へ辿れるため、新しいチャットではこの文書を起点に再開できる

## 重要な非repo要因

- `tmux` socket は `/mnt/d/...` だと `unsafe permissions` になりうる
- 実行時は `TMUX_TMPDIR=/tmp/Shogunate-test` を使う
- `Shogunate-test` には認証済み `codex` state を含む local data が残っている可能性がある
- その state は本体 repo に混ぜない

## 次チャットでの再開手順

1. `AGENTS.md` と `docs/INDEX.md` の Must-read を確認
2. `exec_command` が正常か軽く確認
3. `Shogunate-test` を本体 repo の最新コードへ同期
4. `Shogunate-test` の `queue/` と `logs/` を検証用に初期化
5. `TMUX_TMPDIR=/tmp/Shogunate-test bash shutsujin_departure.sh -c` で runtime 起動
6. pane capture と watcher log で trust / rate-limit / usage-limit prompt の有無を確認
7. 単発 task を 1 本投入して end-to-end を確認
8. 共同開発 task を 1 本投入して、生成物・テスト・report を確認
9. 必要なら本体 repo を修正し、`docs/REQS.md` / `docs/EXECPLAN_2026-03-29_isolated_runtime_validation.md` / `docs/WORKLOG.md` を更新

## 推奨する共同開発 task

場所:

- `/mnt/d/Git_WorkSpace/multi-agent-shognate/Shogunate-test/playground/queue_summary/`

内容:

- `queue/inbox/*.yaml` の unread 件数と `queue/tasks/*.yaml` の status を要約する小さな CLI を標準ライブラリのみで作る

生成物:

- `app.py`
- `README.md`
- `tests/test_app.py`

確認:

- `python3 -m unittest`

## 成功条件

次チャットで最低限ここまで取れれば再開成功。

1. `Shogunate-test` runtime が起動する
2. 単発 task が `cmd_done` まで返る
3. 共同開発 task で新規ファイル作成とテスト実行が完了する
4. blocker があれば repo 起因か external 起因かを切り分けて docs に残す

## 次チャット用の依頼文

```text
AGENTS.mdとDocsを読んで、作業を続行して。docs/HANDOFF_2026-03-29_resume.md を起点に Shogunate-test の実 Codex 検証を再開して。
```

補足:

- もし会話スレッド側の `exec_command` が再び壊れていたら、repo failure と断定せず、新しいチャットを作って同じ依頼文で再開する。
