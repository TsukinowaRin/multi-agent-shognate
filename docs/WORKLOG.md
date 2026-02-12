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

## 2026-02-12 (zellij演出強化 + tmux CLIフォールバック)
- 要求:
  - zellijモードでもtmux相当の演出を表示したい。
  - zellij直接attach時にも役職判別しやすくしたい（タブ色要望）。
  - tmux起動がclaude未導入だけで停止しないようにしたい。
- 実装:
  - `scripts/shutsujin_zellij.sh` に出陣バナー（tmux版と同系統）を追加。
  - `scripts/shutsujin_zellij.sh` でセッション作成時に `zellij action rename-tab` を実行し、役職ラベルを付与:
    - `🟣 shogun`
    - `🔵 karo`
    - `🟤 ashigaru*`
  - `lib/cli_adapter.sh` に以下のヘルパーを追加:
    - `build_cli_command_with_type`
    - `get_first_available_cli`
    - `resolve_cli_type_for_agent`
  - `shutsujin_departure.sh` のtmux起動で `resolve_cli_type_for_agent` を使うように変更し、未導入CLI時は利用可能CLIへフォールバック。
  - `README.md` に「zellij直接attach時は役職アイコン表示」「Claude未導入時フォールバック」の補足を追記。
- 検証:
  - `bash -n lib/cli_adapter.sh shutsujin_departure.sh scripts/shutsujin_zellij.sh scripts/goza_no_ma.sh scripts/goza_zellij.sh scripts/goza_tmux.sh` → PASS
  - `bats tests/unit/test_cli_adapter.bats tests/unit/test_send_wakeup.bats --timing` → 107 tests PASS

## 2026-02-12 (御座の間: 枠色を階級別に修正)
- 要求:
  - zellij運用時の御座の間ビューで、全枠が黄緑になる問題を解消したい。
  - 将軍/家老/足軽で枠色を分離したい。
  - 見出しに色コード断片が露出する表示崩れを解消したい。
- 実装:
  - `scripts/goza_no_ma.sh` に `role_border_color` / `apply_role_border_styles` を追加。
  - 各ペインタイトル（`shogun`/`karo`/`ashigaru*`）を読み取り、`pane-border-style` と `pane-active-border-style` をペイン単位で設定。
    - `shogun`: `colour54`（紫）
    - `karo`: `colour19`（紺）
    - `ashigaru*`: `colour94`（茶）
  - `pane-border-format` は条件式を廃止し、`#{pane_index}:#{pane_title}` の単純形式に変更。
  - 既存セッション再接続時も `apply_role_border_styles` を再適用。
- 検証:
  - `bash -n scripts/goza_no_ma.sh` → PASS
  - `rg -n "apply_role_border_styles|role_border_color|pane-border-style|pane-active-border-style" scripts/goza_no_ma.sh` → 実装行を確認
  - `rg -n "pane-border-format" scripts/goza_no_ma.sh` → 単純形式のみであることを確認

## 2026-02-12 (tmux: active_ashigaru 構成に追従)
- 要求:
  - tmuxモードでも zellij同様に `topology.active_ashigaru` を反映したい。
  - 起動ペイン数、CLI起動対象、watcher対象、布陣表示を同じ active 構成で揃えたい。
- 実装:
  - `shutsujin_departure.sh` に `ACTIVE_ASHIGARU` 読み取り処理を追加（YAMLの数値/文字列を正規化）。
  - `MULTIAGENT_IDS=("karo" + active_ashigaru)` と `MULTIAGENT_COUNT` を導入。
  - multiagentのペイン生成を固定3x3から動的タイル分割へ変更。
  - 足軽CLI起動ループを固定 `ashigaru1..8` から `ACTIVE_ASHIGARU` ループへ変更。
  - watcher起動も active 足軽のみ対象化し、件数表示を動的化。
  - 布陣図と setup-only の案内表示を動的人数・汎用CLI文言へ更新。
- 検証:
  - `bash -n shutsujin_departure.sh` → PASS
  - `bats tests/unit/test_cli_adapter.bats tests/unit/test_send_wakeup.bats --timing` → 107 tests PASS
  - `TERM=xterm MAS_MULTIPLEXER=tmux bash shutsujin_departure.sh -s` は実行環境のtmuxソケット制約で失敗（`error connecting to /tmp/tmux-1000/default (Operation not permitted)`）。静的検証とユニットテストで回帰なしを確認。

## 2026-02-12 (起動判定のCLI汎用化 + zellij優先)
- 要求:
  - 「Claude Code起動判定」依存を除去し、各エージェントCLIの起動で判定したい。
  - zellijを第一手段、tmuxをサブ手段にしたい。
  - 枠色/背景色の変更責務（リポジトリ側かユーザー環境側か）を明確化したい。
