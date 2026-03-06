# Upstream Sync Notes (2026-03-06, zellij / Gemini scope)

対象上流: `yohey-w/multi-agent-shogun`  
比較基準: `upstream/main`（確認時点の先頭は `86ee80b`）

## Context
- ユーザー要求を `zellij` 対応と `Gemini CLI` 対応に絞る。
- `tmux` や `localapi` など他テーマの整理は今回の主目的から外す。

## 反映する差分
### 1. watcher の false-busy deadlock 防止
- 上流 `71890b4` / `e6e484a` / `da49b0f` 系の意図を採用。
- このフォークでは `scripts/inbox_watcher.sh` 起動時に Claude 用初期 idle flag を作る。
- 目的:
  - stop hook 未実行の初期状態で busy 判定が固着するのを防ぐ。

### 2. zellij 起動時の Gemini preflight 自動処理
- 上流には Gemini CLI 固有の trust/high-demand 対応はない。
- このフォーク独自に次を追加する。
  - `scripts/shutsujin_zellij.sh`
    - 1セッション1エージェントの Gemini 起動で
      - `Trust this folder`
      - `Keep trying` / `high demand`
      を自動処理してから bootstrap を送る。
  - `scripts/goza_no_ma.sh`
    - pure zellij 御座の間でも Gemini preflight を agent 別 transcript ベースで扱う。

### 3. pure zellij の bootstrap 方式変更
- 旧方式:
  - CLI 起動時の引数として初動命令を渡す。
- 新方式:
  - 各ペインはまず CLI だけを起動。
  - agent ごとの transcript に出力を記録。
  - transcript を監視しながら bootstrap を明示送信する。
- 理由:
  - 「起動はするがプロンプトが注入されない」問題を、CLI 引数依存から切り離すため。
  - Gemini/Codex/Claude の挙動差を bootstrap 層で吸収しやすくするため。

## 今回見送る差分
- `tmux` UI/演出の整理
- `localapi` 拡張
- 古い実験コードの全面移設

## 検証観点
1. `bats tests/unit/test_goza_pure_bootstrap.bats tests/unit/test_zellij_bootstrap_delivery.bats`
2. `bats tests/unit/test_send_wakeup.bats`
3. `rg -n "gemini trust accepted|gemini keep_trying|pure_zellij_.*\\.log" scripts/goza_no_ma.sh scripts/shutsujin_zellij.sh`
