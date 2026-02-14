# ExecPlan: tmux / zellij 起動挙動の同一化

## Context
- ユーザー要件として「tmuxでもzellijでも同じ動作」が明示された。
- 実際には `queue/inbox` の初期化方針が起動モードごとに異なり、環境によって壊れた状態（ファイル化）を引き起こすことがあった。
- その結果、`git add` 失敗や watcher 起動不整合が発生していた。

## Scope
- `queue/inbox` を両モードで「常にローカルディレクトリ化」する。
- 起動系スクリプトと watcher/inbox_write で同一の正規化処理を利用。
- 回帰テスト（inbox_write + mux parity）を追加する。

## Acceptance Criteria
1. `tmux/zellij` の setup-only 起動後に `queue/inbox` が必ずディレクトリ。
2. `queue/inbox` がファイルでも、`inbox_write` 実行で自動復旧。
3. `bats tests/unit/test_mux_parity.bats tests/test_inbox_write.bats tests/unit/test_send_wakeup.bats` がPASS。

## Work Breakdown
1. `lib/inbox_path.sh` を追加し、inbox正規化ロジックを実装。
2. `shutsujin_departure.sh` / `scripts/shutsujin_zellij.sh` / `scripts/goza_no_ma.sh` / `scripts/watcher_supervisor.sh` に組み込み。
3. `scripts/inbox_write.sh` の親ディレクトリ自己復旧を追加。
4. テスト追加・ドキュメント更新。

## Progress
- 2026-02-14: `lib/inbox_path.sh` を追加。
- 2026-02-14: tmux/zellij/goza/watcher 起動で inbox 正規化ヘルパーを共通利用に変更。
- 2026-02-14: `inbox_write` に `queue/inbox` ファイル化時の自動復旧を追加。
- 2026-02-14: `tests/unit/test_mux_parity.bats` と `tests/test_inbox_write.bats`（T-016）を追加。

## Surprises & Discoveries
- DrvFS環境では symlink の扱い差で `queue/inbox` が通常ファイル化されうるため、`mkdir -p` 前提が壊れやすい。

## Decision Log
- D1: inbox はVCS対象ではなくランタイム領域として扱い、ローカルディレクトリを正規形にする。
- D2: 修復処理は起動時だけでなく `inbox_write` 実行時にも入れ、自己回復性を高める。

## Outcomes & Retrospective
- 起動モード差に依存しない inbox 準備ができるようになり、運用上の再現性が上がった。
- 今後は `queue/` 配下の他ランタイムファイルについても同様の正規化ルールを適用可能。