- 実装:
  - `shutsujin_departure.sh` の既定 `MULTIPLEXER_SETTING` を `zellij` に変更。
  - `shutsujin_departure.sh` の待機ログを
    - `Claude Code の起動を待機中...`
    - `将軍の Claude Code 起動確認完了...`
    から、各ペインの `@agent_cli` と `pane_current_command` を照合するCLI汎用判定へ変更。
  - ログ文言を `全エージェントCLIを起動中` に変更。
  - `README.md` に zellij優先方針と「御座の間枠色はリポジトリ側、zellij直接attach画面の配色はユーザー側テーマ設定」の説明を追記。
- 検証:
  - `bash -n shutsujin_departure.sh` → PASS
  - `bats tests/unit/test_cli_adapter.bats tests/unit/test_send_wakeup.bats --timing` → 107 tests PASS
  - `rg -n "エージェントCLIの起動を確認中|pane_current_command|@agent_cli" shutsujin_departure.sh` で汎用判定ロジックを確認。

## 2026-02-12 (tmux/zellij テンプレート導入)
- 要求:
  - tmuxは将軍のみ表示か？という混乱を解消し、tmux/zellijで共通のテンプレート概念で起動したい。
  - Multi Agents Shogunateの既定起動でテンプレートを適用したい。
- 実装:
  - `scripts/goza_no_ma.sh` に `--template shogun_only|goza_room` を追加。
  - 既定テンプレートは `config/settings.yaml` の `startup.template`（未設定時はテンプレートYAMLのdefault、最終fallbackは `shogun_only`）。
  - `tmux + shogun_only`: 将軍セッションへ直接attach。
  - `tmux + goza_room`: `goza-no-ma` ビューで `shogun` と `multiagent` を2分割表示。
  - `zellij + shogun_only`: `zellij attach shogun`。
  - `zellij + goza_room`: 既存の御座の間（activeエージェント俯瞰）を使用。
  - テンプレート定義ファイルを追加:
    - `templates/multiplexer/tmux_templates.yaml`
    - `templates/multiplexer/zellij_templates.yaml`
  - `config/settings.yaml` と `first_setup.sh` の設定雛形に `startup.template: shogun_only` を追加。
  - READMEにテンプレート運用手順を追記。
- 検証:
  - `bash -n scripts/goza_no_ma.sh shutsujin_departure.sh first_setup.sh` → PASS
  - `bash scripts/goza_no_ma.sh --help` で `--template` が表示されることを確認。
  - `ls templates/multiplexer/*.yaml` でテンプレートファイル存在を確認。

## 2026-02-12 (テスト優先設定へ切替)
- 要求:
  - `settings.yaml` はエージェント側で変更し、ユーザーはテスト実行だけしたい。
- 実装:
  - `config/settings.yaml` の `startup.template` を `shogun_only` から `goza_room` に変更。
  - `docs/REQS.md` に上記要求と受け入れ条件を追記。
- 検証:
  - `rg -n "startup:|template: goza_room" config/settings.yaml` で設定変更を確認。

## 2026-02-12 (構成CUI + zellij表示改善の仕上げ)
- 要求:
  - 足軽人数・役職別CLIを簡単に編集できるCUI/GUIを追加したい。
  - 起動時の足軽人数表示を構成に連動させたい。
  - zellij御座の間ビューを均等4分割ではなく将軍優先表示にしたい。
  - zellij起動時にもtmux相当のAA演出を表示したい。
- 実装:
  - `scripts/configure_agents.sh` を追加し、対話形式で以下を更新可能化。
    - `multiplexer.default`
    - `startup.template`
    - `topology.active_ashigaru`
    - `cli.default`
    - `cli.agents.<role>.{type,model}`
  - `scripts/configure_agents.sh` の出力混入バグを修正。
    - `prompt_choice` / `prompt_model` の案内表示を標準エラーへ分離し、`settings.yaml` へのゴミ文字混入を防止。
  - `scripts/goza_no_ma.sh` の zellij `goza_room` レイアウトを将軍優先に変更（`main-pane-width 65%`）。
  - `scripts/goza_no_ma.sh` で分割直後の `pane_id` を使ってタイトル設定するよう改善し、枠色適用の安定性を向上。
  - `scripts/shutsujin_zellij.sh` / `shutsujin_departure.sh` のバナー人数表示を `ACTIVE_ASHIGARU_COUNT` 連動に統一。
  - `scripts/shutsujin_zellij.sh` / `shutsujin_departure.sh` の `clear` を非TTY環境で失敗しないよう修正（`set -e` で即死しないようにした）。
  - `README.md` に `scripts/configure_agents.sh` の使い方と人数連動表示を追記。
  - `docs/REQS.md` に本要求の追補、`docs/INDEX.md` の更新日を追記。
