# ExecPlan: upstream差分同期（2026-02-14）

## Context
- ユーザー要求: 上流 `yohey-w/multi-agent-shogun` を確認し、更新点を分析して本リポジトリへ必要分を反映する。
- 本リポジトリは zellij/tmux 両対応かつ multi-CLI 拡張済みで、上流をそのまま取り込むと既存拡張と衝突する。

## Scope
- 上流直近更新を分析し、「即効性が高く回帰リスクが低い差分」を同期する。
- Docs に「何を採用/非採用にしたか」を明記する。

## Acceptance Criteria
1. 上流更新の要点と採用判断が Docs に記録されている。
2. Codex CLI の `--model` 指定が利用可能になる。
3. `inbox_watcher` の self-watch 判定が誤検知しにくくなる。
4. `bats tests/unit/test_cli_adapter.bats tests/unit/test_send_wakeup.bats` が PASS する。

## Work Breakdown
1. 上流コミットを確認し、同期候補を選定する。
2. `lib/cli_adapter.sh` に Codex `--model` 対応を安全に実装する。
3. `scripts/inbox_watcher.sh` に self-watch 判定改善を実装する。
4. 関連ユニットテストを更新する。
5. Docs（INDEX/REQS/WORKLOG/同期ノート）を更新する。

## Progress
- 2026-02-14: 上流参照用 clone を `_upstream_reference/` に分離配置して調査。
- 2026-02-14: 対象コミットを `7f703f2`, `9d4ca4d`, `f10ee4b` に絞って比較。
- 2026-02-14: Codex `--model`（明示設定のみ）と watcher self-watch改善を実装。
- 2026-02-14: 関連ユニットテストを更新し、`112/112` PASS を確認。

## Surprises & Discoveries
- 上流 `9d4ca4d` をそのまま適用すると、本リポジトリの既定モデル（`opus/sonnet`）が Codex に流れうるため、そのまま移植は不適切。
- `send_wakeup_with_escape` の claude 抑止を入れると既存Escalationテストの前提が変わるため、テストを CLI別期待に直す必要があった。

## Decision Log
- D1: Codex `--model` は「設定で明示された model だけ」付与する。
  - 理由: 既定値由来の不正モデル注入を防ぐため。
- D2: self-watch は `claude` 限定とし、PGID除外で watcher 自身の inotifywait を誤検知しない。
  - 理由: non-Claude での誤スキップを防ぐため。
- D3: 上流の `gunshi` 追加は今回は非採用。
  - 理由: 本リポジトリの多家老/足軽可変トポロジと同時導入すると影響範囲が大きいため。

## Outcomes & Retrospective
- 上流の有効差分を本リポジトリ方針に合わせて取り込み、実運用で問題化しやすい2点（model注入、self-watch誤判定）を低減できた。
- 次段では、上流 watcher 改善群（busy判定精度、context reset再試行）を本リポジトリの zellij 分岐に合わせて段階移植する余地がある。
