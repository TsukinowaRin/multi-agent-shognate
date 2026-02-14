# ExecPlan: zellij移植 + Multi-CLI拡張

## Context
- 現行は `tmux` 前提で、CLIは Claude/Codex/Copilot/Kimi を中心に構成。
- 要求は `zellij` への移植と `Gemini CLI` / `ローカルAI API` の運用対応。

## Scope
- `zellij` 用起動導線を追加し、既存 `tmux` を後方互換として維持。
- CLIアダプタへ `gemini` / `localapi` を追加。
- watcherのCLI特殊コマンド処理を拡張。
- 必要最小限のドキュメント更新とテスト追加。

## Acceptance Criteria
- `tests/unit/test_cli_adapter.bats` に `gemini` / `localapi` が含まれPASS。
- `shutsujin_departure.sh` が multiplexer設定で `zellij` 分岐可能。
- `tmux` 既存系の主要テストが退行しない。

## Work Breakdown
1. docs基盤整備（INDEX/REQS/PLANS/ExecPlan/WORKLOG）
2. CLI adapter拡張（gemini/localapi）
3. local API用REPLクライアント追加
4. watcher拡張（新CLI種別・zellij送信経路）
5. zellij起動スクリプト追加 + 起動分岐
6. テスト追加・既存テスト実行

## Progress
- 2026-02-10: docs基盤整備を開始。
- 2026-02-10: `lib/cli_adapter.sh` に `gemini` / `localapi` を追加。
- 2026-02-10: `scripts/localapi_repl.py` を追加（OpenAI互換ローカルAPI REPL）。
- 2026-02-10: `scripts/inbox_watcher.sh` を multiplexer対応（tmux/zellij）に拡張。
- 2026-02-10: `scripts/shutsujin_zellij.sh` を追加（1エージェント=1zellijセッション方式）。
- 2026-02-10: `shutsujin_departure.sh` に multiplexer分岐（`zellij` 自動委譲）を追加。
- 2026-02-10: `scripts/build_instructions.sh` を更新し `gemini/localapi` 指示書を生成可能化。
- 2026-02-10: 関連テストを拡張（cli_adapter/send_wakeup）。
- 2026-02-11: `bats tests/unit/test_cli_adapter.bats tests/unit/test_send_wakeup.bats` 実行、105件全PASSを確認。
- 2026-02-11: zellij実機は本環境snap制約で不可のため、モックzellijで起動導線と委譲動作を検証。
- 2026-02-12: `scripts/goza_no_ma.sh` に `--mux`/`--template` 分岐を実装し、zellij/tmux両テンプレート起動を共通化。
- 2026-02-12: `scripts/configure_agents.sh` を追加し、足軽人数と役職別CLI割当をCUIで編集可能化。
- 2026-02-12: `scripts/shutsujin_zellij.sh` に tmux相当のAAバナーを追加し、足軽人数表示を `active_ashigaru` 連動に変更。
- 2026-02-12: zellij御座の間ビューを `main-pane-width 65%` の将軍優先レイアウトへ変更。

## Surprises & Discoveries
- `docs/` 直下にINDEX系文書が未整備（`philosophy.md` のみ）だった。
- `config/settings.yaml` がリポジトリには含まれず、セットアップ時に生成される設計。
- zellijは外部から任意ペイン指定制御が制限されるため、従来tmuxと同じ「1セッション多ペイン」制御は実装リスクが高い。
- このため zellij モードは「1エージェント=1セッション」に設計変更して制御の決定性を優先。

## Decision Log
- zellij移植は「tmux互換を壊さない分岐追加」で実装し、既存利用者の影響を最小化する。
- local AI APIは OpenAI互換API前提の薄いREPLで対応する。
- watcherの送信実装は `MUX_TYPE` で分岐し、tmux既存経路を保持したままzellij経路を追加。
- 指示書生成は role/common の共通パーツを更新し、CLI追加時の再生成で整合を維持。
- 構成入力はGUI新規実装ではなく、運用依存が少ないBash対話CUI（`configure_agents.sh`）を採用。
- zellij直結画面の色変更は端末テーマ依存が強いため、リポジトリ側は「御座の間ビューの枠色制御」と「zellijタブ名ラベル」で視認性を担保。

## Outcomes & Retrospective
- 実装面では「tmux後方互換を維持しつつzellij導線を追加」できた。
- `gemini` / `localapi` は adapter + watcher + instruction generation まで一通り接続済み。
- 構成変更の実運用導線（CUI設定→起動→人数/CLI反映）がREADMEで追える状態になった。
- 残課題は、ユーザー端末での実機zellijテーマ差分を含むE2E確認（配色は端末設定影響あり）。
