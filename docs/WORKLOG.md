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

## 2026-02-11 (WSL再起動後ワンショット起動)
- 要求: WSL再起動後に、1コマンドで起動し、区切られた画面で各エージェントへ接続できるようにする。
- 実装:
  - `scripts/start_command_room.sh` を追加。
  - 起動フロー:
    - `shutsujin_departure.sh` を呼び出して zellij バックエンド起動（`-s`/追加引数の透過対応）。
    - `tmux` セッション `command-room` を作成し、分割ペインを並べる。
    - 各ペインで `zellij attach shogun|karo|active_ashigaru...` を実行。
  - `--view-only`（バックエンド再起動せずビューのみ）と `--session`（ビュー名変更）を実装。
  - `.gitignore` に `!scripts/start_command_room.sh` を追加し追跡対象化。
- 検証:
  - `bash -n scripts/start_command_room.sh` → PASS
  - `bash scripts/start_command_room.sh --help` → PASS
- 注意:
  - このCodex実行環境では snap 制約により実zellij attach のE2Eは不可。ユーザー実機での確認が最終。

## 2026-02-11 (samurai naming + pane color)
- 要求: 起動スクリプト名を侍らしい名称へ変更し、Shogunペインを紫・その他を藍色にする。
- 実装:
  - `scripts/start_command_room.sh` を `scripts/samurai_dojo.sh` へ改名。
  - `scripts/samurai_dojo.sh` に `--no-attach` オプションを追加（検証用）。
  - tmux pane border/title の色付けを追加:
    - shogun: `colour141`（紫）
    - その他: `colour63`（藍色）
  - `.gitignore` の許可リストを `!scripts/samurai_dojo.sh` へ更新。
  - `docs/REQS.md` のコマンド例を新スクリプト名へ更新。
- 検証:
  - `bash -n scripts/samurai_dojo.sh` → PASS
  - `bash scripts/samurai_dojo.sh --help` → PASS
  - mock zellij + tmux で `--no-attach` 実行し、tmux session/pane作成と pane-border-format 色指定を確認。

## 2026-02-11 (onari room naming + role color split)
- 要求: 「道場」命名を避け、上様来訪を意識した部屋名へ変更。加えて色分けを将軍/家老/足軽で分離。
- 実装:
  - スクリプトを `scripts/onari_no_ma.sh` へ改名（御成の間イメージ）。
  - default tmux session 名を `onari-no-ma` に変更。
  - ペイン見出し色を3段階に変更:
    - `shogun`: `colour141`（紫）
    - `karo`: `colour19`（紺）
    - `ashigaru*`: `colour130`（茶）
  - `.gitignore` 許可リストを `!scripts/onari_no_ma.sh` に更新。
  - `docs/REQS.md` の起動コマンド名と受け入れ条件を更新。
- 検証:
  - `bash -n scripts/onari_no_ma.sh` → PASS
  - `bash scripts/onari_no_ma.sh --help` → PASS
  - mock zellij + tmux で `-s --no-attach` 実行し、`pane-border-format` の色分岐と4ペイン生成を確認。

## 2026-02-11 (goza naming update)
- 要求: 部屋名を `御座の間`（goza）へ再変更する。
- 実装:
  - スクリプトを `scripts/goza_no_ma.sh` へ改名。
  - 既定tmux session名を `goza-no-ma` に変更。
  - `.gitignore` 許可リストを `!scripts/goza_no_ma.sh` に更新。
  - `docs/REQS.md` のコマンド例を `goza_no_ma.sh` に更新。
- 検証:
  - `bash -n scripts/goza_no_ma.sh` → PASS
  - `bash scripts/goza_no_ma.sh --help` → PASS
  - mock zellij + tmux で `bash scripts/goza_no_ma.sh -s --no-attach --session <tmp>` 実行し、4ペイン生成と色分岐維持を確認。

## 2026-02-11 (pane text color fix)
- 要求: ペイン本文の文字色は通常のままにし、タブ（見出し）色のみ変更したい。
- 実装:
  - `scripts/goza_no_ma.sh` の `tmux select-pane -P "fg=..."` を削除。
  - 色指定は `pane-border-format`（見出し）だけに限定。
