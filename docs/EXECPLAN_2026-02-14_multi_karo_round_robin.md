# ExecPlan: 複数家老時の足軽均等割り振り

## Context
- 足軽増員時に家老が複数化されても、担当境界が固定されず報告先がぶれる問題があった。
- `inbox_write` が経路制約を持たず、非担当家老宛や家老同士直接通信を防げていなかった。
- watcher監視対象が単一家老前提のため、`karo1..karoN` 構成で監視漏れが起きる。

## Scope
- `lib/topology_adapter.sh` の均等割り振り関数を起動フローで使用。
- 起動時に `queue/runtime/ashigaru_owner.tsv` を再生成（tmux/zellij）。
- `scripts/inbox_write.sh` に送信経路ポリシーを実装。
- `scripts/watcher_supervisor.sh` を多家老監視へ対応。
- 役職指示書と設定CUIに担当固定ルール/確認導線を反映。
- テスト追加（topology/inbox_write）と既存回帰確認。

## Acceptance Criteria
1. `ashigaru_owner.tsv` が起動時に再生成され、全足軽に owner が1件付与される。
2. 家老別の割り当て人数差は常に最大1以内。
3. `inbox_write` で足軽→非担当家老宛を拒否し、担当宛は通過する。
4. 家老→家老（別家老）を拒否する。
5. `bats tests/unit/test_topology_adapter.bats tests/test_inbox_write.bats` がPASS。

## Work Breakdown
1. 起動時 owner map 再生成の実装確認（tmux/zellij）。
2. 送信経路制約を `inbox_write` に追加。
3. `watcher_supervisor` の監視対象を `KARO_AGENTS + ACTIVE_ASHIGARU` に変更。
4. `instructions/karo.md` / `instructions/ashigaru.md` へ担当固定ルール追記。
5. `configure_agents.sh` に割り振り確認表示を追加。
6. テスト追加/実行、REQS/INDEX/WORKLOG更新。

## Progress
- 2026-02-14: `inbox_write` に「足軽→非担当家老拒否」「家老同士通信拒否」を追加。
- 2026-02-14: `watcher_supervisor` を多家老対応し、`karo1..karoN` の watcher 自動維持を実装。
- 2026-02-14: `configure_agents.sh` に owner map サマリ表示を追加。
- 2026-02-14: `instructions/karo.md` / `instructions/ashigaru.md` に担当固定・非担当禁止を追記。
- 2026-02-14: `tests/unit/test_topology_adapter.bats` を追加し、均等割り振り検証ケースを実装。
- 2026-02-14: `tests/test_inbox_write.bats` に送信経路制約の回帰テストを追加。

## Surprises & Discoveries
- 監視再同期ロジックは `pane_target` 不一致時に古い watcher を残しやすく、複数家老で顕在化しやすかった。
- `queue/inbox` が環境依存の特殊ファイルになるケースがあり、git add 失敗の副作用を誘発していた。

## Decision Log
- D1: 割り振りは「起動時固定」のみを採用し、運用中の動的再配分は対象外とした。
- D2: 送信経路の最終防衛線は `inbox_write` に置き、指示書違反を実行時にブロックする。
- D3: watcher は owner map 直接依存より `topology_resolve_karo_agents` 優先で解決し、設定由来の再現性を優先。

## Outcomes & Retrospective
- 複数家老構成での足軽担当境界が明確化され、誤配送の自動検知/拒否が可能になった。
- 監視対象が多家老・可変足軽構成に追随し、運用時の監視漏れリスクを下げた。
- 残課題は、`karo_gashira` を含む上位統制フローの明確な運用ルールを別ExecPlanで整理すること。