- 検証:
  - `bash -n scripts/configure_agents.sh scripts/goza_no_ma.sh scripts/shutsujin_zellij.sh shutsujin_departure.sh` → PASS
  - `printf ... | bash scripts/configure_agents.sh` → `config/settings.yaml` が正しいYAMLで更新されることを確認
  - `bats tests/unit/test_cli_adapter.bats tests/unit/test_send_wakeup.bats --timing` → 107 tests PASS（1 testは環境依存で skip 表示あり）
  - `bash scripts/shutsujin_zellij.sh -s` → 本環境は snap版zellij制約で実機セッション作成失敗（`snap-confine ... permission denied`）だが、AA表示と人数連動表示は出力確認
  - `bash scripts/goza_no_ma.sh --mux tmux --template goza_room -s --no-attach` → 本環境tmuxソケット制約で失敗（`error connecting to /tmp/tmux-1000/default`）

## 2026-02-12 (zellij goza_room確認 + size missing改善)
- 事象:
  - ユーザー報告: `bash scripts/goza_zellij.sh --template goza_room` 実行時に tmux が起動しているように見える。
  - ユーザー報告: tmux 実行時に終了間際 `size missing` が出る。
- 判断:
  - 現行設計では `zellij + goza_room` は「バックエンド=zellij（各エージェントセッション）」を維持し、俯瞰ビューのみ tmux を使う仕様。
  - この責務をログとREADME/REQSで明示する。
- 実装:
  - `scripts/goza_no_ma.sh`
    - `TMUX_VIEW_WIDTH` / `TMUX_VIEW_HEIGHT`（既定 `200x60`）を追加。
    - ビューセッション作成を `tmux new-session -d -x ... -y ...` に変更し、サイズ未確定時の失敗を抑制。
    - 右分割/縦分割にリトライ付きヘルパーを追加。
      - `tmux_split_right_ratio_run`
      - `tmux_split_right_ratio_pane`
      - `tmux_split_down_pane`
    - zellij goza_room 時に責務を明示するログを追加:
      - `[INFO] zellij + goza_room は tmux ビューで表示します（バックエンドは zellij セッション）。`
  - `README.md`
    - zellij goza_room の表示責務（tmuxビュー使用）を明記。
    - `TMUX_VIEW_WIDTH` / `TMUX_VIEW_HEIGHT` の説明を追加。
    - `size missing` 対処コマンドを追加。
  - `docs/REQS.md`
    - 本修正要求（責務明確化 + size missing対策）と受け入れ条件を追記。
- 検証:
  - `bash -n scripts/goza_no_ma.sh README.md docs/REQS.md` → PASS
  - `rg -n "TMUX_VIEW_WIDTH|TMUX_VIEW_HEIGHT|tmux_new_view_session|tmux_split_right_ratio_run|tmux_split_right_ratio_pane|tmux_split_down_pane|zellij \+ goza_room" scripts/goza_no_ma.sh README.md docs/REQS.md` → 実装行を確認
  - `bash scripts/goza_no_ma.sh --help` → オプション表示を確認
  - 実機起動確認は本実行環境のtmuxソケット権限制約で未実施（`error connecting to /tmp/tmux-1000/default (Operation not permitted)`）

## 2026-02-12 (御座の間タブ色未反映 + zellij CLI未起動感の修正)
- 事象:
  - ユーザー画面で御座の間ビューの枠/タブ色が全体的に緑のまま。
  - zellij各セッションで Codex/Gemini が自動起動していないように見える。
- 原因想定:
  - タイトルが `Zellij (shogun)` のような文字列で、既存の厳密一致判定（`shogun`/`karo`/`ashigaru*`）に一致しないケースがある。
  - zellijの `action write 13` が環境/バージョン差分で Enter として効かないケースがある。
- 実装:
  - `scripts/goza_no_ma.sh`
    - 役職判定を厳密一致から部分一致へ変更（`*shogun*` / `*karo*` / `*ashigaru*`）。
    - `pane-border-format` に役職別の色付きヘッダを直接実装（将軍=紫、家老=紺、足軽=茶）。
    - 枠線自体は中立色に固定し、タブ色で視認性を担保。
  - `scripts/shutsujin_zellij.sh`
    - `send_line` の Enter送信にフォールバック追加:
      - `action write 13` → `action write 10` → `write-chars $'\\n'`
    - ブートストラップ/CLI投入失敗時に警告ログを出すよう変更。
  - `scripts/inbox_watcher.sh`
    - zellijモードの Enter送信を同様のフォールバック方式へ更新。
  - `README.md`
    - タブ色確認コマンド（`pane-border-format`）を追加。
    - CLI未起動時の確認手順（`queue/runtime/agent_cli.tsv` と watcherログ）を追加。
  - `docs/REQS.md`
    - 本修正の追補要件と受け入れ条件を追加。
