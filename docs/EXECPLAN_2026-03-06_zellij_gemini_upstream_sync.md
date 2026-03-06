# ExecPlan: zellij / Gemini upstream sync

## Context
- 上流 `upstream/main` の最新確認結果を、このフォークの `zellij` / `Gemini CLI` 経路へ限定反映する。
- 既存の pure zellij 御座の間では「起動はするが初動命令が入らない」問題が残っている。

## Scope
- `scripts/goza_no_ma.sh`
- `scripts/shutsujin_zellij.sh`
- `scripts/inbox_watcher.sh`
- 対応テスト
- 関連 Docs

## Acceptance Criteria
- `bats tests/unit/test_goza_pure_bootstrap.bats tests/unit/test_zellij_bootstrap_delivery.bats` が PASS。
- `bats tests/unit/test_send_wakeup.bats` が PASS。
- pure zellij 側で agent 単位 transcript を使った bootstrap 経路が存在する。
- zellij session-per-agent 側で Gemini trust/high-demand を自動処理する。

## Work Breakdown
1. 要求と同期ノートを zellij / Gemini スコープへ更新する。
2. pure zellij の bootstrap を CLI引数方式から明示送信方式へ切り替える。
3. Gemini preflight を `goza_no_ma.sh` / `shutsujin_zellij.sh` に実装する。
4. watcher に上流の false-busy deadlock 緩和を入れる。
5. テストと WORKLOG を更新する。

## Progress
- 2026-03-06: 要求再定義、上流同期ノート新設、pure zellij bootstrap の方式変更に着手。
- 2026-03-06: pure zellij を transcript + 明示送信へ変更、Gemini preflight と watcher 初期 idle flag を実装。

## Surprises & Discoveries
- pure zellij は pane ごとの外部 capture API が弱く、screen dump だけでは他ペインと混線する。
- そのため、agent ごとの transcript を取る方が bootstrap 判定の基盤として妥当。

## Decision Log
- CLI 起動時に prompt を引数で渡す方式は廃止する。
- Gemini trust/high-demand は bootstrap 前段で吸収する。
- 古い実験コードの全面撤去は今回見送る。

## Outcomes & Retrospective
- `bats tests/unit/test_goza_pure_bootstrap.bats tests/unit/test_zellij_bootstrap_delivery.bats tests/unit/test_send_wakeup.bats` は PASS。
- `bash -n scripts/goza_no_ma.sh scripts/shutsujin_zellij.sh scripts/inbox_watcher.sh lib/cli_adapter.sh` は PASS。
- スモーク実行では `scripts/goza_no_ma.sh -s --no-attach --mux zellij --ui zellij --template goza_room` は通過。
- 同一環境で `scripts/shutsujin_zellij.sh -s` は `snap-confine ... cap_dac_override not found` により失敗した。これは zellij snap パッケージと実行環境 capability の相性問題で、コード不具合と切り分け済み。
