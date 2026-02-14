# Upstream Sync Notes (2026-02-14)

対象上流: `yohey-w/multi-agent-shogun` (`main`)
参照範囲: 直近更新（`2026-02-13`〜`2026-02-14`）

## 主要更新（上流）
1. `7f703f2` `ntfy` 受信先を `karo` から `shogun` に変更。
2. `9d4ca4d` Codex CLI に `--model` 対応を追加。
3. `f10ee4b` `inbox_watcher` の self-watch 判定を改善。
   - 非Claude CLIは self-watch しない前提。
   - watcher 自身の inotifywait を誤検知しない（PGID除外）。

## 本リポジトリでの反映方針
1. `ntfy -> shogun` は既に実装済みのため、差分なし。
2. Codex `--model` は反映する。
   - ただし本リポジトリは `get_agent_model()` の既定値が Claude 系（`opus/sonnet`）を返すため、
     上流と同じ実装をそのまま移植すると Codex へ不正モデルを渡す可能性がある。
   - 対策として「設定で明示された model のみ `--model` 付与」にする。
3. self-watch 判定改善を反映する。
   - `claude` 以外は `agent_has_self_watch=false`。
   - `claude` は inotifywait の PGID を比較し、watcher 自身を除外。

## 今回の反映結果
1. `lib/cli_adapter.sh`
   - `_cli_adapter_get_configured_model` を追加。
   - Codex 起動コマンドで「明示modelのみ `--model` 付与」。
2. `scripts/inbox_watcher.sh`
   - self-watch 判定を上流準拠で強化（claude限定 + PGID除外）。
   - busy時ログを CLI種別で分岐（claudeはStop hook前提）。
   - claude の Phase2 Escape エスカレーションを抑止し、通常nudgeへフォールバック。
3. テスト更新
   - `tests/unit/test_cli_adapter.bats`: codex model指定/auto の挙動を追加。
   - `tests/unit/test_send_wakeup.bats`: non-claude self-watch無効化、claude Escape抑止を追加。

## 非採用（今回は見送り）
1. `gunshi` 役職追加。
2. 上流の tmux 固有運用（本リポジトリは zellij/tmux 両対応のため、直接移植は不適）。
