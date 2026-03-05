# Upstream Sync Notes (2026-03-05)

対象上流: `yohey-w/multi-agent-shogun`  
比較基準: `upstream/main`（先頭 `86ee80b`）

## 1) 最新コード取得（ワークスペース内）
- `git fetch upstream --prune` で上流最新を取得。
- HTTPS直クローンは端末の `schannel` 認証設定により失敗したため、取得済み参照から worktree を作成。
  - 作成先: `_upstream_reference/upstream_latest_2026-03-05_86ee80b`
  - 参照コミット: `86ee80b`

## 2) Gemini CLI / Zellij へ反映した差分
### 採用: watcher の `/clear` busy保護（上流 `e598f70` の要点）
- `scripts/inbox_watcher.sh`
  - `send_cli_command` に busy guard を追加。
    - Working中の `/clear` は即送らず、次サイクルへ延期。
  - `clear_command` 処理に `clear_sent` を導入。
    - busyで延期した場合は auto-recovery を発火しない。
    - 実際に `/clear`（またはCLI変換後コマンド）を送った場合のみ auto-recovery を投入。

### 採用: zellij 初動注入の可観測性強化
- `scripts/shutsujin_zellij.sh`
  - run-id 単位ログ追加。
    - `queue/runtime/bootstrap_run_<timestamp>_<pid>/delivery.log`
  - `ready:<agent>` ACK確認を追加（`wait_for_ready_ack_zellij`）。
  - ACK未検出時はブートストラップを1回再送し、再判定。
  - ログへ `deliver start` / `bootstrap delivered` / `ready ack detected|missing` を記録。

## 3) テスト反映
- `tests/unit/test_send_wakeup.bats`
  - busy時 `/clear` 延期を確認するケースを追加。
  - busy時 `clear_command` で auto-recovery を生成しないケースを追加。
- `tests/unit/test_zellij_bootstrap_delivery.bats`
  - run-id ログ出力と `ready ACK` 再送フローの静的検証を追加。

## 4) 今回見送ったもの
- `scripts/goza_no_ma.sh` の pure zellij 経路へ ACK/再送を追加する改修。
  - 先に `shutsujin_zellij.sh` 経路で可観測化を確実化し、次段で pure zellij 側へ同等実装を展開する。

## 5) 検証観点
1. `rg -n "clear_sent|deferred to next cycle|wait_for_ready_ack_zellij|BOOTSTRAP_RUN_LOG" scripts/inbox_watcher.sh scripts/shutsujin_zellij.sh`
2. `bats tests/unit/test_send_wakeup.bats tests/unit/test_zellij_bootstrap_delivery.bats`
