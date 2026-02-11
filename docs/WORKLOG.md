# Worklog

## 2026-02-10
- docs基盤ファイル（INDEX/DOCS_POLICY/PLANS/REQS/EXECPLAN）を新規作成。
- 次工程として、CLI adapterへのgemini/localapi追加とzellij起動導線の実装に着手。

## 2026-02-10 (checkpoint)
- 実装:
  - `lib/cli_adapter.sh` に `gemini` / `localapi` 対応を追加（type判定、コマンド生成、instruction path、可用性検証、モデル既定値）。
  - `scripts/localapi_repl.py` を追加（OpenAI互換ローカルAPI REPL、`:model` 切替対応）。
  - `scripts/inbox_watcher.sh` を `MUX_TYPE` 分岐化し、tmux/zellij送信経路を追加。`gemini`/`localapi` の `/clear` `/model` 分岐を追加。
  - `scripts/shutsujin_zellij.sh` を新規作成（zellij運用起動）。
  - `shutsujin_departure.sh` に `multiplexer.default=zellij` 時の自動委譲を追加。
  - `scripts/watcher_supervisor.sh` を zellij/tmux 両対応化。
  - `first_setup.sh` の settings.yaml テンプレートを拡張（multiplexer + multi-cli設定）。
  - `scripts/build_instructions.sh` を拡張し、`gemini/localapi` 生成を追加。
  - instructions role/common を更新し、`AGENT_ID`/`DISPLAY_MODE` の zellij fallback を追加。生成ファイル再ビルド済み。
- Docs:
  - `docs/INDEX.md` / `DOCS_POLICY.md` / `PLANS.md` / `REQS.md` / `EXECPLAN_TEMPLATE.md` / `EXECPLAN_2026-02-10_zellij_multi_cli.md` / `ZELLIJ_AND_MULTI_CLI.md` を整備。
- 検証:
  - `bash scripts/build_instructions.sh` → PASS
  - `bash -n lib/cli_adapter.sh scripts/inbox_watcher.sh scripts/watcher_supervisor.sh shutsujin_departure.sh scripts/shutsujin_zellij.sh first_setup.sh scripts/build_instructions.sh` → PASS
  - `python3 -m py_compile scripts/localapi_repl.py` → PASS
  - `bash scripts/shutsujin_zellij.sh -h` → PASS
  - `bash shutsujin_departure.sh -h` → PASS
  - `bats ...` は未実施（環境に `bats` がないため）
- リスク:
  - zellij未導入環境のため、zellij起動E2Eは未検証。
  - 既存ワークツリーに多数の未コミット変更があり、今回変更との切り分けに注意が必要。

## 2026-02-11 (verification)
- テスト実行:
  - `bats tests/unit/test_cli_adapter.bats tests/unit/test_send_wakeup.bats --timing`
  - 結果: 105 tests, 全PASS（SKIPなし）
- zellij検証:
  - このCodex実行環境では `snap` 制約により実 zellij 実行不可（`timeout waiting for snap system profiles`）。
  - 代替としてモックzellijで以下を検証:
    - `scripts/shutsujin_zellij.sh -s` が 10 agent session を作成すること
    - `shutsujin_departure.sh` が `multiplexer.default: zellij` で zellijスクリプトへ委譲すること
- 追記修正:
  - `shutsujin_departure.sh` help文を multiplexer対応に更新
  - `scripts/shutsujin_zellij.sh` の watcher重複起動判定を zellij識別込みに強化

## 2026-02-11 (settings default update)
- 要求: settingsの既定を「足軽1名 + codex」に変更、pushなしcommitのみ。
- 実装:
  - `scripts/shutsujin_zellij.sh` に `topology.active_ashigaru` 読み取りを追加。
  - 未設定時の既定を `ashigaru1` のみに設定。
  - セッション作成/CLI起動/watcher起動/接続ガイドを有効足軽リスト連動に変更。
  - `first_setup.sh` の `config/settings.yaml` 雛形を `multiplexer.default: zellij` + `topology.active_ashigaru: [ashigaru1]` + `cli.default: codex` へ更新。
- 検証:
  - `bash -n scripts/shutsujin_zellij.sh first_setup.sh` PASS
  - `bats tests/unit/test_cli_adapter.bats tests/unit/test_send_wakeup.bats --timing` PASS (105 tests)
  - モックzellijで `bash scripts/shutsujin_zellij.sh -s` 実行し、`shogun/karo/ashigaru1` のみ生成を確認。

## 2026-02-11 (mixed codex+gemini launch checkpoint)
- 要求: `shogun/karo=codex`、`ashigaru1/2=gemini` の混在起動を実行可能にし、起動テストする。
- 実装:
  - `config/settings.yaml` を混在構成へ更新（`topology.active_ashigaru: [ashigaru1, ashigaru2]`）。
  - `lib/cli_adapter.sh` の起動コマンド解決を改善（`kimi`/`gemini` は `*-cli` バイナリを自動フォールバック）。
  - `scripts/shutsujin_zellij.sh` で非アクティブ管理セッションを削除し、現在配備とセッション一覧を一致させる。
  - `tests/unit/test_cli_adapter.bats` に `kimi-cli` / `gemini-cli` フォールバックテストを追加。
- 検証:
  - `bats tests/unit/test_cli_adapter.bats tests/unit/test_send_wakeup.bats --timing` → PASS (107 tests, 既存skip 1)
  - `bash -n lib/cli_adapter.sh scripts/shutsujin_zellij.sh` → PASS
  - `PATH=/tmp/mock-zellij-bin:$PATH bash scripts/shutsujin_zellij.sh -s` → `shogun/karo/ashigaru1/ashigaru2` の4セッションのみ生成を確認
  - `PATH=/tmp/mock-zellij-bin:$PATH bash scripts/shutsujin_zellij.sh` → 起動ログと `queue/runtime/agent_cli.tsv` で `codex/codex/gemini/gemini` を確認
- 注意:
  - Codex実行環境のsnap制約で実zellijコマンドは失敗（`timeout waiting for snap system profiles...`）。ユーザー実機での実zellij確認を前提。
