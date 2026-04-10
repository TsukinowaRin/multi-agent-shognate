# Handoff 2026-04-10 — runtime resume (main repo)

最終更新: 2026-04-10 (JST)

このドキュメントは、**新しいエージェントが記憶ゼロから再開できること**を目的にまとめた最新 handoff。
`docs/INDEX.md` の Must-read を読み終えたら、まず本書を読む。

## 1) いまの結論（業務利用判定）

- **軽い共同開発タスク（複数足軽で分担）なら業務利用可**。
- 条件: 将軍に 1 回だけ指示し、家老が初手で複数足軽へ割り振り、`cmd_done` まで返ることを確認済み。
- ただし **重い/長時間/連続タスクの安定性は未検証**。外部 quota で止まるリスクは残る。

## 2) リポジトリとブランチ

- repo root: `/mnt/d/git_workspace/multi-agent-shognate/multi-agent-shognate`
- 作業ブランチ: `codex/upstream-sync-2026-03-29`
- 最新コミット: `3de0a69` `codex: 家老の初手分担を複数足軽前提に補強`

## 3) 直近で入れた重要変更

### 家老の初手分担を強制

目的: 家老が「自然に並列化できる task なのに 1 人だけに振る」問題を止める。

変更点:
- `instructions/roles/karo_role.md`
  - **Multi-Ashigaru Initial Split Rule** を追加。
  - 「2 人以上の足軽が空いていて、自然に並列化できる場合は初手で複数足軽へ切る」を明文化。
- `shutsujin_departure.sh`
  - 家老の初動 directive に同じルールを反映。
- `instructions/generated/*karo*.md`
  - 生成物を再生成。
- `tests/unit/test_build_system.bats` / `tests/unit/test_mux_parity.bats`
  - 文面回帰を追加。

## 4) 実運用テストの結果（multi-ashigaru）

### テスト内容（将軍への 1 回指示）

タスク名: `burnin_probe_seven`
要件:
- `runtime_sandboxes/burnin_probe_seven/` に CLI を作成
- 入力: `id,status` の CSV
- 出力: Markdown summary
- 生成物: `app.py`, `README.md`, `tests/test_app.py`
- 検証コマンド:
  - `python3 -m unittest runtime_sandboxes/burnin_probe_seven/tests/test_app.py`

### 観測結果

以下を確認済み:
- 将軍が 1 回だけ指示を受けて `cmd` を起票。
- 家老が初手で 2 人の足軽へ分担:
  - `ashigaru1`: `app.py`
  - `ashigaru2`: `README.md` + `tests/test_app.py`
- 両方の `report` が `status: done`。
- 家老が再検証後に close。
- 将軍 inbox に `cmd_done` が返り、既読化。
- `python3 -m unittest runtime_sandboxes/burnin_probe_seven/tests/test_app.py` が PASS。

主要ファイル:
- `runtime_sandboxes/burnin_probe_seven/app.py`
- `runtime_sandboxes/burnin_probe_seven/README.md`
- `runtime_sandboxes/burnin_probe_seven/tests/test_app.py`
- `queue/reports/ashigaru1_report.yaml`
- `queue/reports/ashigaru2_report.yaml`
- `queue/inbox/shogun.yaml` (cmd_done)
- `dashboard.md` (完了表示)

## 5) 直近の実行コマンド

### 生成物更新
- `bash scripts/build_instructions.sh`
- `bats tests/unit/test_build_system.bats tests/unit/test_mux_parity.bats`

### 実運用テスト
- `bash shutsujin_departure.sh -c`
- `bash scripts/inbox_write.sh shogun "<burnin_probe_seven task>" task_assigned user`
- `python3 -m unittest runtime_sandboxes/burnin_probe_seven/tests/test_app.py`

## 6) いまの runtime 状態

次が確認済み（完走後の正常状態）:
- `queue/shogun_to_karo.yaml` → `commands: []`
- `queue/inbox/shogun.yaml` → `cmd_done` 既読化
- `queue/inbox/karo.yaml` → `cmd_new` / `report_received` 既読化
- `dashboard.md` → `burnin_probe_seven` 完了

## 7) 既知リスク / 未完了

- 長時間連続運転の安定性は未検証。
- 外部 quota による停止は起こり得る。
- `git status` は重く、全体の clean 状態は未確認。
  - このため **作業再開時に `git status` を短時間で確認すること**。

## 8) 再開手順（最短）

1. runtime 再起動
```
bash shutsujin_departure.sh -c
```

2. 将軍に 1 回だけ task を投げて、multi-ashigaru 分担を確認
```
bash scripts/inbox_write.sh shogun "<task>" task_assigned user
```

3. 完走確認ポイント
- `queue/shogun_to_karo.yaml` が空
- `queue/reports/ashigaru*_report.yaml` が `done`
- `queue/inbox/shogun.yaml` に `cmd_done`
- `dashboard.md` の完了表示

## 9) 次にやるべきこと（候補）

1. 「軽いタスク 2 本連続」までの再現性を確認する。
2. quota による停止が出たら `runtime_blocked` relay が将軍・人間の双方へ届くか確認する。