- 検証:
  - `bash -n scripts/goza_no_ma.sh scripts/shutsujin_zellij.sh scripts/inbox_watcher.sh` → PASS
  - `bats tests/unit/test_send_wakeup.bats --timing` → 36 tests PASS
  - `bats tests/unit/test_cli_adapter.bats --timing` → 71 tests PASS
  - 実機tmux/zellij表示確認は本実行環境制約のため未実施（ユーザーWSLで確認が必要）。

## 2026-02-12 (zellij操作デフォルト + tmux内部運用へ切替)
- 要求:
  - zellijの操作/UIを使いたい。
  - 内部はtmuxで動かし、tmux派ユーザーは従来どおりtmux直接運用できるようにしたい。
- 実装:
  - `scripts/goza_zellij.sh` を `--mux tmux --ui zellij` 呼び出しへ変更（デフォルト導線を「zellij UI + tmux backend」に切替）。
  - `scripts/goza_tmux.sh` を `--mux tmux --ui tmux` 明示呼び出しに変更。
  - `scripts/goza_no_ma.sh` に `--ui zellij|tmux` を追加。
    - `--mux` をバックエンド、`--ui` を表示レイヤーとして分離。
    - `--mux tmux --ui zellij` 時は tmux 側で `shogun/multiagent` または `goza-no-ma` を準備し、zellij UI セッション（`goza-no-ma-ui`）から tmux attach を実行。
  - `scripts/goza_no_ma.sh` に zellij UI セッション作成・コマンド投入ヘルパーを追加。
    - `zellij_create_ui_session`
    - `zellij_send_line`
    - `zellij_ui_attach_tmux_target`
  - `scripts/shutsujin_zellij.sh` / `shutsujin_departure.sh` に `inotifywait` 事前チェックを追加。
    - 未導入時は watcher を起動せず、導入コマンドを明示して継続。
  - `README.md` と `docs/REQS.md` を新運用モデルに合わせて更新。
- 検証:
  - `bash -n scripts/goza_no_ma.sh scripts/goza_zellij.sh scripts/goza_tmux.sh scripts/shutsujin_zellij.sh shutsujin_departure.sh` → PASS
  - `bats tests/unit/test_send_wakeup.bats --timing` → 36 PASS
  - `bats tests/unit/test_cli_adapter.bats --timing` → 71 PASS
  - `bash scripts/goza_no_ma.sh --help` で `--ui` 表示を確認。

## 2026-02-12 (zellijは開くが対話不可問題の修正)
- 事象:
  - ユーザー環境で zellij UI は起動するが、Codex/Gemini と対話できない。
  - 画面が zellij のデフォルトシェル表示のままになり、tmux attach が実行されていない。
- 原因:
  - zellij UI 側で `action write-chars` によるコマンド注入を使っていたため、環境差分で入力注入が不安定だった。
- 実装:
  - `scripts/goza_no_ma.sh`
    - zellij UI 起動を `layout` ベースに変更。
    - `zellij_ui_layout_file` を追加し、タブ起動時に `tmux attach-session -t <target>` を直接実行するKDLを生成。
    - `zellij_ui_attach_tmux_target` で以下の順に起動:
      1) `zellij --new-session-with-layout <layout> -s <ui_session>`
      2) `zellij --layout <layout> -s <ui_session>`
      3) `zellij --layout <layout> attach -c <ui_session>`
    - 既存 UI セッションを毎回再生成して stale 状態を排除。
  - `scripts/shutsujin_zellij.sh` / `shutsujin_departure.sh`
    - `inotifywait` 未導入時は watcher を起動せず、明示警告だけ出して継続。
  - `README.md` / `docs/REQS.md`
    - `inotify-tools` 前提と zellij UI attach 安定化要件を追記。
- 検証:
  - `bash -n scripts/goza_no_ma.sh scripts/goza_zellij.sh scripts/goza_tmux.sh scripts/shutsujin_zellij.sh shutsujin_departure.sh` → PASS
  - `bats tests/unit/test_send_wakeup.bats --timing` → 36 PASS
  - `bats tests/unit/test_cli_adapter.bats --timing` → 71 PASS
  - `rg -n "zellij_ui_layout_file|new-session-with-layout|inotifywait" ...` で実装箇所確認。

## 2026-02-12 (zellij layout KDL parse error 修正)
- 事象:
  - `goza_zellij.sh --template goza_room` 実行時に `Failed to parse Zellij configuration` が発生。
  - 生成KDLの `pane command="bash" { args ... }` が 0.41.2 で受理されなかった。
