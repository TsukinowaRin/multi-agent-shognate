# Requirements (Normalized)

最終更新: 2026-02-11
出典: 直近ユーザープロンプト

## 要求
1. 既存の `tmux` 前提のシステムを `zellij` で運用できるようにする。
2. `Claude Code` だけでなく、少なくとも以下で運用可能にする。
- `Codex CLI`
- `Gemini CLI`
- ローカルAI API（ローカル推論サーバ）
3. 作業開始時は `AGENTS.md` と `docs` の index-first 手順に従う。

## 非機能要件
- 既存の `tmux` 運用を即時に破壊しない（後方互換を維持）。
- 既存の mailbox/inbox 運用を維持する。

## 受け入れ条件（観測可能）
1. CLIアダプタ
- コマンド: `bats tests/unit/test_cli_adapter.bats`
- 期待結果: `gemini` と `localapi` のCLI種別・起動コマンド・可用性判定のテストがPASS。

2. zellij起動導線
- コマンド: `bash shutsujin_departure.sh`（`config/settings.yaml` で multiplexer を `zellij` に設定）
- 期待結果: `zellij` モード分岐が動作し、zellij専用起動スクリプトが呼ばれる。

3. 既存tmux互換
- コマンド: `bash shutsujin_departure.sh -s`
- 期待結果: `tmux` 設定時の既存起動フローが従来どおり実行される。

4. inbox watcher互換
- コマンド: `bats tests/unit/test_send_wakeup.bats`
- 期待結果: 既存tmux系テストが退行しない（SKIPなし）。

## 仮定
- `Gemini CLI` 実行コマンドは `gemini`（未導入環境では `gemini-cli` も許容）とする。
- ローカルAI APIは OpenAI互換 `/v1/chat/completions` を想定し、URL/APIキー/モデルは環境変数で指定する。

## 追補（2026-02-11）
### 要求
1. `settings` の既定値は「足軽1名（`ashigaru1`）」とする。
2. 既定CLIは `codex` とする。
3. `push` は行わず、`commit` のみ実施する。

### 受け入れ条件（観測可能）
1. コマンド: `bash scripts/shutsujin_zellij.sh -s`（`topology.active_ashigaru` 未設定）
   - 期待結果: `shogun` / `karo` / `ashigaru1` のみセッション作成される。
2. コマンド: `first_setup.sh` が生成する `config/settings.yaml` 雛形を確認
   - 期待結果: `multiplexer.default: zellij`、`topology.active_ashigaru: [ashigaru1]`、`cli.default: codex` が含まれる。