- 検証:
  - `bash -n scripts/goza_no_ma.sh` → PASS
  - `rg -n \"select-pane -t .* -P\" scripts/goza_no_ma.sh` → 0件
  - mock zellij + tmux で `bash scripts/goza_no_ma.sh -s --no-attach --session <tmp>` 実行し、`pane-border-format` の色分岐が維持されることを確認。

## 2026-02-11 (tab color not reflected on existing session fix)
- 事象: 「タブカラーが変わっていない」報告。既存 tmux セッション再利用時に新スタイル再適用が走らないケースを確認。
- 実装:
  - `scripts/goza_no_ma.sh` の既存セッション分岐（`tmux has-session`）でも `pane-border-status` と `pane-border-format` を毎回再適用。
  - 視認性向上のため見出し色を背景色ベースに変更（将軍=紫背景、家老=紺背景、足軽=茶背景）。
- 検証:
  - mock zellij + tmux で
    - 1回目: `bash scripts/goza_no_ma.sh -s --no-attach --session <s>`
    - 2回目: `bash scripts/goza_no_ma.sh --view-only --no-attach --session <s>`
  - 2回目ログで既存セッション分岐を確認し、`tmux show-options -w` で `pane-border-format` 再適用を確認。
  - `pane-style` 未設定（本文色に影響なし）を確認。

## 2026-02-11 (dual mux mode commands)
- 要求: zellij/tmux それぞれで専用コマンドを実行すれば、そのモードで起動するようにする。
- 実装:
  - `scripts/goza_no_ma.sh` に `--mux zellij|tmux` を追加。
  - `shutsujin_departure.sh` に `MAS_MULTIPLEXER` 環境変数オーバーライドを追加（`tmux|zellij`）。
  - `scripts/goza_zellij.sh` を追加（`goza_no_ma --mux zellij` ラッパー）。
  - `scripts/goza_tmux.sh` を追加（`goza_no_ma --mux tmux` ラッパー）。
  - `.gitignore` に新規スクリプト許可を追加。
- 検証:
  - `bash -n shutsujin_departure.sh scripts/goza_no_ma.sh scripts/goza_zellij.sh scripts/goza_tmux.sh` → PASS
  - `bash scripts/goza_no_ma.sh --help` → `--mux` 表示を確認
  - `bash scripts/goza_zellij.sh --help` / `bash scripts/goza_tmux.sh --help` → ヘルプ到達確認
  - `bats tests/unit/test_cli_adapter.bats tests/unit/test_send_wakeup.bats --timing` → PASS
  - tmux実起動検証（`TERM=xterm bash scripts/goza_tmux.sh -s --no-attach`）で `goza_tmux` の案内文確認。

## 2026-02-11 (README rewrite for new tools)
- 要求: ルート `README.md` を新ツールの説明中心に書き換える。
- 実装:
  - `README.md` を全面更新。
  - `goza_zellij.sh` / `goza_tmux.sh` / `goza_no_ma.sh --mux` を先頭で案内する構成に変更。
  - 役割別タブ色（将軍/家老/足軽）と「本文色は変えない」方針を記載。
  - 設定例、トラブルシュート、開発者向け補足を追加。
- 検証:
  - `sed -n '1,120p' README.md` で新構成を確認。
  - `rg -n \"goza_zellij|goza_tmux|--mux\" README.md` で新コマンド記載を確認。

## 2026-02-11 (README operation addendum)
- 要求: READMEに混在CLI運用（Codex/Gemini/LocalAPI）とWSL再起動後の最短手順を追記し、起動時の操作ミスを減らす。
- 実装:
  - `README.md` に「CLI割り当て例（Codex / Gemini / LocalAPI）」セクションを追加。
  - `localapi` 用の環境変数（`LOCALAPI_BASE_URL` / `LOCALAPI_API_KEY` / `LOCALAPI_MODEL`）を明記。
  - `README.md` に「WSL再起動後の最短手順」を追加し、`zellij list-sessions -n` をそのまま実行する案内を記載。
  - `docs/REQS.md` に上記追補要求と受け入れ条件を追加。
- 検証:
  - `rg -n "localapi|LOCALAPI_BASE_URL|LOCALAPI_MODEL" README.md` → 期待文字列を確認。
  - `rg -n "WSL再起動後の最短手順|zellij list-sessions -n" README.md` → 期待文字列を確認。