- 修正:
  - `scripts/goza_no_ma.sh` のレイアウト生成を 0.41系互換の記法へ変更。
    - `pane { command "bash"; args "-lc" "..."; }`
  - 起動コマンド文字列のクォートを簡素化し、KDL文字列内の過剰エスケープを除去。
- 検証:
  - `bash -n scripts/goza_no_ma.sh` → PASS
  - 生成テンプレート断片を `sed` で確認し、`command/args` ノード形式になっていることを確認。

## 2026-02-12 (tmux内部運用での agent_cli.tsv 更新)
- 事象:
  - ユーザー確認で `queue/runtime/agent_cli.tsv` が `shogun/karo/ashigaru1/2 = codex` となっていた。
  - ただしこの時点の `goza_zellij` は `--mux tmux --ui zellij` 運用へ移行済みで、`agent_cli.tsv` が tmux経路で更新されていなかった。
- 修正:
  - `shutsujin_departure.sh` の tmux 起動経路で `queue/runtime/agent_cli.tsv` を毎回初期化・書き込み。
  - 将軍/家老/足軽の各起動時に `printf "<agent>\t<cli_type>"` を追記。
  - 足軽起動ログを個別表示（`ashigaru1（...）` 形式）へ変更。
- 検証:
  - `bash -n shutsujin_departure.sh` → PASS
  - `bats tests/unit/test_cli_adapter.bats --timing` → 71 PASS
  - `rg -n "queue/runtime/agent_cli.tsv|printf .*\\t.*_cli_type" shutsujin_departure.sh` で記録処理を確認。

## 2026-02-12 (即作業開始向けの初動自動化)
- 背景:
  - ユーザー所感: 「CLIが開くだけで、将軍/家老/足軽として即仕事にならない」。
  - 具体的には Gemini の trust プロンプトで足軽が停止し、役割読込も自動化されていなかった。
- 実装:
  - `shutsujin_departure.sh` に以下を追加。
    - `auto_accept_gemini_trust_prompt_tmux`: Gemini pane に `Do you trust this folder` が出たら `1 + Enter` を自動送信。
    - `send_startup_bootstrap_tmux`: 全エージェントへ初動命令を送信（AGENTS.md + CLI別指示書を読ませ、`ready:<agent>` 返答で待機）。
  - 起動シーケンスへ組み込み。
    - CLI起動直後に Gemini trust 自動承認。
    - 続いて全エージェントへ初動命令を投入。
  - 既存の `agent_cli.tsv` 記録と併用し、誰がどのCLIで起動したか追跡可能化。
- 検証:
  - `bash -n shutsujin_departure.sh` → PASS
  - `bats tests/unit/test_cli_adapter.bats --timing` → 71 PASS
  - `rg -n "auto_accept_gemini_trust_prompt_tmux|send_startup_bootstrap_tmux|初動命令を投入" shutsujin_departure.sh` で実装を確認。

## 2026-02-12 (将軍ペインを起動直後アクティブ化 + 操作説明追加)
- 要求:
  - 人間は将軍としか会話しないため、起動直後は将軍ペインをアクティブにしたい。
  - zellij表示時のペイン切替方法が分からないため、操作を明示したい。
- 実装:
  - `scripts/goza_no_ma.sh`
    - `tmux_focus_shogun_for_human` を追加。
    - `goza_room` では `goza-no-ma:overview.0`（将軍）を起動直後に選択。
    - 併せて `goza-no-ma:overview` に `mouse on` を設定（クリック切替を有効化）。
  - `README.md`
    - 「操作方法（zellij表示時）」を追加。
    - 起動直後の将軍アクティブ、`Ctrl+b + 矢印` / `Ctrl+b + o` を記載。
- 検証:
  - `bash -n scripts/goza_no_ma.sh` → PASS
  - `rg -n "tmux_focus_shogun_for_human|overview.0|mouse on" scripts/goza_no_ma.sh` で実装確認。

## 2026-02-12 (役職別正本MD必読 + 最適化MD自動同期)
- 要求:
  - 将軍/家老/足軽で役職ごとの正本MDを必読化したい。
  - 正本変更時に Codex/Gemini/Claude などの最適化MDを自動追従させたい。
- 実装:
  - `lib/cli_adapter.sh`
    - `get_role_instruction_file()` を追加（`instructions/<role>.md` を返す）。
    - `get_instruction_file()` の返却先を `instructions/generated/*` に統一。
      - `claude` → `instructions/generated/<role>.md`
      - `codex|copilot|kimi|gemini|localapi` → `instructions/generated/<cli>-<role>.md`
  - `scripts/ensure_generated_instructions.sh` を新規追加。
    - `instructions/`（generated除外）と `CLAUDE.md` をソースとしてmtime比較。
    - 差分があれば `scripts/build_instructions.sh` を自動実行。
  - `shutsujin_departure.sh`
    - 起動初期に `ensure_generated_instructions` を実行。
    - `send_startup_bootstrap_tmux` を更新し、
      - まず役職共通MD
      - 次にCLI最適化MD（存在時のみ）
      の順で読ませる初動命令に変更。
  - `scripts/shutsujin_zellij.sh`
    - 起動初期に `ensure_generated_instructions` を実行。
    - `send_startup_bootstrap_zellij` を追加し、tmux経路と同じ「正本→最適化」初動命令を送信。
  - `tests/unit/test_cli_adapter.bats`
    - `get_instruction_file` の期待値を `instructions/generated/*` へ更新。
    - `get_role_instruction_file` のユニットテストを追加。
- Docs:
  - `docs/REQS.md` に本要求の追補（受け入れ条件）を追加。
  - `docs/EXECPLAN_2026-02-12_role_instruction_sync.md` を新規追加。
  - `docs/INDEX.md` の Plans に新ExecPlanを登録。
- 検証:
  - `bash -n lib/cli_adapter.sh shutsujin_departure.sh scripts/shutsujin_zellij.sh scripts/ensure_generated_instructions.sh` → PASS
  - `bash scripts/ensure_generated_instructions.sh` → `[INFO] generated instruction files are up to date.`
  - `bats tests/unit/test_cli_adapter.bats tests/unit/test_send_wakeup.bats --timing` → 108 tests PASS（claude未導入環境の既存skip 1件のみ）
- 判断メモ:
  - 役職正本とCLI最適化を分離することで、運用指示の一貫性とCLI差分の追従性を両立。
  - 再生成失敗時は警告継続にし、起動停止リスクを回避した。

## 2026-02-12 (zellij枠名の露出抑止 + 階層連携順序の明示)
- 要求:
  - zellij UI利用時に枠タイトルへ `bash -lc ...` が露出する挙動を改善したい。
  - 将軍→家老→足軽の順序連携を起動初動で明示し、実運用で順番を守らせたい。
  - オリジナルREADME_jaの階層連携に沿った実装へ寄せたい。
- 実装:
  - `scripts/goza_no_ma.sh`
    - `zellij_ui_layout_file` で `startup_cmd` 生成を `tmux_attach_session_cmd` 経由に統一。
    - zellij layout の `pane` に `name="..."` を追加し、UI上の枠名を明示化。
    - `zellij_ui_attach_tmux_target` に `tmux has-session` 事前チェックを追加。
      - attach先が無い場合は明示エラーで停止し、長いコマンド露出のまま待機しない。
  - `shutsujin_departure.sh`
    - `role_linkage_directive` を追加。
    - `send_startup_bootstrap_tmux` の初動命令へ、役職別の連携順序（将軍→家老→足軽）を埋め込み。
      - 将軍: `queue/shogun_to_karo.yaml` + inbox経由で家老へ委譲
      - 家老: `queue/tasks/ashigaruN.yaml` + inboxで足軽起動
      - 足軽: `queue/reports/<agent>_report.yaml` + inboxで家老へ報告
  - `scripts/shutsujin_zellij.sh`
    - 同等の `role_linkage_directive` を追加。
    - `send_startup_bootstrap_zellij` に役職別連携順序を組み込み、tmux経路と挙動統一。
- Docs:
  - `docs/REQS.md` に「zellij表示名の正常化 + 連携順序強制」の追補要件と受け入れ条件を追加。
- 検証:
  - `bash -n scripts/goza_no_ma.sh shutsujin_departure.sh scripts/shutsujin_zellij.sh` → PASS
  - `bats tests/unit/test_send_wakeup.bats --timing` → 36 tests PASS
- 判断メモ:
  - この修正で「attach失敗時に長いコマンドが枠名として残る」症状を抑止。
  - 役職別初動命令に順序ルールを明示し、CLI差分があっても統率フローを維持しやすくした。

## 2026-02-12 (足軽AAの人数連動 + zellij KDLパース失敗修正)
- 要求:
  - 起動時の足軽AAを実際の配備人数に合わせて増減したい。
  - `goza_zellij` 実行時に `Failed to parse Zellij configuration` で起動失敗する問題を直したい。
- 実装:
  - `scripts/goza_no_ma.sh`
    - `tmux_attach_session_cmd` を `%q` ベースへ変更し、埋め込みコマンドのクォート崩れを抑止。
    - `kdl_escape` を追加し、layout生成時に `\` / `"` / 改行をKDL向けにエスケープ。
    - `zellij_ui_layout_file` で `args "-lc" "..."` にエスケープ済みコマンドを埋め込むよう変更。
  - `shutsujin_departure.sh`
    - `render_ashigaru_ascii` を追加。
    - `show_battle_cry` の足軽AAを固定8体から人数連動描画へ変更。
  - `scripts/shutsujin_zellij.sh`
    - 同様に `render_ashigaru_ascii` を追加。
    - `show_battle_cry` の足軽AAを人数連動描画へ変更。
- Docs:
  - `docs/REQS.md` に本件追補（AA人数連動 + KDLクォート修正）を追加。
- 検証:
  - `bash -n scripts/goza_no_ma.sh shutsujin_departure.sh scripts/shutsujin_zellij.sh` → PASS
  - `bats tests/unit/test_send_wakeup.bats --timing` → 36 tests PASS
- 判断メモ:
  - KDLパース失敗は layout 文字列への未エスケープ挿入が主因。`kdl_escape` 導入で再発を防止。
  - AAは視覚演出なので、まず1〜8体を安定表示する実装を優先した。

## 2026-02-12 (初動自動送信 + watcher割り込み抑止 + 歴史書導入)
- 要求:
  - 起動直後の最初の命令を自動送信し、手動Enterなしで開始したい。
  - `/new is disabled while a task is in progress` 系の割り込みを抑止したい。
  - 全エージェントへ言語設定（ja/en）を反映し、イベント駆動を徹底したい。
  - Gemini既定モデルを最新Pro系へ更新したい。
  - 人間向け履歴要約「歴史書」を自動生成したい。
  - zellij UI下部の操作バーを復活させたい。
- 実装:
  - `shutsujin_departure.sh`
    - 初動命令を `ready:<agent>` 即時送信 + 言語規則 + イベント駆動 + 報告連鎖込みに改修。
    - 初動命令の投入タイミングを「CLI起動確認後」へ移動（入力欄残留を抑止）。
    - watcher起動envを将軍/家老/足軽すべて `ASW_DISABLE_ESCALATION=1 ASW_PROCESS_TIMEOUT=0` に統一。
    - 起動時に `scripts/history_book.sh` を呼び出すよう追加。
  - `scripts/shutsujin_zellij.sh`
    - 同等の初動命令（ready即時送信・言語・イベント駆動・報告連鎖）へ改修。
    - CLI起動後 `sleep 2` を挟んでから初動命令を送信。
    - watcher起動envを `ASW_DISABLE_ESCALATION=1 ASW_PROCESS_TIMEOUT=0` に統一。
    - 起動時に `scripts/history_book.sh` を呼び出すよう追加。
  - `scripts/inbox_watcher.sh`
    - Codexの `/clear` について、`source_context=escalation` 時は `/new` 変換を抑止。
    - special message経由のみ `/clear -> /new` を許可。
  - `scripts/goza_no_ma.sh`
    - zellij layoutへ `default_tab_template` + `zellij:tab-bar` / `zellij:status-bar` pluginを追加。
  - `scripts/history_book.sh`（新規）
    - `queue/shogun_to_karo.yaml` / `queue/tasks` / `queue/reports` / `queue/inbox` から
      `queue/history/rekishi_book.md` を生成。
  - `scripts/inbox_write.sh`
    - inbox書込成功時に `history_book.sh` を自動実行。
  - `lib/cli_adapter.sh` / `config/settings.yaml` / `README.md` / `tests/unit/test_cli_adapter.bats`
    - Gemini既定モデルを `gemini-3-pro` へ更新。
  - `scripts/configure_agents.sh`
    - gemini/kimi/localapi でCLI別の既定モデル候補を提示する補助関数を追加。
- Docs:
  - `docs/REQS.md` に本件追補を追加。
  - `docs/EXECPLAN_2026-02-12_startup_event_driven.md` を新規追加し進捗更新。
  - `docs/INDEX.md` の Plans にExecPlanを登録。
- 検証:
  - `bash -n shutsujin_departure.sh scripts/shutsujin_zellij.sh scripts/goza_no_ma.sh scripts/inbox_watcher.sh scripts/inbox_write.sh scripts/history_book.sh scripts/configure_agents.sh lib/cli_adapter.sh` → PASS
  - `bash scripts/history_book.sh && sed -n '1,80p' queue/history/rekishi_book.md` → 生成PASS
  - `bats tests/unit/test_cli_adapter.bats tests/unit/test_send_wakeup.bats --timing` → 108 tests PASS（環境依存skip 1）
- 判断メモ:
  - 割り込み問題の主因はwatcherエスカレーションだったため、まず既定で無効化して対話安定性を優先。
  - zellij layoutの実機表示確認は、snap権限の都合でこの実行環境では不可。ユーザーWSL実機で確認が必要。

## 2026-02-12 (pure zellij / hybrid / tmux 分離 + Gemini高負荷再試行)
- 背景:
  - ユーザー報告: `goza_zellij` 実行時に zellij操作とtmux操作が混在して直感的でない。
  - Gemini paneで `We are currently experiencing high demand` が出て停止するケースがあった。
- 実装:
  - `scripts/goza_zellij.sh`
    - 役割を pure zellij に変更（`--mux zellij --ui zellij`）。
  - `scripts/goza_hybrid.sh`（新規）
    - 旧 `goza_zellij` 相当（`--mux tmux --ui zellij`）を分離。
  - `scripts/goza_no_ma.sh`
    - `MUX=zellij` かつ `UI=zellij` で `goza_room` 指定時は、tmuxビューへ入らず `shogun` 直attachへフォールバック。
    - 併せて `goza_hybrid.sh --template goza_room` を案内。
  - `shutsujin_departure.sh`
    - `auto_retry_gemini_busy_tmux` を追加し、Gemini高負荷画面（Keep trying/Stop）で `1` を自動送信して再試行。
  - `README.md`
    - pure zellij / hybrid / tmux の3モード説明へ更新。
    - Gemini高負荷時の挙動をトラブルシュートへ追記。
  - `.gitignore`
    - 新規 `scripts/goza_hybrid.sh` を公開対象に追加。
- 検証:
  - `bash -n shutsujin_departure.sh scripts/goza_no_ma.sh scripts/goza_zellij.sh scripts/goza_hybrid.sh scripts/shutsujin_zellij.sh scripts/inbox_watcher.sh scripts/inbox_write.sh scripts/history_book.sh scripts/configure_agents.sh` → PASS
  - `bats tests/unit/test_send_wakeup.bats --timing` → 36 PASS
- 判断メモ:
  - zellijとtmuxの責務を分離することで、ユーザーが「純正zellij操作」を選ぶ経路を確保。
  - 御座の間俯瞰はtmux描画前提のため、hybrid/tmux専用とした。

## 2026-02-12 (pure zellij goza_room のペイン分割対応)
- 背景:
  - ユーザー報告: `goza_zellij` 起動時に将軍が見えず、単一のコマンドラインに見える。
  - 要望: zellijを開いた時点でペイン分割された画面（将軍含む）を表示したい。
- 実装:
  - `scripts/goza_no_ma.sh`
    - `zellij_collect_active_agents` を共通化（設定から shogun/karo/active_ashigaru を抽出）。
    - `zellij_agent_attach_cmd` を追加（`ZELLIJ=` で nested attach を実行）。
    - `zellij_pure_goza_layout_file` を追加（pure zellij用の複数pane layoutを動的生成）。
    - `zellij_pure_attach_goza_room` を追加（layoutで `goza-no-ma-ui` を起動）。
    - `UI=zellij` かつ `template=goza_room` で、pure zellij複数ペイン表示へ分岐。
  - `README.md`
    - pure zellijでも `goza_room` が使える説明へ更新。
    - 運用例に `bash scripts/goza_zellij.sh --template goza_room` を追加。
- 検証:
  - `bash -n scripts/goza_no_ma.sh` → PASS
  - `rg -n "zellij_pure_goza_layout_file|zellij_pure_attach_goza_room|zellij_agent_attach_cmd" scripts/goza_no_ma.sh` で実装確認。
- 判断メモ:
  - pure zellijではtmux演出（色付き罫線）は使わず、まず「将軍が見える分割画面」を優先した。

## 2026-02-13 (nested zellij解消: pure goza_room を直接CLI起動へ変更)
- 背景:
  - ユーザー実機で、pure zellijの `goza_room` が「1つのzellij内に複数zellijをattach」する表示となり、UIが重複して見づらかった。
- 実装:
  - `scripts/goza_no_ma.sh`
    - pure zellij + goza_room で backend の per-session attach を使わない経路へ変更。
    - `zellij_agent_pane_cmd` を追加し、各paneで `AGENT_ID` をセットしてCLIを直接起動。
    - `PURE_ZELLIJ_GOZA` 判定を追加し、このモードでは `shutsujin_departure.sh` のbackend生成をスキップ（重複セッション回避）。
    - pure goza_room の表示対象は「既存zellij sessionの有無」ではなく `config/settings.yaml` の active agent 構成を直接採用。
  - `README.md`
    - goza_room pure zellij が「ネストattachではなく直接起動」であることを明記。
- 検証:
  - `bash -n scripts/goza_no_ma.sh` → PASS
  - `rg -n "zellij_agent_pane_cmd|PURE_ZELLIJ_GOZA|build_cli_command_with_type" scripts/goza_no_ma.sh` で実装確認。
- 判断メモ:
  - まず「見やすさと操作性（ネスト排除）」を優先し、pure zellij表示の違和感を解消。
