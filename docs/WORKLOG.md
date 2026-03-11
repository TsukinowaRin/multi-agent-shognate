# Worklog

## 2026-02-23 (bootstrap injection 根本修正) [Claude Sonnet 4.6]
- Goal: 「起動はするがプロンプトが注入されない」問題の根本原因特定と修正。
- Root Causes:
  1. **pure zellij path** (`goza_no_ma.sh`): `zellij_agent_pane_cmd()` でTTY直書き方式
     (`printf "%s\r" > "$tty_path"`) を使用していたが、TTYの**出力側**に書くため
     CLIの**入力**には届かない。CLI は bootstrap message を受け取れなかった。
  2. **hybrid tmux path** (`shutsujin_departure.sh`): ready判定に `pane_current_command` を使用。
     codex/gemini はどちらも `node` プロセスとして見えるため判定が常に失敗し、
     タイムアウト境界（12s）で bootstrap を送信 → CLI未起動時に送信することがあった。
- Changes (files):
  - `scripts/goza_no_ma.sh` — `zellij_agent_pane_cmd()` をTTY直書き → **CLI引数渡し**に全面変更
    （`cli_cmd "$startup_msg"` の形式で起動時にブートストラップメッセージをCLI引数として渡す）
  - `shutsujin_departure.sh` — `wait_for_cli_ready_tmux()` 新規追加（`tmux capture-pane` によるスクリーン内容ベース判定）
    `deliver_bootstrap_tmux()` に `cli_type` 引数追加 + ready待機を`wait_for_cli_ready_tmux`に切替
    bulk wait ループを `pane_current_command` → `wait_for_cli_ready_tmux` ベースに変更
    delivery呼び出し行に `$_shogun_cli_type` / `$_gunshi_cli_type` / `$_agent_cli_type` を追加
  - `tests/unit/test_goza_pure_bootstrap.bats` — 第1テストをCLI引数渡し方式の検証に更新（TTY注入パターン消滅確認）
  - `tests/unit/test_zellij_bootstrap_delivery.bats` — tmux ready判定 & cli_type引数受け取りテストを追加
- Commands + Results:
  - `bats tests/unit/` → **181/181 PASS**
  - `git commit` → `e8ca2cd` "fix: bootstrap injection failure — CLI arg渡しとscreen-contentベースready判定に変更"
  - `git push origin codex/auto` → push 済み
- Decisions / Assumptions:
  - TTY直書き (`/dev/pts/X` への書き込み) はターミナル出力側であり、CLIへの入力には届かない。
    → positional argument として渡す方式 (`cli_cmd "msg"`) が確実かつシンプル。
  - `pane_current_command` は node-based CLIでは "node" しか見えないため使えない。
    → `tmux capture-pane -p` でスクリーン内容を取得し、CLI固有UI文字列を `grep -qiE` で判定。
  - ready_pattern は cli_type ごとに定義（codex: "context left|/model", gemini: "type your message|yolo mode" 等）
- Next:
  1. 実機E2E検証（`start_zellij_goza.bat` 実行）— エージェントが role message を受け取ることを確認
  2. `zellij_resume_pure_goza_panes_background` との相互作用確認（CLI起動後にEnterが届いて問題ないか）
  3. REQS.md への追補（CLI引数渡し方式の受け入れ基準を正式化）
- Blockers: なし
- Links: docs/HANDOVER_2026-02-23_prompt_injection_open_issues.md, docs/REQS.md

---

## 2026-02-23 (引き継ぎ文書整備・状況把握セッション) [Claude Opus 4.6]
- Goal: 前セッションからの引き継ぎ。Docs/AGENTS.mdを全読み込みし、実装状況を把握した上でWORKLOGを更新する。
- Context（セッション開始時の状態）:
  - 前回セッション（2026-02-16）で `39556af` をコミット済み（ブートストラップ根本修正）。
  - Codexセッション（2026-02-17〜2026-02-23）でさらに `c5015ed`〜`0fccaa4` が追加されていた。
  - HANDOVER_2026-02-23_prompt_injection_open_issues.md が既に存在し、未解決課題が整理されていた。
- Changes (files):
  - `docs/WORKLOG.md` — 今回のセッション記録を追記（本エントリー）
- Commands + Results:
  - `bats tests/ tests/unit/` → **209/209 PASS**（test_goza_pure_bootstrap.bats, test_zellij_bootstrap_delivery.bats含む）
  - `git log --oneline` → 直近6コミット（`39556af`〜`0fccaa4`）を確認
- 現時点の到達状況:
  - ✅ `scripts/shutsujin_zellij.sh`: 順次起動 + CLI種別readiness判定 + bootstrap_file経由配信
  - ✅ `scripts/goza_no_ma.sh`: attachブロッキング前にresume予約、ペインTTY自己注入
  - ✅ `scripts/inbox_watcher.sh`: command-layer限定のCodex `/clear` 抑止
  - ✅ `lib/cli_adapter.sh`: Codex `--search` 追加
  - ✅ `tests/unit/test_goza_pure_bootstrap.bats`: pure zellij 起動フロー検証
  - ✅ `tests/unit/test_zellij_bootstrap_delivery.bats`: zellij bootstrap配信静的検証
  - 🔴 実機での「注入されない」問題が未解決（HANDOVER_2026-02-23参照）
- 未解決課題（次エージェント向け）:
  - P0: 起動経路別（goza_no_ma.sh / shutsujin_zellij.sh）の注入処理を一本化
  - P0: ACK機構（ready:<agent>応答を確認してから次へ進む）の導入
  - P0: 実機ログ（queue/runtime/goza_bootstrap_*.log）による再現確認
  - P1: wait_for_cli_ready() の判定厳密化（CLI別idle promptの明確化）
  - 詳細: docs/HANDOVER_2026-02-23_prompt_injection_open_issues.md
- Notes:
  - 実機テスト結果（2026-02-17ユーザー報告）: 起動中Zellijをポチポチすると、フォーカス変更で混線。
    家老に軍師プロンプト、足軽に家老プロンプトが注入される症状。
  - 本セッションでは新規実装なし。引き継ぎ文書の確認・整備が目的。

---

## 2026-02-17 15:15 (JST)
- Goal: Zellijプロンプト注入混線問題の修正（A案：順次起動方式の強化）
- Changes (files):
  - `scripts/shutsujin_zellij.sh` — BOOTSTRAP_AGENT_GAPを2秒から5秒に延長
  - `scripts/shutsujin_zellij.sh` — send_line関数で送信完了を待機（sleep 0.5追加）
  - `scripts/shutsujin_zellij.sh` — deliver_bootstrap_zellij関数で送信完了を待機（sleep 1追加）
  - `docs/EXECPLAN_2026-02-17_zellij_bootstrap_stability.md` — 新規作成（実行計画）
  - `docs/HANDOVER_2026-02-17_bootstrap_injection.md` — 新規作成（引き継ぎドキュメント）
  - `tests/unit/test_zellij_bootstrap_delivery.bats` — 新規作成（ブートストラップ配信テスト）
- Commands + Results:
  - `bash -n scripts/shutsujin_zellij.sh` → syntax OK
  - `bats tests/unit/` → 173 passed, 0 failures
  - `git commit -m 'codex: Zellijプロンプト注入混線問題の修正（順次起動方式の強化）...'` → c5015ed
- Decisions / Assumptions:
  - Zellijの`action write-chars`は非同期で実行されるため、送信完了を待機する必要がある。
  - エージェント間のインターバルを2秒から5秒に延長することで、混線リスクを低減。
  - send_line関数とdeliver_bootstrap_zellij関数にsleepを追加することで、送信完了を待機。
- Next:
  1. ユーザーによるgit push実行
  2. 実機E2E検証（Zellij Pure Mode）
  3. WORKLOG更新
- Blockers: git認証未設定（push待ち）
- Links: docs/REQS.md, docs/HANDOVER_2026-02-17_bootstrap_injection.md

---

## 2026-02-15 13:35 (JST)
- Goal: zellij E2E検証完了
- Changes (files):
  - なし（すべての変更は前回のコミットで完了）
- Commands + Results:
  - `zellij --version` → 0.41.2
  - `MAS_MULTIPLEXER=zellij bash shutsujin_departure.sh -s` → セッション作成OK
  - `MAS_MULTIPLEXER=zellij bash shutsujin_departure.sh` → 起動成功
  - `grep "$(date '+%a %b %d')" logs/inbox_watcher_*.log` → 全エージェントのinbox_watcher起動記録を確認
- Decisions / Assumptions:
  - REQS.mdのR4（zellij フルE2E）が完了
  - R1〜R4すべて判定済み
- Next:
  - WORKLOG.md更新済み
  - 全要件完了
- Blockers: なし
- Links: docs/REQS.md

---

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

## 2026-02-13 (pure zellij goza_room レイアウト再設計: 将軍>家老>足軽)
- 背景:
  - ユーザー報告: pure zellij の御座の間が縦4段で横長・情報密度が低く、役職優先が伝わりづらい。
  - 要望: 将軍を最も大きく縦長、家老を次点、足軽は小さな正方形でコンパクト表示。
- 実装:
  - `scripts/goza_no_ma.sh`
    - `zellij_pure_goza_layout_file` を再設計。
    - 将軍/家老/足軽を分離して解決し、以下の pure zellij レイアウトへ変更。
      - 外枠: 左右分割（左=将軍 66%、右=家老+足軽 34%）
      - 右枠: 上下分割（上=家老 58%、下=足軽 42%）
      - 足軽: `zellij_emit_ashigaru_grid` で 1〜8 体を2列ベースで段組み（コンパクト表示）
    - 補助関数を追加。
      - `zellij_emit_agent_leaf`
      - `zellij_emit_ashigaru_row`
      - `zellij_emit_ashigaru_grid`
- Docs:
  - `docs/REQS.md` に本件追補（縦長優先レイアウト）を追加。
  - `docs/INDEX.md` の最終更新日を更新。
- 検証:
  - `bash -n scripts/goza_no_ma.sh` → PASS
  - `rg -n "zellij_emit_ashigaru_grid|zellij_emit_ashigaru_row|size=\"66%\"|size=\"58%\"" scripts/goza_no_ma.sh` で実装存在を確認。
- 判断メモ:
  - 実機の zellij レンダリング確認は、この実行環境では `zellij` 実行権限制約（snap confine）により未実施。
  - そのため、KDL構文互換を壊さない範囲で既存スタイルを維持しつつ、分割構造のみを明示化した。

## 2026-02-13 (pure zellij: 将軍/家老の縦長化 + 初動命令自動注入)
- 背景:
  - ユーザー報告: pure zellij `goza_room` が横長で履歴が追いづらい。
  - 要望: 将軍は上から下までの縦長最大、家老はその隣で縦長次点、足軽は余白側でコンパクトな正方形寄せ。
  - 追加要望: 起動直後に初動命令を自動注入し、すぐ実働可能にする。
- 実装:
  - `scripts/goza_no_ma.sh`
    - pure zellij レイアウトの分割方向を調整し、3列構成へ再設計。
      - 左列: 将軍（最大、`focus=true` で初期アクティブ）
      - 中列: 家老（次点サイズ、縦長）
      - 右列: 足軽グリッド（2列ベースで段組み）
    - `goza_*_directive` / `goza_startup_bootstrap_message` を追加し、純zellij経路でもtmux系と同じ初動命令文面を生成。
    - `zellij_bootstrap_pure_goza_background` を追加し、session起動後に `write-chars` + `focus-next-pane` で各paneへ初動命令を順次注入。
    - 最後に将軍ペインへフォーカスを戻す処理を追加。
- Docs:
  - `docs/REQS.md` に「pure zellij 初動命令の自動注入」追補を追加。
- 検証:
  - `bash -n scripts/goza_no_ma.sh` → PASS
  - `rg -n "zellij_bootstrap_pure_goza_background|goza_startup_bootstrap_message|focus-next-pane|focus=true" scripts/goza_no_ma.sh` で実装存在を確認。
- 判断メモ:
  - zellij 0.41系の分割方向仕様差分に合わせ、既存実機表示（上下分割化していた現象）を逆算して方向を再設定した。
  - 実機描画の最終確認はユーザー環境（WSL+zellij）での目視確認が必要。

## 2026-02-13 (pure zellij微調整: 自動注入の送信確定 + 足軽の正方形寄せ)
- 背景:
  - ユーザー報告: 初動命令は自動注入されるが、送信確定されず入力欄に残る。
  - ユーザー要望: 足軽ペインは縦長よりも正方形寄りでコンパクトにしたい。
- 実装:
  - `scripts/goza_no_ma.sh`
    - `zellij_send_line_to_session` を強化。
      - 先に `write-chars + \r/\n` 同梱送信を試行。
      - 失敗時に既存の `write 13/10` フォールバックを継続。
    - pure zellij `goza_room` を3列構成へ再調整。
      - 将軍列 46%（全高、最大）
      - 家老列 32%（全高、次点）
      - 足軽列 22%（余白側コンパクト）
    - 足軽2体時は上下2分割を優先するよう、`zellij_emit_ashigaru_grid` を調整。
- Docs:
  - `docs/REQS.md` の「pure zellij 初動命令の自動注入」に「送信確定まで自動実行」を追記。
- 検証:
  - `bash -n scripts/goza_no_ma.sh` → PASS
  - `rg -n "write-chars .*\\$'\\\\r'|action write 13|action write 10|size=\"46%\"|size=\"32%\"|size=\"22%\"" scripts/goza_no_ma.sh` で実装存在を確認。
- 判断メモ:
  - zellijバージョン差分で改行送信の受理方法が揺れるため、同梱送信→key送信の多段フォールバックを採用。

## 2026-02-13 (Gemini 3 Preview化 + pure zellij 初動送信安定化)
- 背景:
  - ユーザー報告: Geminiは起動前に初動命令が送られることがある。
  - ユーザー報告: Codexは文面注入されるが自動送信されないことがある。
  - 追加要望: Geminiモデルを Gemini 3 Preview に統一したい。
- 実装:
  - `scripts/goza_no_ma.sh`
    - `zellij_send_line_to_session` を修正し、改行文字注入ではなく Enterキー送信（`action write 13/10`）を優先。
    - pure zellij 初動注入に CLI別待機時間を追加（`gemini=6s / codex=2s / others=3s`）。
    - 初動送信を最大3回再試行するように変更。
    - 足軽2名時の分割を縦割りへ戻し、正方形寄り表示に調整。
  - `lib/cli_adapter.sh`
    - Gemini既定モデルを `gemini-3-preview` へ変更。
  - `scripts/configure_agents.sh`
    - CUIでの gemini 既定モデルを `gemini-3-preview` へ変更。
  - `config/settings.yaml`
    - 現在設定の ashigaru1/2 のモデルを `gemini-3-preview` へ更新。
  - `README.md` / `tests/unit/test_cli_adapter.bats` / `docs/REQS.md`
    - `gemini-3-pro` 記載を `gemini-3-preview` へ更新。
- 検証:
  - `bash -n scripts/goza_no_ma.sh lib/cli_adapter.sh scripts/configure_agents.sh` → PASS
  - `bats tests/unit/test_cli_adapter.bats --timing` → 72 tests PASS（skip 1）
- 判断メモ:
  - 送信不発の主因は「改行文字注入」と「Enterキーイベント」がCLI側で等価でない点。
  - 起動前送信は固定短時間待機が短すぎるため、CLI別待機 + 再試行に変更した。

## 2026-02-13 (Gemini/Codex Autoモデル化 + inbox_watcher調査)
- 背景:
  - ユーザー要望: Gemini/Codex はモデル固定をやめ、CLI側Auto選択に統一したい。
  - ユーザー報告: Codexで初動文面は入るが送信されない、Geminiで起動前送信が起きる。
  - ユーザー要望: inbox_watcherの状況を自走で調査してほしい。
- 実装:
  - `lib/cli_adapter.sh`
    - gemini で `model=auto/default/空` の場合は `--model` を付与しない仕様へ変更。
    - gemini既定モデルを `auto` に変更。
  - `config/settings.yaml`
    - `ashigaru1/2` の gemini model を `auto` に変更。
  - `scripts/configure_agents.sh`
    - gemini既定モデル候補を `auto` に変更。
  - `scripts/goza_no_ma.sh`
    - 送信処理を `write-chars(本文)` + Enterキー送信（`write 13/10`）優先に再調整。
    - 初動注入の待機をCLI別に維持しつつ、再送制御を継続。
    - 足軽2名時は横方向（上下段）配置で正方形寄りに補正。
  - `README.md` / `tests/unit/test_cli_adapter.bats` / `docs/REQS.md`
    - gemini model記載を `auto` 運用へ更新。
- inbox_watcher調査結果:
  - `logs/inbox_watcher_*.log` を確認。
  - 過去ログに `inotifywait not found` が多数（当時の未導入起動）。
  - 直近ログでは watcher 起動自体は継続しており、tmux運用時に未読メッセージのエスカレーション履歴（Phase2/Phase3）が記録されている。
- 検証:
  - `bash -n scripts/goza_no_ma.sh lib/cli_adapter.sh scripts/configure_agents.sh` → PASS
  - `bats tests/unit/test_cli_adapter.bats --timing` → 72 tests PASS
- 判断メモ:
  - Auto運用は「モデル指定しない」ことが本体のため、geminiは `--model` 非付与を仕様化。
  - codexは既存実装が `--model` を付けないため、実質Auto運用を維持。

## 2026-02-13 (Claude連携テスト準備 + inbox_watcherログ確認)
- 背景:
  - ユーザー要望: Claude Pro契約後、Claude連携を実機で試したい。
  - 指示: inbox_watcherは自走で調査。
- 実施:
  - `claude --version` を確認し、CLI導入を確認（2.1.41）。
  - `config/settings.yaml` をローカルでテスト構成へ更新。
    - `shogun/karo: claude (opus)`
    - `ashigaru1/2: gemini (auto)`
  - `lib/cli_adapter.sh` を source して agent別の解決結果を確認。
- 観測結果:
  - この実行環境では `gemini` コマンド未検出のため、`resolve_cli_type_for_agent` が `codex` へフォールバックした。
  - `logs/inbox_watcher_*.log` を確認し、過去の `inotifywait not found` と、tmux運用時のエスカレーション履歴を確認。
- 判断メモ:
  - ユーザー実機では Gemini CLI 導入済みのため、今回のフォールバック警告はこの実行環境固有の差分。

## 2026-02-13 (役職別CLI固定 + 初動注入先ずれ修正)
- 背景:
  - ユーザー要望: 将軍=Claude、家老=Codex、足軽=Gemini に固定したい。
  - ユーザー報告: pure zellij で初動命令の注入先がずれ（将軍文面が足軽へ等）、足軽2で未注入が出る。
- 実装:
  - `config/settings.yaml`（ローカル設定）
    - `shogun: claude(opus)` / `karo: codex` / `ashigaru1,2: gemini(auto)` に更新。
  - `scripts/goza_no_ma.sh`
    - 初動注入ロジックを再設計。
      - `zellij_focus_shogun_anchor`: 左上（将軍）へフォーカス寄せ。
      - `zellij_focus_direction`: 方向移動アクションのラッパー。
      - `zellij_send_bootstrap_current_pane`: 現在ペインへ送信+再試行。
      - 送信順を固定化（将軍→家老→足軽1→足軽2）し、4体超は循環フォーカスで処理。
    - 足軽2名時レイアウトを上下配置（`split_direction="vertical"`）に戻し、注入順の安定化に合わせた。
- 検証:
  - `bash -n scripts/goza_no_ma.sh` → PASS
  - `source lib/cli_adapter.sh` で配備解決確認。
    - この実行環境では gemini未導入のため ashigaru は codexへフォールバック（ユーザー環境差分）。
  - `rg -n "zellij_focus_shogun_anchor|zellij_focus_direction|zellij_send_bootstrap_current_pane|count -ge 4" scripts/goza_no_ma.sh` で実装確認。
- 判断メモ:
  - 先ずれの主因は `focus-next-pane` の開始位置依存だったため、方向移動で将軍アンカーへ寄せてから役職順送信へ変更。

## 2026-02-13 (pure zellij: 足軽2沈黙 / 足軽1読込失敗の改善)
- 背景:
  - ユーザー報告: `ashigaru2` が沈黙し、`ashigaru1`（Gemini）が初動でファイルを読めないケースが発生。
  - 観測: pure zellij の注入ロジックが「現在フォーカス起点」で、4ペイン時に送信先がずれる可能性があった。
  - 観測: Geminiは起動直後に trust/high-demand 画面へ入ることがあり、初動命令が実タスク入力として受理されにくい。
- 実装:
  - `scripts/goza_no_ma.sh`
    - `zellij_focus_agent_index` を追加し、毎回「将軍アンカー→対象インデックス」へ再フォーカスして注入する方式へ変更。
    - `zellij_prepare_gemini_gate_current_pane` を追加し、Gemini足軽へは初動命令前に軽い先行入力（`1`）を実施。
    - Gemini向け `goza_startup_bootstrap_message` を `@AGENTS.md @instructions/...` 明示形式へ変更。
    - 足軽2名グリッドを `split_direction="vertical"` にして、4ペイン時の `ashigaru1 -> ashigaru2` 注入導線（down優先）を安定化。
  - `docs/REQS.md`
    - 「足軽2沈黙/足軽1読込失敗の改善」追補を追加（観測可能な受け入れ条件つき）。
  - `docs/EXECPLAN_2026-02-12_startup_event_driven.md`
    - Progress / Decision Log / Outcomes を今回対応に合わせて更新。
- 検証:
  - `bash -n scripts/goza_no_ma.sh` → PASS
  - `bash -n shutsujin_departure.sh scripts/shutsujin_zellij.sh` → PASS
  - `bash scripts/goza_no_ma.sh --help` → PASS
  - `rg -n "zellij_focus_agent_index|zellij_prepare_gemini_gate_current_pane|この順で読む: @AGENTS.md" scripts/goza_no_ma.sh` → 実装確認
- 判断メモ:
  - 送信先ずれ対策としては、相対移動を積み重ねるより「毎回アンカー復帰」が安全。
  - Geminiの初回画面はCLI依存で完全判定が難しいため、軽い先行入力で失敗率を下げる現実解を採用。

## 2026-02-13 (pure zellij: 足軽増員に備えた注入方式の切替)
- 背景:
  - ユーザー要望: 足軽増員時に同様の沈黙/誤注入が再発すると困る。
  - 既存方式（外部フォーカス移動 + write）は、ペイン数増加時に順序依存リスクが残る。
- 実装:
  - `scripts/goza_no_ma.sh`
    - `zellij_agent_pane_cmd` を拡張し、各pane内で起動するシェルが自分のTTY（`tty_path="$(tty)"`）へ初動命令を直接送信する方式へ変更。
    - Gemini足軽では pane内先行入力（`1`）後に初動命令を送るようにした。
    - `zellij_pure_attach_goza_room` で外部注入呼び出しを停止し、pane内自動送信方式を正とした。
  - `docs/REQS.md`
    - 「足軽増員時の初動注入スケーラビリティ」追補を追加。
- 検証:
  - `bash -n scripts/goza_no_ma.sh` → PASS
  - `rg -n "bootstrap_line=|tty_path=\\\"\\$\\(tty\\)\\\"|pure zellij では各pane内で自動初動送信" scripts/goza_no_ma.sh` → 実装確認
- 判断メモ:
  - 増員耐性は「外部制御の賢さ」より「各pane自己完結」の方が安定。
  - フォーカス注入関数は残置しているが、pure zellij の標準経路では未使用。

## 2026-02-13 (足軽9名以上対応 + ashigaru2同期ずれ対策)
- 背景:
  - ユーザー要望: 足軽を9名以上へ増員しても安定稼働させたい。
  - ユーザー報告: `ashigaru2` で偽通知（同期ずれ）と待機ループが発生。
  - 調査: `watcher_supervisor.sh` は固定1..8配列かつ escalation抑止フラグ未設定で watcher 起動しており、pane不一致時の再同期も未実装。
- 実装:
  - `shutsujin_departure.sh`
    - `active_ashigaru` パースの上限固定（<=8）を撤廃し、`ashigaruN (N>=1)` を許容。
    - clean時の task/report/inbox 初期化対象を固定1..8ではなく `KNOWN_ASHIGARU`（active + 既存ファイル）へ変更。
    - 起動時AAを複数段表示へ変更し、人数が8を超えても表示できるようにした。
  - `scripts/shutsujin_zellij.sh`
    - `active_ashigaru` パース上限撤廃。
    - staleセッション削除を固定1..8から `zellij list-sessions` の動的検出へ変更。
    - clean時初期化対象を `KNOWN_ASHIGARU` へ変更。
    - 人数連動AAを複数段表示へ変更。
  - `scripts/goza_no_ma.sh`
    - `zellij_collect_active_agents` の足軽番号上限撤廃。
  - `scripts/configure_agents.sh`
    - 足軽人数入力を `1以上の整数` に拡張（旧: 1-8）。
  - `scripts/watcher_supervisor.sh`
    - active足軽を毎ループで動的読込（`ashigaru9+` 対応）。
    - pane一致 watcher が無ければ stale watcher をkillして再起動する再同期ロジックを追加。
    - watcher起動envを `ASW_DISABLE_ESCALATION=1 ASW_PROCESS_TIMEOUT=0 ASW_DISABLE_NORMAL_NUDGE=0` に統一。
    - 非active足軽の stale watcher を定期掃除する処理を追加。
- 検証:
  - `bash -n shutsujin_departure.sh scripts/shutsujin_zellij.sh scripts/goza_no_ma.sh scripts/configure_agents.sh scripts/watcher_supervisor.sh` → PASS
  - `rg -n "ASW_DISABLE_ESCALATION=1 ASW_PROCESS_TIMEOUT=0 ASW_DISABLE_NORMAL_NUDGE=0" scripts/watcher_supervisor.sh` → 反映確認
  - `rg -n "ashigaru\\[1-9\\]\\[0-9\\]\\*|i >= 1|x >= 1" shutsujin_departure.sh scripts/shutsujin_zellij.sh scripts/goza_no_ma.sh scripts/configure_agents.sh` → 上限撤廃確認
- 判断メモ:
  - 同期ずれは「ashigaru2の能力不足」ではなく、監視プロセスのpane追従不足と安全フラグ差分が主因。
  - まず watcher層を安定化し、その上で役職フローに戻す方が再現性が高い。

## 2026-02-14 (複数家老の均等割り振り + 経路制約)
- 背景:
  - ユーザー要求: 家老が複数人のとき、足軽を均等配分し、担当外報告を防止したい。
  - 既存状態: owner map は起動時生成済みだったが、`inbox_write` と `watcher_supervisor` が単一家老前提で制約不足。
- 実装:
  - `scripts/inbox_write.sh`
    - `queue/runtime/ashigaru_owner.tsv` を参照する送信経路バリデーションを追加。
    - `ashigaruN -> 非担当karoX` を拒否。
    - `karoX -> karoY (X!=Y)` を拒否。
  - `scripts/watcher_supervisor.sh`
    - `lib/topology_adapter.sh` を読込、`topology_resolve_karo_agents` ベースで `KARO_AGENTS` を解決。
    - zellij/tmux双方で `karo1..karoN` watcher 起動に対応。
    - stale watcher 掃除を `ashigaru` 限定から「managed agent判定」へ拡張。
  - `scripts/configure_agents.sh`
    - 設定保存後に owner map を再計算し、家老別人数サマリを表示。
  - `instructions/karo.md` / `instructions/ashigaru.md`
    - 担当固定・非担当禁止・家老間直接通信禁止を追記。
  - docs更新:
    - `docs/REQS.md` に 2026-02-14 追補を追加。
    - `docs/EXECPLAN_2026-02-14_multi_karo_round_robin.md` を新規作成。
    - `docs/INDEX.md` を更新。
  - tests更新:
    - 新規 `tests/unit/test_topology_adapter.bats` を追加。
    - `tests/test_inbox_write.bats` に T-013〜T-015 を追加。
- 検証:
  - `bash -n scripts/inbox_write.sh scripts/watcher_supervisor.sh scripts/configure_agents.sh shutsujin_departure.sh scripts/shutsujin_zellij.sh` → PASS
  - `bash -n lib/topology_adapter.sh lib/cli_adapter.sh` → PASS
  - `bats tests/unit/test_topology_adapter.bats tests/test_inbox_write.bats tests/unit/test_send_wakeup.bats` → 55/55 PASS
- 判断メモ:
  - 経路制約は最終送信ポイント（`inbox_write`）で強制するのが最も再現性が高い。
  - 運用中再配分は要件外のため、今回は起動時固定のみ実装してスコープを維持。

## 2026-02-14 (queue/inbox のGit不整合整理)
- 背景:
  - `git add -A` 実行時に `queue/inbox` で `Function not implemented` が再発していた。
  - `queue/inbox` は履歴上 symlink（mode 120000）で、WSL/DrvFS環境差分と衝突していた。
- 対応:
  - 作業ツリー上は `queue/inbox` をディレクトリへ戻し、実行時生成に統一。
  - Git上は `queue/inbox` の追跡削除を維持（`.gitignore` の `queue/inbox` ルールで再追跡を防止）。
- 検証:
  - `bats tests/unit/test_topology_adapter.bats tests/test_inbox_write.bats` → PASS
- 判断メモ:
  - inboxはランタイムデータのため、VCS管理対象にしない方が環境差分の事故を減らせる。

## 2026-02-14 (tmux/zellij 挙動同一化: inbox 正規化)
- 背景:
  - ユーザー要求: tmux と zellij で同じ動作にしてテストしたい。
  - 差分要因: inbox初期化がモードごとに異なり、`queue/inbox` がファイル化すると起動・書き込みが不安定になる。
- 実装:
  - 新規 `lib/inbox_path.sh` を追加し、`ensure_local_inbox_dir` で `queue/inbox` を常にローカルディレクトリへ正規化。
  - `shutsujin_departure.sh` / `scripts/shutsujin_zellij.sh` / `scripts/goza_no_ma.sh` / `scripts/watcher_supervisor.sh` が同ヘルパーを利用するよう更新。
  - `scripts/inbox_write.sh` に `queue/inbox` がファイルでも自動復旧する処理を追加。
  - `tests/unit/test_mux_parity.bats` を追加（起動系で共通ヘルパー利用を静的確認）。
  - `tests/test_inbox_write.bats` に T-016（file→directory 自動復旧）を追加。
  - `docs/REQS.md` / `docs/EXECPLAN_2026-02-14_mux_behavior_parity.md` / `docs/INDEX.md` を更新。
- 検証:
  - `bash -n lib/inbox_path.sh scripts/inbox_write.sh scripts/watcher_supervisor.sh shutsujin_departure.sh scripts/shutsujin_zellij.sh scripts/goza_no_ma.sh` → PASS
  - `bats tests/unit/test_mux_parity.bats tests/test_inbox_write.bats tests/unit/test_send_wakeup.bats` → 55/55 PASS
  - `MAS_MULTIPLEXER=tmux bash shutsujin_departure.sh -s` → この実行環境では tmux socket 権限エラーで失敗（`Operation not permitted`）
  - `MAS_MULTIPLEXER=zellij bash shutsujin_departure.sh -s` → この実行環境では zellij セッション作成失敗
  - 失敗後も `queue/inbox` はディレクトリ維持を確認（`test -d queue/inbox` 成功）。
- 判断メモ:
  - inboxをsymlink運用せずディレクトリ正規化に寄せる方が、tmux/zellij双方で同じ復旧ロジックを適用しやすい。

## 2026-02-14 (goza zellij の複数家老対応)
- 背景:
  - tmux側は `topology_resolve_karo_agents` で `karo1..karoN` を扱えるが、`goza_no_ma.sh` の pure zellij 経路は `karo` 固定寄りだった。
- 実装:
  - `scripts/goza_no_ma.sh` が `lib/topology_adapter.sh` を読込むよう変更。
  - `zellij_collect_active_agents` で `topology_load_active_ashigaru` + `topology_resolve_karo_agents` を優先使用。
  - 役職判定を `karo|karo[1-9]*|karo_gashira` へ拡張（連携規則・報告規則・指示書解決）。
  - pure zellij レイアウトの家老エリアを単数 `karo` 固定から、家老配列のグリッド表示へ変更。
  - `tests/unit/test_mux_parity.bats` に topology利用・複数家老判定の静的検証を追加。
- 検証:
  - `bash -n scripts/goza_no_ma.sh` → PASS
  - `bats tests/unit/test_mux_parity.bats tests/test_inbox_write.bats tests/unit/test_send_wakeup.bats` → 57/57 PASS
- 判断メモ:
  - multiplexer実行権限が無い環境ではE2Eを完了できないため、CIでは静的検証＋ユニット回帰で担保し、実機はユーザーWSLで最終確認とする。

## 2026-02-14 (tmux/zellij parity スモークスクリプト追加)
- 背景:
  - ユーザーが実機で tmux/zellij の同一挙動を短手順で確認できる導線が必要。
- 実装:
  - `scripts/mux_parity_smoke.sh` を追加。
    - `--dry-run` / `--tmux-only` / `--zellij-only` / `--clean` を提供。
    - `shutsujin_departure.sh -s` を tmux/zellij で実行し、`queue/inbox` ディレクトリ化と owner map 生成を検証。
    - 両モード実行時は `queue/runtime/ashigaru_owner.tmux.tsv` と `.zellij.tsv` を比較。
  - `tests/unit/test_mux_parity_smoke.bats` を追加し、dry-run出力を検証。
  - `docs/REQS.md` に受け入れ条件を追記。
- 検証:
  - `bash -n scripts/mux_parity_smoke.sh` → PASS
  - `bats tests/unit/test_mux_parity_smoke.bats` → PASS

## 2026-02-14 (ランタイム初期化の parity 追加調整)
- 背景:
  - tmux/zellij の setup-only 後で、`queue/ntfy_inbox.yaml` 初期化有無と inbox YAML の初期値表記に差が残っていた。
- 実装:
  - `shutsujin_departure.sh` の inbox初期化を `messages: []` へ統一。
  - `scripts/shutsujin_zellij.sh` に `queue/ntfy_inbox.yaml` の常時確保（clean時初期化）を追加。
  - `scripts/mux_parity_smoke.sh` で `queue/ntfy_inbox.yaml` の存在チェックを追加。
  - `tests/unit/test_mux_parity.bats` に `ntfy_inbox.yaml` 生成確認を追加。
- 検証:
  - `bash -n shutsujin_departure.sh scripts/shutsujin_zellij.sh scripts/mux_parity_smoke.sh` → PASS
  - `bats tests/unit/test_mux_parity_smoke.bats tests/unit/test_mux_parity.bats tests/test_inbox_write.bats tests/unit/test_send_wakeup.bats` → PASS

## 2026-02-14 (上流同期: Codex model / watcher self-watch 判定)
- 背景:
  - ユーザー要求: 上流 `yohey-w/multi-agent-shogun` の更新内容を確認し、本リポジトリで必要な更新を取り込む。
  - 直近上流差分のうち、実運用影響が大きいのは `9d4ca4d`（Codex `--model`）と `f10ee4b`（self-watch判定改善）。
- 実装:
  - `lib/cli_adapter.sh`
    - `_cli_adapter_get_configured_model` を追加。
    - Codex起動コマンドで、`cli.agents.<id>.model` / `models.<id>` の明示値のみ `--model` 付与。
    - `auto/default/空` は `--model` を付与しない（Auto運用維持）。
  - `scripts/inbox_watcher.sh`
    - `agent_has_self_watch` を claude限定 + PGID除外に変更し、watcher自身の inotifywait を誤検知しないよう改善。
    - busy時ログを CLI種別別に出力。
    - claude の Phase2 Escape エスカレーションを抑止し、通常 nudge へフォールバック。
  - テスト更新:
    - `tests/unit/test_cli_adapter.bats` に Codex model指定/auto のケースを追加。
    - `tests/unit/test_send_wakeup.bats` に non-claude self-watch無効化、claude Escape抑止ケースを追加。
  - ドキュメント:
    - `docs/UPSTREAM_SYNC_2026-02-14.md`（差分分析と採用/非採用）を新規追加。
    - `docs/EXECPLAN_2026-02-14_upstream_sync.md` を新規追加。
    - `docs/INDEX.md` / `docs/REQS.md` を更新。
- 検証:
  - `bash -n lib/cli_adapter.sh scripts/inbox_watcher.sh tests/unit/test_cli_adapter.bats tests/unit/test_send_wakeup.bats` → PASS
  - `bats tests/unit/test_cli_adapter.bats tests/unit/test_send_wakeup.bats` → 112/112 PASS
- 判断メモ:
  - 上流 `Codex --model` は有効だが、本リポジトリは既定モデルがClaude系のため、"明示設定のみ付与" に調整しないと誤モデル注入リスクがある。
  - 上流 `gunshi` 追加は本リポジトリの可変トポロジと影響範囲が広いため、今回は非採用。

## 2026-02-14 (実機テスト不具合: pure zellij 初動未注入 / tmux未アタッチ)
- 背景:
  - ユーザー実機で `goza_zellij --template goza_room` 実行時に、初動プロンプトが自動送信されないケースを確認。
  - `goza_tmux` 実行後にtmux画面へ遷移せず、シェルへ戻るケースを確認。
  - `shutsujin_departure.sh` のCLI起動確認30秒待ちで、体感遅延が大きい。
- 実装:
  - `scripts/goza_no_ma.sh`
    - pure zellij の初動注入を「pane内埋め込み」依存から、`zellij_bootstrap_pure_goza_background` によるセッション作成後一括送信へ統一。
    - `zellij_agent_pane_cmd` はCLI起動専用に簡素化（注入処理を分離）。
    - tmux attach を `TMUX= tmux attach...` に変更（ネスト環境でのattach失敗を回避）。
    - `shutsujin_departure.sh` 呼出時に `MAS_CLI_READY_TIMEOUT`（既定12秒）を渡すように変更。
  - `shutsujin_departure.sh`
    - CLI起動確認の待機上限を固定30秒から `MAS_CLI_READY_TIMEOUT` 可変に変更。
- 検証:
  - `bash -n scripts/goza_no_ma.sh shutsujin_departure.sh` → PASS
  - `bats tests/unit/test_mux_parity.bats tests/unit/test_mux_parity_smoke.bats tests/unit/test_send_wakeup.bats` → 46/46 PASS
  - `rg -n "MAS_CLI_READY_TIMEOUT|zellij_bootstrap_pure_goza_background|TMUX= tmux attach" scripts/goza_no_ma.sh shutsujin_departure.sh` → 実装行を確認。
- 判断メモ:
  - 初動注入は「セッション単位で後段注入」へ寄せる方が、ペイン数可変時に安定する。
  - tmux attachは `TMUX=` 明示で環境依存の失敗を減らせる。

## 2026-02-14 (Codex制限前 引き継ぎドキュメント作成)
- 背景:
  - ユーザー要求: Codex利用制限前に、思考中の事項・今後作業・即対応事項をDocsへ完全に引き継ぐ。
- 実装:
  - 新規 `docs/HANDOVER_2026-02-14_codex_limit.md` を作成。
    - 現在の到達点（反映済みコミット）
    - いま考えていること（技術判断の前提）
    - 今やるべきこと（Must-Do）
    - これからやること（Next）
    - 既知リスク
    - 再開時チェックリスト
    - 実機検証コマンド（コピペ）
  - `docs/INDEX.md` の Specs に handover 文書を登録。
- 判断メモ:
  - 直近の課題は機能追加より実機安定性確認と運用データのGit整理。
  - 引き継ぎは「作業背景」と「即実行コマンド」を同時に残す形が最短復帰に有効。

## 2026-02-14 (queue実行時ファイルの追跡整理)
- 背景:
  - VSCodeのSource Controlで `queue/` 配下の実行時ファイルが大量表示され、ステージ/コミット操作を阻害。
- 実装:
  - `.gitignore` を更新し、`queue/` は原則 ignore、`queue/shogun_to_karo.yaml` のみ追跡対象に限定。
  - 既存追跡済みだった runtime ファイル（history/metrics/reports/runtime/tasks の11ファイル）を `git rm --cached` でインデックスから除外。
- 判断メモ:
  - 実行時データを追跡し続けると、運用のたびに差分が増殖するため、コード変更と運用データを分離した。

## 2026-02-17 (zellij初動注入の安定化: 逐次起動/厳密ready判定)
- 背景:
  - 継続開発要求に合わせ、`docs/HANDOVER_2026-02-17_bootstrap_injection.md` で未解決だった zellij 初動注入混線の主因を先に潰す。
  - 既存 `wait_for_cli_ready` が `\$` を含むため、CLI未起動でも shell で ready 誤判定し得る状態だった。
- 実装:
  - `scripts/shutsujin_zellij.sh`
    - `wait_for_cli_ready` を `wait_for_cli_ready(session, cli_type, max_wait)` へ変更。
    - ready 判定を CLI種別パターン化し、shell prompt 依存を除去。
    - 起動フローを「全CLI起動→全注入」から「agent単位: 起動→ready確認→注入」へ直列化。
    - `MAS_ZELLIJ_BOOTSTRAP_GAP`（既定2秒）を追加し、エージェント間送信の競合回避余地を提供。
  - `tests/unit/test_zellij_bootstrap_delivery.bats` を新規追加（静的回帰）。
  - docs 更新:
    - `docs/INDEX.md` に 2026-02-17 handover/execplan を登録。
    - `docs/REQS.md` に本修正の受け入れ条件を追記。
    - `docs/EXECPLAN_2026-02-17_zellij_bootstrap_stability.md` を作成・更新。
- 検証:
  - `bash -n scripts/shutsujin_zellij.sh` → PASS
  - `bats tests/unit/test_zellij_bootstrap_delivery.bats tests/unit/test_mux_parity.bats` → 9/9 PASS
- 判断メモ:
  - この段階では「誤判定削減 + 逐次化」による安定化を優先し、pure zellij 実機E2Eは次チェックポイントで確認する。

## 2026-02-17 17:00 (JST)
- Goal: 実機E2E検証と引き継ぎドキュメント更新
- Changes (files):
  - config/settings.yaml — 将軍=codex, 家老=codex, 軍師=gemini, 足軽=geminiに設定
  - docs/HANDOVER_2026-02-17_bootstrap_injection.md — 実機テスト結果を追記
  - docs/WORKLOG.md — WORKLOG更新
- Commands + Results:
  - bash scripts/goza_zellij.sh → YAMLパースエラー（インデント修正）
  - 実機テスト結果: 起動中にユーザーがZellijをポチポチすると、混線が発生
    - 家老に軍師のプロンプトが注入される
    - 将軍に別のプロンプトが注入される
- Decisions / Assumptions:
  - ユーザー操作によるフォーカス変更が、write-charsの送信先を誤認識させる可能性がある。
  - 起動中はユーザー操作を禁止する警告を追加する必要がある。
- Next:
  1. ユーザー操作時の混線防止を実装
  2. 実機E2E検証（Zellij Pure Mode）
  3. WORKLOG更新
- Blockers: ユーザー操作時の混線問題
- Links: docs/REQS.md, docs/HANDOVER_2026-02-17_bootstrap_injection.md


## 2026-02-17 (ログ分析: pure zellij のアクティブペイン注入廃止)
- 背景:
  - ユーザー報告「うまくいっていない。アクティブペイン注入手法が悪い」を受け、`logs/inbox_watcher_*.log` を確認。
  - 主要観測:
    - `inotifywait not found` が多数混在（古い運用履歴のノイズ）。
    - `ashigaru2` で nudge→Escape→`/clear` の連鎖（`ESCALATION Phase 3`）が反復。
    - tmux/zellij 混在起動履歴により、送信対象前提が不安定化していた。
  - コード確認で、`scripts/goza_no_ma.sh` の pure zellij はフォーカス移動 + `write-chars` で「現在アクティブペイン」へ注入していた。
- 実装:
  - `scripts/goza_no_ma.sh`
    - `zellij_agent_pane_cmd` を変更し、各ペイン内で `tty_path="$(tty)"` を取得。
    - CLI起動後にそのペイン自身のTTYへ `bootstrap_line` を自律注入する方式へ変更。
    - `MAS_PURE_ZELLIJ_BOOTSTRAP_WAIT_{CLAUDE,CODEX,GEMINI,DEFAULT}` を導入。
    - `zellij_pure_attach_goza_room` から `zellij_bootstrap_pure_goza_background` 呼び出しを削除。
  - テスト追加: `tests/unit/test_goza_pure_bootstrap.bats`
- 検証:
  - `bash -n scripts/goza_no_ma.sh` → PASS
  - `bats tests/unit/test_goza_pure_bootstrap.bats tests/unit/test_mux_parity.bats tests/unit/test_zellij_bootstrap_delivery.bats` → 11/11 PASS
- 判断メモ:
  - pure zellij は「外部フォーカス制御で注入」より「各ペイン内の自己注入」のほうが構造的に安全。
  - watcherログには過去履歴が大量に残るため、今後の実機検証は起動ごとの専用ログファイル（run-id）分離が必要。

## 2026-02-21 (起動失敗: Waiting to run 対策)
- 背景:
  - ユーザー報告: 「エージェントが立ち上がっていない」。スクリーンショットで各ペインに `Waiting to run:` が表示。
- ログ確認:
  - `logs/inbox_watcher_*.log` は過去分を含みノイズが多いが、`ashigaru2` で unresponsive→`/clear` 循環履歴を確認。
  - 現象の直接原因は watcher より先に、zellij pane が「実行待ち」で停止していた点。
- 実装:
  - `scripts/goza_no_ma.sh`
    - zellij layout の pane 定義を `command="bash" start_suspended=false` に変更（UIレイアウト/純zellijレイアウト双方）。
    - pure zellij は既存の「アクティブペイン外部注入」を使わず、各ペインのTTY自律注入を維持。
- 検証:
  - `bash -n scripts/goza_no_ma.sh` → PASS
  - `bats tests/unit/test_goza_pure_bootstrap.bats tests/unit/test_mux_parity.bats tests/unit/test_zellij_bootstrap_delivery.bats` → 11/11 PASS
- 補足:
  - zellij 0.41系では command pane が待機表示になるケースがあり、`start_suspended=false` 明示で自動実行に寄せた。

## 2026-02-21 (起動後に初動プロンプトが入らない問題の修正)
- 背景:
  - ユーザー実機で「エージェントは起動するがプロンプトが入らない」事象を確認。
  - 旧実装は初動文面を pane 起動コマンドへ直埋めし、CLI起動タイミング依存で取りこぼしやすかった。
- 実装:
  - `scripts/goza_no_ma.sh`
    - `zellij_agent_pane_cmd` で初動文面を `queue/runtime/goza_bootstrap_<agent>.txt` に事前書き出し。
    - 各ペイン内で `tty_path` を取得し、`bootstrap_file` を読んで遅延リトライ送信する方式へ変更。
    - 送信結果を `queue/runtime/goza_bootstrap_<agent>.log` に記録（`bootstrap delivered` / `cli exited`）。
    - 待機時間デフォルトを引き上げ（codex 12s / claude 10s / gemini 18s）。
  - `tests/unit/test_goza_pure_bootstrap.bats` を更新（bootstrap_file経由を検証）。
- 検証:
  - `bash -n scripts/goza_no_ma.sh` → PASS
  - `bats tests/unit/test_goza_pure_bootstrap.bats tests/unit/test_mux_parity.bats tests/unit/test_zellij_bootstrap_delivery.bats` → 11/11 PASS
- 判断メモ:
  - フォーカス注入廃止に加え、文面直埋めを外すことで quoting/長文コマンド由来の不安定要因を削減。
  - 実機で問題が残る場合は `queue/runtime/goza_bootstrap_<agent>.log` を一次データとして追跡する。

## 2026-02-21 (上流再同期 + pure zellij `Waiting to run` 補正)
- Goal:
  - 上流 `yohey-w/multi-agent-shogun` 最新設計を再確認し、有効差分を反映する。
  - ユーザー報告「起動したがプロンプト未注入」に対し、`Waiting to run` 停止点を除去する。
- Upstream確認:
  - `git fetch upstream --prune`
  - 先頭確認: `upstream/main` = `cbad684`
  - 重点コミット: `b01d56b`（codex `--search`）, `300eafc`（command-layer `/clear` 抑止）
- Changes (files):
  - `scripts/goza_no_ma.sh`
    - `zellij_resume_pure_goza_panes_background` を追加。
    - pure zellij セッション作成後、各ペインへ Enter を順次送信して command pane を自動開始。
    - 初動本文は従来どおり各ペインTTY自己注入（アクティブペイン誤注入を再導入しない）。
  - `lib/cli_adapter.sh`
    - Codex起動コマンドに `--search` を追加（上流整合）。
  - `scripts/inbox_watcher.sh`
    - Codex escalation `/clear` 抑止を command-layer のみに限定。
      - `shogun|gunshi|karo|karoN|karo_gashira`
  - `tests/unit/test_goza_pure_bootstrap.bats`
    - `Waiting to run` 自動解除（Enter送信）検証を追加。
  - `tests/unit/test_cli_adapter.bats`
    - Codex期待値を `--search` 付きへ更新。
  - `tests/unit/test_send_wakeup.bats`
    - command-layer抑止と ashigaru継続回復の分岐テストを追加。
  - `docs/UPSTREAM_SYNC_2026-02-21.md`
    - 上流比較結果と採用/非採用を記録。
  - `docs/INDEX.md`, `docs/REQS.md`, `docs/EXECPLAN_2026-02-14_upstream_sync.md`, `docs/EXECPLAN_2026-02-17_zellij_bootstrap_stability.md`
    - 参照・要件・計画ログを更新。
- Commands + Results:
  - `bats tests/unit/test_goza_pure_bootstrap.bats tests/unit/test_cli_adapter.bats tests/unit/test_send_wakeup.bats`
    - 結果: `1..117` 全PASS
  - `bash -n scripts/goza_no_ma.sh lib/cli_adapter.sh scripts/inbox_watcher.sh shutsujin_departure.sh scripts/shutsujin_zellij.sh`
    - 結果: PASS
- Decisions / Assumptions:
  - zellij 0.41系の `start_suspended=false` 依存は不十分と判断し、実行開始トリガ（Enter送信）を補助実装。
  - command-layerの `/clear` 抑止は上流準拠、ashigaruは自己回復維持のため抑止しない。

## 2026-02-23 (注入未実行の再修正: attachブロッキング対策)
- Goal:
  - ユーザー報告「起動はするがプロンプト注入されない」を再修正。
- Root cause:
  - `scripts/goza_no_ma.sh` の `zellij_pure_attach_goza_room` で、`zellij --new-session-with-layout ... -s` がブロッキングのため、
    `zellij_resume_pure_goza_panes_background` 呼び出しが attach 終了後まで到達しなかった。
  - 結果として `queue/runtime/goza_bootstrap_*.log` が空のままになり、注入処理が未実行だった。
- Changes (files):
  - `scripts/goza_no_ma.sh`
    - `zellij_schedule_resume_after_attach` を追加。
    - attach実行前に resume をバックグラウンド予約する形へ変更。
  - `tests/unit/test_goza_pure_bootstrap.bats`
    - `attachブロッキング前にresume予約を行う` テストを追加。
  - `docs/REQS.md`
    - 本不具合向け受け入れ条件を追補。
- Commands + Results:
  - `bash -n scripts/goza_no_ma.sh` → PASS
  - `bats tests/unit/test_goza_pure_bootstrap.bats tests/unit/test_send_wakeup.bats` → `1..44` PASS
- Decision:
  - resume処理は attach 後ではなく「attach 開始前に予約」が必須。

## 2026-02-23 (未解決のため引き継ぎ文書を整備)
- Goal:
  - ユーザー報告「起動するがプロンプト注入されない」が継続しているため、次エージェントが即着手できる引き継ぎ資料を作成。
- Changes (files):
  - `docs/HANDOVER_2026-02-23_prompt_injection_open_issues.md` を新規作成。
  - `docs/INDEX.md` に handover 文書を登録。
  - `docs/REQS.md` に引き継ぎ整備要求を追補。
- Notes:
  - 実装はここで止め、未解決のまま課題を明示的に移譲。
  - 起動経路別（`goza_no_ma.sh` / `shutsujin_zellij.sh`）の切り分けをP0として指定。

### 2026-03-05 22:20 (JST)
- Goal: Docs/AGENTS確認後に再開し、上流最新取得 + Gemini/Zellij安定化を進める
- Changes (files):
  - `_upstream_reference/upstream_latest_2026-03-05_86ee80b/` — upstream/main (`86ee80b`) 参照worktreeを作成
  - `scripts/inbox_watcher.sh` — busy中 `/clear` 延期 + clear_commandの`clear_sent`判定へ変更
  - `scripts/shutsujin_zellij.sh` — bootstrap run-idログと `ready:<agent>` ACK確認/再送を追加
  - `tests/unit/test_send_wakeup.bats` — busy延期/auto-recovery抑止テストを追加
  - `tests/unit/test_zellij_bootstrap_delivery.bats` — run-idログ/ACK再送の静的テストを追加
  - `docs/UPSTREAM_SYNC_2026-03-05.md` — 上流同期内容を新規記録
  - `docs/INDEX.md` — 新規同期ドキュメントを登録、更新日を更新
  - `docs/REQS.md` — 2026-03-05追補を追加
- Commands + Results:
  - `git fetch upstream --prune` → 成功
  - `git log --oneline upstream/main --max-count=20` → 先頭 `86ee80b` を確認
  - `git worktree add _upstream_reference/upstream_latest_2026-03-05_86ee80b upstream/main` → 成功
  - `bash -lc "bats ..."` → 失敗（`Bash/Service/CreateInstance/E_ACCESSDENIED`）
  - 代替として `rg` ベースで追加実装とテスト記述を静的確認
- Decisions / Assumptions:
  - HTTPS直クローンは端末認証依存で不安定のため、`fetch + worktree` を「上流最新クローン相当」として採用。
  - 上流の watcher busy保護（`e598f70`）は本フォークの multi-CLI/zellij 実装へ優先導入する。
  - pure zellij (`goza_no_ma.sh`) へのACK再送拡張は次段に分離し、まず `shutsujin_zellij.sh` を可観測化する。
- Next:
  1. 実機で `bash scripts/shutsujin_zellij.sh` を実行し、`queue/runtime/bootstrap_run_*/delivery.log` の ACK検出を確認
  2. bash実行環境（WSL/Git Bash）を復旧後に bats を再実行
  3. pure zellij (`goza_no_ma.sh`) へ同等のACKログ機構を展開
- Blockers:
  - この端末では `bash` 実行が `E_ACCESSDENIED` で失敗し、Bats実行による動的検証が未実施
- Links: docs/UPSTREAM_SYNC_2026-03-05.md, docs/REQS.md

### 2026-03-06 00:10 (JST)
- Goal: Go指示を受け、pure zellij (`goza_no_ma.sh`) 側にも ACK監視と配信ログを追加
- Changes (files):
  - `scripts/goza_no_ma.sh` — run-idログ (`queue/runtime/goza_bootstrap_<run-id>.log`) 追加、`ready:<agent>` ACK確認と未検出時1回再送を追加
  - `tests/unit/test_goza_pure_bootstrap.bats` — pure zellij のログ/ACK再送の静的テストを追加
  - `docs/REQS.md` — 2026-03-06追補を追加
- Commands + Results:
  - `C:\Program Files\Git\bin\bash.exe -lc '... bash -n ...'` → 失敗（Win32 error 5）
  - `C:\Program Files\Git\bin\bash.exe -lc '... bats ...'` → 失敗（Win32 error 5）
  - `rg` による実装・テスト定義の静的確認 → 実施済み（ACK/再送/ログ実装を確認）
- Decisions / Assumptions:
  - bash実行不可のため、今回は静的検証を先行し、動的検証は実機環境で再実施する前提とした。
  - `goza_no_ma.sh` では既存のEnter送信によるresume処理は維持し、ACK未検出時のみ追加再送する最小変更を採用。
- Next:
  1. bash実行可能な環境で `bash -n` と `bats tests/unit/test_goza_pure_bootstrap.bats` を実行
  2. 実機で `bash scripts/goza_zellij.sh --template goza_room` を実行し、`queue/runtime/goza_bootstrap_*.log` を確認
  3. 問題なければコミット・push
- Blockers:
  - この端末では Git Bash 実行時に Win32 error 5 が発生し、動的検証が実施できない
- Links: docs/REQS.md

### 2026-03-06 16:50 (JST)
- Goal: 継続指示に基づき、PowerShell経由 `wsl` 検証と上流最新クローンの再確認を実施
- Changes (files):
  - `_upstream_reference/upstream_clone_2026-03-06_86ee80b/` — upstream/main (`86ee80b`) の shallow clone を追加
  - `docs/UPSTREAM_SYNC_2026-03-05.md` — 2026-03-06再確認手順（openssl fetch/clone）を追記
  - `docs/WORKLOG.md` — 本記録を追記
- Commands + Results:
  - `wsl bash -lc "cd /mnt/d/Git_WorkSpace/multi-agent-shognate/multi-agent-shognate && ..."` → 失敗（`Wsl/Service/CreateInstance/E_ACCESSDENIED`）
  - `wsl.exe --status` → 失敗（`Wsl/EnumerateDistros/Service/E_ACCESSDENIED`）
  - `git fetch upstream --prune` → 失敗（`schannel: SEC_E_NO_CREDENTIALS`）
  - `git -c http.sslbackend=openssl fetch upstream --prune` → 成功
  - `git log --oneline --max-count=20 upstream/main` / `git rev-parse --short upstream/main` → 先頭 `86ee80b` を確認
  - `git -c http.sslbackend=openssl clone --depth 1 https://github.com/yohey-w/multi-agent-shogun.git _upstream_reference/upstream_clone_2026-03-06_86ee80b` → 成功
  - `git -C D:\Git_WorkSpace\multi-agent-shognate\multi-agent-shognate\_upstream_reference\upstream_clone_2026-03-06_86ee80b rev-parse --short HEAD` → `86ee80b`
- Decisions / Assumptions:
  - この実行環境では `wsl` サービスにアクセスできず、動的検証（`bash -n` / `bats`）は継続不能と判断。
  - 上流取得は当面 `git -c http.sslbackend=openssl ...` を標準手順として扱う。
- Next:
  1. `wsl` サービスアクセス可能な端末で `bash -n` と `bats` を再実行
  2. 実機で `bash scripts/goza_zellij.sh --template goza_room` を実行し、`queue/runtime/goza_bootstrap_*.log` の ACK記録を確認
- Blockers:
  - Codex実行環境側の `Wsl/*/E_ACCESSDENIED` により `wsl` 実行不可
- Links: docs/UPSTREAM_SYNC_2026-03-05.md

### 2026-03-06 18:35 (JST)
- Goal: 上流最新を zellij / Gemini CLI に限定反映し、pure zellij の未注入問題を減らす
- Changes (files):
  - `scripts/goza_no_ma.sh` — pure zellij を CLI引数渡しから transcript + 明示送信方式へ変更、Gemini preflight を追加
  - `scripts/shutsujin_zellij.sh` — Gemini trust/high-demand 自動処理を追加
  - `scripts/inbox_watcher.sh` — Claude 初期 idle flag 作成を追加（上流 false-busy deadlock 緩和）
  - `tests/unit/test_goza_pure_bootstrap.bats` — pure zellij の transcript / Gemini preflight を検証する静的テストへ更新
  - `tests/unit/test_zellij_bootstrap_delivery.bats` — zellij Gemini preflight テストを追加
  - `docs/REQS.md` — 2026-03-06 追補（zellij / Gemini 限定スコープ）を追加
  - `docs/UPSTREAM_SYNC_2026-03-06_ZELLIJ_GEMINI.md` — 上流同期ノートを新規追加
  - `docs/EXECPLAN_2026-03-06_zellij_gemini_upstream_sync.md` — 実行計画を新規追加
  - `docs/INDEX.md` — 新規Docsを登録
- Commands + Results:
  - `git rev-parse --short upstream/main` → `86ee80b`
  - `bash -n scripts/goza_no_ma.sh scripts/shutsujin_zellij.sh scripts/inbox_watcher.sh lib/cli_adapter.sh` → PASS
  - `bats tests/unit/test_goza_pure_bootstrap.bats tests/unit/test_zellij_bootstrap_delivery.bats tests/unit/test_send_wakeup.bats` → `1..59` PASS
  - `bash scripts/goza_no_ma.sh -s --no-attach --mux zellij --ui zellij --template goza_room` → PASS（`goza-no-ma-ui` 背景生成）
  - `bash scripts/shutsujin_zellij.sh -s` → FAIL（`snap-confine ... cap_dac_override not found`）
- Decisions / Assumptions:
  - pure zellij では pane別 capture API の不足を transcript ファイルで補う。
  - Gemini preflight は zellij bootstrap 層で吸収し、CLIコマンド自体は `gemini --yolo` のまま保つ。
  - `shutsujin_zellij.sh -s` の失敗は、この実行環境の snap 版 zellij 制約と判断し、コード問題とは切り分ける。
- Next:
  1. ユーザー実機で `bash scripts/goza_no_ma.sh --mux zellij --ui zellij --template goza_room` を実行し、`queue/runtime/pure_zellij_*.log` を確認
  2. 実機 zellij が snap 版なら、非 snap 版（cargo / apt / release binary）での再確認を行う
  3. 必要なら `shutsujin_zellij.sh` も transcript 化して Gemini 判定基盤を共通化する
- Links: docs/UPSTREAM_SYNC_2026-03-06_ZELLIJ_GEMINI.md, docs/EXECPLAN_2026-03-06_zellij_gemini_upstream_sync.md

### 2026-03-07 00:25 (JST)
- Goal: 上流の内部構造変化を踏まえ、「上流基盤へ戻して zellij / Gemini だけを載せ直す」再出発の第一段を開始
- Changes (files):
  - `_trash/restart_2026-03-07_core/` — 置換前の基盤ファイルを退避
  - `AGENTS.md` — 上流最新版へ更新
  - `lib/agent_status.sh` — 上流最新版を新規導入
  - `scripts/inbox_watcher.sh` — `lib/agent_status.sh` を読むよう補正し、tmux busy 判定を共有化
  - `docs/REQS.md` — 2026-03-07 追補（再出発方針）を追加
  - `docs/UPSTREAM_SYNC_2026-03-07_RESTART.md` — 上流構造変化と再出発方針を新規追加
  - `docs/EXECPLAN_2026-03-07_upstream_restart_zellij_gemini.md` — 再出発ExecPlanを新規追加
  - `docs/INDEX.md` — 新規Docsを登録
- Commands + Results:
  - `test -f _trash/restart_2026-03-07_core/AGENTS.md.before_upstream && test -f lib/agent_status.sh && echo OK` → `OK`
  - `bash -n scripts/inbox_watcher.sh lib/agent_status.sh` → PASS
  - `bats tests/unit/test_send_wakeup.bats` → `1..42` PASS
- Decisions / Assumptions:
  - いきなり `shutsujin_departure.sh` 全置換は危険なため、まず runtime 安全性へ効く `AGENTS.md` / `agent_status` / watcher から戻す。
  - `README_ja.md` と `shutsujin_departure.sh` の全面同期は次段へ送る。
  - 置換前ファイルは削除せず `_trash/restart_2026-03-07_core/` に保管する。
- Next:
  1. `shutsujin_departure.sh` を upstream 基盤へ寄せ、`MAS_MULTIPLEXER=zellij` 分岐だけを最小追加する
  2. `lib/cli_adapter.sh` を upstream 基盤ベースで再整理し、`gemini` を正式に載せる
  3. `scripts/build_instructions.sh` を upstream ベースへ寄せ、`gemini` 生成を整理する
- Links: docs/UPSTREAM_SYNC_2026-03-07_RESTART.md, docs/EXECPLAN_2026-03-07_upstream_restart_zellij_gemini.md

### 2026-03-07 00:35 (JST)
- Goal: 上流完全クローンを基準に、退避先 `Waste/` を正式化し、`cli_adapter` / `build_instructions` を上流骨格へ寄せる
- Changes (files):
  - `Waste/README.md` — 退避方針を記録
  - `Waste/restart_2026-03-07_core/*.before_upstream` — 置換前の基盤スナップショットを tracked 化
  - `.gitignore` — `Waste/` の必要最小限の追跡を許可
  - `docs/REQS.md` — 上流完全クローン基準 + Waste退避の要求を追加
  - `docs/INDEX.md` — 新規同期ノートを登録
  - `docs/UPSTREAM_SYNC_2026-03-07_FULL_BASELINE.md` — 上流完全クローン基準の同期方針を追加
  - `docs/EXECPLAN_2026-03-07_upstream_restart_zellij_gemini.md` — full clone / Waste 方針へ更新
  - `lib/cli_adapter.sh` — upstream骨格へ差し替えた上で gemini/localapi、role共通MD、CLIフォールバックAPIを再導入
  - `scripts/build_instructions.sh` — upstream版へ差し替えた上で gemini/localapi generated instructions を再導入
  - `AGENTS.md`, `.github/copilot-instructions.md`, `agents/default/system.md` — build再生成で更新
- Commands + Results:
  - `git -C _upstream_reference/original_full_2026-03-07 rev-parse --short HEAD` → `86ee80b`
  - `bash -n lib/cli_adapter.sh scripts/build_instructions.sh first_setup.sh shutsujin_departure.sh scripts/shutsujin_zellij.sh scripts/goza_no_ma.sh` → PASS
  - `bats tests/unit/test_cli_adapter.bats` → `1..74` PASS
  - `bash scripts/build_instructions.sh` → PASS（`instructions/generated/gemini-*.md` / `localapi-*.md` 再生成）
  - `bats tests/unit/test_send_wakeup.bats tests/unit/test_zellij_bootstrap_delivery.bats tests/unit/test_mux_parity.bats` → `1..58` PASS
  - `bash shutsujin_departure.sh -h` / `bash scripts/goza_zellij.sh -h` / `bash scripts/shutsujin_zellij.sh -h` → PASS
- Decisions / Assumptions:
  - `shutsujin_departure.sh` は既に `zellij` 分岐を持つため、この段では全面置換せず据え置いた。
  - `cli_adapter` は upstream の動的モデル系関数を維持しつつ、このフォーク固有の `gemini/localapi` と `resolve_cli_type_for_agent` 系APIを上乗せした。
  - `_trash/` は非追跡のままとし、再出発時点の重要スナップショットだけを `Waste/` に tracked 化した。
- Next:
  1. `first_setup.sh` を upstream 基準へ再確認し、zellij 導入案内を実環境向けに補正する
  2. `shutsujin_departure.sh` の tmux 本流を upstream 側へさらに寄せる
  3. `README.md` / `README_ja.md` を上流最新版説明へ寄せた上で zellij / Gemini 追記に整理する
- Links: docs/UPSTREAM_SYNC_2026-03-07_FULL_BASELINE.md, docs/EXECPLAN_2026-03-07_upstream_restart_zellij_gemini.md

### 2026-03-07 00:41 (JST)
- Goal: `first_setup.sh` の zellij / Gemini / Codex 導入案内を実運用に寄せる
- Changes (files):
  - `first_setup.sh` — zellij の Ubuntu/WSL 導入案内を現実的な手段へ修正し、Codex/Gemini の任意CLIチェックを追加
  - `docs/WORKLOG.md` — 本記録を追記
- Commands + Results:
  - `bash -n first_setup.sh && bash -n lib/cli_adapter.sh scripts/build_instructions.sh` → PASS
  - `rg -n "STEP 5\.5|Codex CLI: optional|Gemini CLI: optional|cargo install --locked zellij" first_setup.sh` → 期待行を確認
- Decisions / Assumptions:
  - Codex / Gemini は認証や配布形態が環境依存のため、自動インストールではなく「存在確認 + 導入案内」に留めた。
  - zellij は apt 未提供の環境があるため、WSL向け案内を `cargo` / release binary ベースへ変更した。
- Next:
  1. `README.md` / `README_ja.md` を upstream 説明へ寄せつつ zellij / Gemini の使い方に絞って整理する
  2. `shutsujin_departure.sh` の tmux 本流を upstream へさらに寄せる
- Links: first_setup.sh

### 2026-03-07 13:08 (JST)
- Goal: `bash scripts/goza_zellij.sh` で Codex / Claude が起動せず初回注入も入らない問題に対し、既定の zellij 導線を pure zellij から安定経路へ切り替える
- Changes (files):
  - `scripts/goza_zellij.sh` — 既定導線を `--mux tmux --ui zellij` へ変更
  - `scripts/goza_zellij_pure.sh` — pure zellij 導線を experimental コマンドとして新設
  - `tests/unit/test_goza_wrapper_modes.bats` — wrapper責務の回帰テストを追加
  - `README.md` — stable / experimental の運用コマンドを整理
  - `docs/REQS.md` — 2026-03-07追補（zellij運用コマンドの安定経路切替）を追加
  - `docs/EXECPLAN_2026-03-07_upstream_restart_zellij_gemini.md` — 本判断を Progress / Decision Log に追記
- Commands + Results:
  - `bash -n scripts/goza_zellij.sh scripts/goza_zellij_pure.sh scripts/goza_hybrid.sh scripts/goza_tmux.sh scripts/goza_no_ma.sh` → PASS
  - `bash scripts/goza_zellij.sh -h` / `bash scripts/goza_zellij_pure.sh -h` → PASS
  - `bats tests/unit/test_goza_wrapper_modes.bats tests/unit/test_goza_pure_bootstrap.bats tests/unit/test_zellij_bootstrap_delivery.bats tests/unit/test_mux_parity.bats` → `1..25` PASS
  - `bash scripts/goza_zellij.sh -s --no-attach` → この実行環境では `tmux create window failed: fork failed: Permission denied` で実機起動検証は不可（sandbox制約と判断）
- Decisions / Assumptions:
  - pure zellij の bootstrap は `goza_bootstrap_*.log` 上で `pane resumed agent=shogun` 以降が止まり、未収束のため既定導線から外した。
  - ユーザー向けの `goza_zellij.sh` は安定運用を優先し、zellij UI + tmux backend を既定とする。
  - pure zellij は削除せず `goza_zellij_pure.sh` として残し、別系統で継続検証できるようにする。
- Next:
  1. ユーザー実機で `bash scripts/goza_zellij.sh -s` → `bash scripts/goza_zellij.sh` を再確認する
  2. pure zellij が必要なら `bash scripts/goza_zellij_pure.sh` を別途デバッグする
  3. 次段で `README_ja.md` と `shutsujin_departure.sh` の上流寄せを続行する
- Links: README.md, scripts/goza_zellij.sh, scripts/goza_zellij_pure.sh, docs/REQS.md

### 2026-03-07 13:18 (JST)
- Goal: 画像の `Waiting to run` 再発に対し、古い pure zellij 呼び出しでも stable 経路へ逃がすガードを追加する
- Changes (files):
  - `scripts/goza_no_ma.sh` — `MAS_ENABLE_PURE_ZELLIJ` opt-in が無い限り pure zellij `goza_room` を `tmux backend + zellij UI` へフォールバック
  - `scripts/goza_zellij_pure.sh` — pure zellij 実験コマンドとして `MAS_ENABLE_PURE_ZELLIJ=1` を明示設定
  - `tests/unit/test_goza_wrapper_modes.bats` — fallback guard の回帰テストを追加
  - `README.md` / `docs/REQS.md` — 明示opt-in制へ更新
- Commands + Results:
  - `bash -n scripts/goza_zellij.sh scripts/goza_zellij_pure.sh scripts/goza_no_ma.sh` → PASS
  - `bats tests/unit/test_goza_wrapper_modes.bats` → `1..3` PASS
  - `rg -n "MAS_ENABLE_PURE_ZELLIJ|フォールバック" scripts/goza_no_ma.sh README.md` → 期待行を確認
- Decisions / Assumptions:
  - 画像で出ている `Waiting to run` は pure zellij command pane 起因と判断し、ユーザー導線からは完全に外す。
  - pure zellij は `goza_zellij_pure.sh` に閉じ込め、通常の `goza_zellij.sh` では到達不能にする。
- Next:
  1. ユーザー実機で `bash scripts/goza_zellij.sh` を再実行し、タイトルが `tmux-core` になることを確認する
  2. その上で Codex / Claude / Gemini の起動内容を capture-pane で確認する
- Links: scripts/goza_no_ma.sh, scripts/goza_zellij_pure.sh

### 2026-03-07 13:40 (JST)
- Goal: pure zellij を native に戻し、`Waiting to run` を前提にしない shell pane 起動へ切り替える。あわせて Codex updater で bootstrap が止まる問題を抑止する。
- Changes (files):
  - `scripts/goza_no_ma.sh` — pure zellij の pane を command pane ではなく shell pane にし、pane ごとに `launch command` を send-line して CLI を起動する方式へ変更。Gemini に加えて Codex preflight を追加。
  - `lib/cli_adapter.sh` — Codex 起動コマンドに `NO_UPDATE_NOTIFIER=1` を付与。
  - `scripts/shutsujin_zellij.sh` — session-per-agent の Codex preflight を追加。
  - `shutsujin_departure.sh` — tmux 経路の Codex update prompt 自動スキップを追加。
  - `tests/unit/test_cli_adapter.bats` — Codex command 期待値を更新。
  - `tests/unit/test_goza_pure_bootstrap.bats` — pure zellij を shell pane launch 前提へ更新、Codex preflight 検証を追加。
  - `tests/unit/test_zellij_bootstrap_delivery.bats` — zellij/tmux の Codex preflight 検証を追加。
  - `docs/REQS.md` — pure zellij shell pane 起動化 + Codex updater抑止の要求を追加。
- Commands + Results:
  - `bash -n lib/cli_adapter.sh scripts/goza_no_ma.sh scripts/shutsujin_zellij.sh shutsujin_departure.sh scripts/goza_zellij_pure.sh` → PASS
  - `bats tests/unit/test_cli_adapter.bats tests/unit/test_goza_wrapper_modes.bats tests/unit/test_goza_pure_bootstrap.bats tests/unit/test_zellij_bootstrap_delivery.bats` → `1..97` PASS
- Decisions / Assumptions:
  - pure zellij の本質的な不安定さは `command pane` 起因と判断し、通常 shell pane + send-line launch へ設計変更した。
  - Codex updater は設定で完全無効化できる確証がないため、`NO_UPDATE_NOTIFIER=1` と preflight UI処理の二段で抑止する。
- Next:
  1. ユーザー実機で `bash scripts/goza_zellij_pure.sh` を再実行し、`Waiting to run` が消えたか確認する。
  2. その後 `ready:` ACK と bootstrap 送信ログを確認する。
- Links: scripts/goza_no_ma.sh, lib/cli_adapter.sh, shutsujin_departure.sh, scripts/shutsujin_zellij.sh

### 2026-03-07 18:35 (JST)
- Goal: pure zellij の「アクティブペインへ平文注入」方式をやめ、元リポジトリの file-based communication 原則へ寄せた dedicated bootstrap へ置き換える。
- Changes (files):
  - `scripts/zellij_agent_bootstrap.sh` — 各 pane が `AGENT_ID` 固定で起動し、agent別 bootstrap file を読み、CLI を transcript 付きで直接起動する専用 runner を追加。
  - `lib/cli_adapter.sh` — `build_cli_command_with_startup_prompt()` を追加し、Codex/Claude は positional prompt、Gemini は `-i` で初回命令を起動引数へ載せるようにした。
  - `scripts/goza_no_ma.sh` — pure zellij のレイアウトを dedicated runner 起動へ変更し、`prepare_pure_zellij_bootstrap_files()` で agent別 bootstrap file を生成するよう更新。外側の focus 巡回 bootstrap は pure zellij attach 経路から外した。
  - `tests/unit/test_cli_adapter.bats` — startup prompt 付きCLI command 生成のテストを追加。
  - `tests/unit/test_goza_pure_bootstrap.bats` — pure zellij が runner + bootstrap file 前提であることを確認するよう更新。
  - `docs/REQS.md` / `docs/EXECPLAN_2026-03-07_upstream_restart_zellij_gemini.md` — dedicated bootstrap 方針を追記。
- Commands + Results:
  - `chmod +x scripts/zellij_agent_bootstrap.sh && bash -n scripts/goza_no_ma.sh scripts/zellij_agent_bootstrap.sh lib/cli_adapter.sh` → PASS
  - `bats tests/unit/test_cli_adapter.bats tests/unit/test_goza_pure_bootstrap.bats tests/unit/test_goza_wrapper_modes.bats` → `1..87` PASS
- Decisions / Assumptions:
  - upstream の通信原則どおり、本文は file-based に寄せる。`zellij action write-chars` で本文を流す設計は pure zellij では混線しやすく、役職取り違えを再現したため不採用。
  - Gemini CLI の初回命令は `-i` を使って interactive startup prompt に載せる前提で実装した。実機で trust/high-demand が残る場合は、次段で pane 内 runner 側へ preflight 自動化を追加する。
- Next:
  1. ユーザー実機で `bash scripts/goza_zellij_pure.sh -s` → `bash scripts/goza_zellij_pure.sh` を再実行し、`Waiting to run` ではなく各CLI本体が pane 起動するか確認する。
  2. `queue/runtime/pure_zellij_goza-no-ma-ui_*.log` と `*.meta.log` を見て、Codex/Gemini の初回挙動を agent単位で切り分ける。
  3. 必要なら Gemini の trust/high-demand 処理も runner 内へ閉じて自動化する。
- Links: scripts/zellij_agent_bootstrap.sh, scripts/goza_no_ma.sh, lib/cli_adapter.sh

### 2026-03-07 18:49 (JST)
- Goal: pure zellij の足軽ペインが細すぎるため、右端グリッドの横幅を拡張する。
- Changes (files):
  - `scripts/goza_no_ma.sh` — pure zellij `goza_room` の列配分を `46/32/22` から `42/28/30` へ変更し、足軽グリッドを横に広げた。
- Commands + Results:
  - `bash -n scripts/goza_no_ma.sh` → PASS
  - `bats tests/unit/test_goza_pure_bootstrap.bats` → `1..7` PASS
- Decisions / Assumptions:
  - 将軍列は最優先で大きく保ちつつ、家老列を少し削って足軽列を拡張した。
  - 2x2 の足軽配置自体は維持し、今回は列比率だけ変更した。
- Next:
  1. ユーザー実機で `bash scripts/goza_zellij_pure.sh` を再起動し、足軽ペインの可読性を再確認する。
  2. まだ縦長なら、次は右端列の中で `2列固定` から `1列+タブ切替` など別構成を検討する。
- Links: scripts/goza_no_ma.sh

### 2026-03-07 19:35 (JST)
- Goal: `gunshi` を設定CUIへ追加し、`Codex/Gemini` の思考モードを `config/settings.yaml` から永続化して起動時へ反映する。
- Changes (files):
  - `scripts/configure_agents.sh` — `gunshi` を設定対象へ追加し、`Codex reasoning_effort`、`Gemini thinking_level / thinking_budget` を role 単位で保存できるよう更新。
  - `lib/cli_adapter.sh` — `reasoning_effort` / `thinking_level` / `thinking_budget` の読み出しを追加し、`Codex` では `-c model_reasoning_effort='...'`、`Gemini` では `mas-<agent>` alias を用いるよう更新。
  - `scripts/sync_gemini_settings.py` — workspace `.gemini/settings.json` の `modelConfigs.customAliases` を `config/settings.yaml` から自動生成する同期スクリプトを追加。
  - `shutsujin_departure.sh` / `scripts/shutsujin_zellij.sh` / `scripts/goza_no_ma.sh` — 起動前に Gemini workspace settings を同期する処理を追加。
  - `tests/unit/test_cli_adapter.bats` — `Codex reasoning_effort` と `Gemini alias` のテストを追加。
  - `tests/unit/test_sync_gemini_settings.bats` — `.gemini/settings.json` 生成と丸め warning のテストを追加。
  - `docs/REQS.md` / `docs/EXECPLAN_2026-03-07_upstream_restart_zellij_gemini.md` — 今回の設定仕様を追記。
- Commands + Results:
  - `bash -n scripts/configure_agents.sh lib/cli_adapter.sh scripts/shutsujin_zellij.sh shutsujin_departure.sh scripts/goza_no_ma.sh` → PASS
  - `python3 -m py_compile scripts/sync_gemini_settings.py scripts/localapi_repl.py` → PASS
  - `bats tests/unit/test_cli_adapter.bats tests/unit/test_sync_gemini_settings.bats` → `1..85` PASS
  - `printf '\n%.0s' {1..40} | bash scripts/configure_agents.sh` → `config/settings.yaml` が壊れず更新されることを確認後、元のローカル設定へ復元。
  - `python3 scripts/sync_gemini_settings.py` → `.gemini/settings.json` と `queue/runtime/gemini_aliases.tsv` を生成できることを確認。
- Decisions / Assumptions:
  - `Codex` は現行 CLI の `-c key=value` を用い、`reasoning_effort` は `auto|none|low|medium|high` に限定する。
  - `Gemini 3` は `thinking_level`、`Gemini 2.5` は `thinking_budget` に分ける。`auto` のまま思考設定が入った場合は、`Gemini 3` は `gemini-3-pro-preview`、`2.5` 予算系は `gemini-2.5-pro` を基底モデルとして alias 生成する。
  - `gemini-3-pro-preview` + `minimal/medium`、`gemini-2.5-pro` + `thinkingBudget=0` は公式仕様に合わせて安全側へ丸め、warning を summary に残す。
- Next:
  1. 実機で `configure_agents.sh` を使い、`gunshi=codex(high)`、`ashigaru1=gemini(gemini-3-flash-preview/minimal)` などの構成を保存して再起動し、pane 表示と初動が維持されるか確認する。
  2. 必要なら pane 見出しへ `Codex(high)` / `Gemini(low)` のような簡易表示を追加する。
- Links: scripts/configure_agents.sh, lib/cli_adapter.sh, scripts/sync_gemini_settings.py

### 2026-03-07 20:05 (JST)
- Goal: `shogun` の未設定デフォルトを、CLIごとに最小思考へ寄せる。
- Changes (files):
  - `lib/cli_adapter.sh` — `shogun` 向けの既定値を追加。`Claude` は `MAX_THINKING_TOKENS=0`、`Codex` は `reasoning_effort=none`、`Gemini` はモデルに応じて `low / minimal / 0 / -1` の最小側へ寄せる。
  - `scripts/sync_gemini_settings.py` — `shogun` が `Gemini` で thinking 未設定のとき、workspace alias に既定最小思考を反映するよう更新。
  - `scripts/configure_agents.sh` — 設定UIでも `shogun` の既定選択を最小思考寄りに変更。
  - `tests/unit/test_cli_adapter.bats` / `tests/unit/test_sync_gemini_settings.bats` — `shogun` 既定挙動の回帰テストを追加。
  - `docs/REQS.md` — `shogun` 最小思考既定の受け入れ条件を追加。
- Commands + Results:
  - `bash -n scripts/configure_agents.sh lib/cli_adapter.sh scripts/sync_gemini_settings.py` → PASS
  - `bats tests/unit/test_cli_adapter.bats tests/unit/test_sync_gemini_settings.bats` → `1..90` PASS
- Decisions / Assumptions:
  - `Gemini 2.5 Pro` は完全OFFできないため、`shogun` 既定でも `dynamic(-1)` を下限扱いとする。
  - `Gemini auto` の `shogun` 既定は `gemini-3-pro-preview + LOW` 相当の alias を生成する。これは「auto のまま無制御」よりも意図が明確で、思考を抑えたいというユーザー要求に近いため。
- Next:
  1. 実機で `shogun=claude/codex/gemini` を切り替え、未設定時に pane 表示と挙動が最小思考へ寄るか確認する。
  2. 必要なら `README.md` に `shogun` 既定値と `Kilo CLI` 方針を追記する。
- Links: lib/cli_adapter.sh, scripts/sync_gemini_settings.py, scripts/configure_agents.sh

### 2026-03-07 20:55 (JST)
- Goal: `OpenCode` / `Kilo` を local-AI 向け CLI として正式対応し、`config/settings.yaml` から role 設定と shared provider 設定を保存できるようにする。
- Changes (files):
  - `lib/cli_adapter.sh` — `opencode` / `kilo` を許可CLIへ追加し、`--model provider/model`、`--prompt`、指示書解決、可用性判定、表示名を実装。
  - `scripts/build_instructions.sh` / `scripts/ensure_generated_instructions.sh` — `opencode-*` / `kilo-*` / `gunshi` 生成対象を追加。
  - `instructions/cli_specific/opencode_tools.md` / `instructions/cli_specific/kilo_tools.md` — CLI固有の運用メモを追加。
  - `scripts/sync_opencode_config.py` — `config/settings.yaml` の `cli.opencode_like` から project-level `opencode.json` と `queue/runtime/opencode_like_config_summary.tsv` を生成する同期スクリプトを追加。
  - `scripts/configure_agents.sh` — `opencode` / `kilo` を CUI 選択肢へ追加し、`provider/base_url/api_key_env/instructions` を `cli.opencode_like` として保存できるよう更新。空フィールド崩れで `Gemini thinking_level` が誤って `reasoning_effort` に入る不具合も修正。
  - `shutsujin_departure.sh` / `scripts/shutsujin_zellij.sh` / `scripts/goza_no_ma.sh` — 起動前に `sync_opencode_config.py` を呼ぶよう更新。
  - `first_setup.sh` — `OpenCode` / `Kilo` の存在確認と導入案内を追加。
  - `tests/unit/test_cli_adapter.bats` / `tests/unit/test_sync_opencode_config.bats` / `tests/unit/test_configure_agents.bats` — CLI 対応、`opencode.json` 生成、CUI 保存の回帰テストを追加。
  - `docs/REQS.md` / `docs/EXECPLAN_2026-03-07_upstream_restart_zellij_gemini.md` — 今回の仕様と受け入れ条件を追記。
- Commands + Results:
  - `bash -n scripts/configure_agents.sh lib/cli_adapter.sh scripts/build_instructions.sh scripts/ensure_generated_instructions.sh scripts/goza_no_ma.sh scripts/shutsujin_zellij.sh shutsujin_departure.sh first_setup.sh` → PASS
  - `python3 -m py_compile scripts/sync_opencode_config.py` → PASS
  - `bash scripts/build_instructions.sh` → PASS
  - `bats tests/unit/test_cli_adapter.bats tests/unit/test_sync_gemini_settings.bats tests/unit/test_sync_opencode_config.bats tests/unit/test_configure_agents.bats tests/unit/test_goza_wrapper_modes.bats tests/unit/test_goza_pure_bootstrap.bats tests/unit/test_zellij_bootstrap_delivery.bats` → `1..127` PASS
  - `bash scripts/configure_agents.sh` に対して入力を流し、`cli.opencode_like` 保存と `opencode.json` 生成を手動確認 → PASS
- Decisions / Assumptions:
  - `OpenCode` と `Kilo` は upstream 実装系が同じため、project provider 設定は `opencode.json` に一本化する。
  - local provider は role ごとでなく workspace 共有設定とし、role ごとの差は `type/model` だけに絞る。
  - `OpenCode/Kilo` の思考制御は provider/model 依存が強いため、この段では抽象 thinking API は持たず、provider config と model 指定までを正式対応とする。
- Next:
  1. `README.md` / `README_ja.md` に `OpenCode/Kilo` の設定例と local provider 例（Ollama/LM Studio/OpenAI-compatible）を追記する。
  2. 実機で `opencode` / `kilo` 実体が入った状態で `goza_zellij_pure.sh` / `goza_zellij.sh` の起動確認を行う。
  3. 必要なら `Kilo/OpenCode` 用に provider別プリセット（`ollama`, `lmstudio`, `openai-compatible`）を CUI へ追加する。
- Links: lib/cli_adapter.sh, scripts/configure_agents.sh, scripts/sync_opencode_config.py, tests/unit/test_configure_agents.bats

### 2026-03-07 21:05 (JST)
- Goal: OpenCode/Kilo 対応 checkpoint の commit/push を完了する。
- Commands + Results:
  - `git commit -m "codex: opencodeとkiloのCLI対応を追加"` → PASS (`e6cace8`)
  - `git push -u origin codex/auto` → FAIL (`fatal: could not read Username for 'https://github.com': No such device or address`)
- Decisions / Assumptions:
  - 実装・テストは完了しているため、次の停止理由は認証のみ。
  - 作業差分は commit 済みなので、次回はユーザーの認証後に同じ push コマンドを再実行すればよい。
- Links: e6cace8

### 2026-03-09 15:20 (JST)
- Goal: `OpenCode/Kilo` の local provider として `Ollama` / `LM Studio` を明示対応し、設定UIと同期スクリプトで既定URL補完を持たせる。
- Changes (files):
  - `scripts/configure_agents.sh` — `provider` を free-form だけでなく `ollama / lmstudio / openai-compatible / custom` から選べるよう更新し、`base_url` / `api_key_env` / `instructions` は空入力を許す optional prompt に変更。
  - `scripts/sync_opencode_config.py` — `ollama` は `http://127.0.0.1:11434/v1`、`lmstudio` / `openai-compatible` は `http://127.0.0.1:1234/v1` を既定補完するよう更新。
  - `first_setup.sh` — `ollama` の存在確認と、`LM Studio` は GUI 側 local server を有効化する運用案内を追加。
  - `tests/unit/test_sync_opencode_config.bats` — `ollama` / `lmstudio` の base_url 既定補完テストを追加。
  - `docs/REQS.md` / `docs/EXECPLAN_2026-03-07_upstream_restart_zellij_gemini.md` — local provider 明示対応を追記。
- Commands + Results:
  - `bash -n scripts/configure_agents.sh scripts/sync_opencode_config.py first_setup.sh` → PASS
  - `python3 -m py_compile scripts/sync_opencode_config.py` → PASS
  - `bats tests/unit/test_sync_opencode_config.bats tests/unit/test_configure_agents.bats` → `1..5` PASS
  - `bash scripts/build_instructions.sh` → PASS
  - `bats tests/unit/test_cli_adapter.bats tests/unit/test_sync_opencode_config.bats tests/unit/test_configure_agents.bats` → `1..104` PASS
- Decisions / Assumptions:
  - `LM Studio` は WSL からの安定自動検出が難しいため、CLI ではなく OpenAI-compatible local server 前提の対応に留める。
  - `Ollama` / `LM Studio` は provider プリセットとして固定し、詳細 provider 拡張は `custom` へ逃がす。
- Next:
  1. `README.md` / `README_ja.md` に `OpenCode/Kilo + Ollama/LM Studio` の設定例を追記する。
  2. 実機で `opencode` / `kilo` 本体と `ollama` / `LM Studio local server` を起動し、`goza_zellij_pure.sh` で実起動確認する。
- Links: scripts/configure_agents.sh, scripts/sync_opencode_config.py, first_setup.sh, tests/unit/test_sync_opencode_config.bats

### 2026-03-09 15:24 (JST)
- Goal: `Ollama/LM Studio` 対応 checkpoint の commit/push を完了する。
- Commands + Results:
  - `git commit -m "codex: ollamaとlmstudioのprovider対応を追加"` → PASS (`7049b39`)
  - `git push -u origin codex/auto` → FAIL (`fatal: could not read Username for 'https://github.com': No such device or address`)
- Decisions / Assumptions:
  - 実装・テストは完了しているため、停止理由は認証のみ。
  - 次回は認証後に同じ push コマンドを再実行すればよい。
- Links: 7049b39

### 2026-03-09 15:34 (JST)
- Goal: 実機起動前の役職CLI構成を、ユーザー指定どおり `shogun=gemini / karo=codex / gunshi=gemini / ashigaru1-2=codex / ashigaru3-4=gemini` に合わせる。
- Changes (files):
  - `config/settings.yaml` — active ashigaru 4名を維持したまま、各役職の `type` をユーザー指定構成へ更新。
- Commands + Results:
  - `python3 scripts/sync_gemini_settings.py` → PASS
  - `cat config/settings.yaml` → 指定どおりの role 割当を確認
  - `cat queue/runtime/gemini_aliases.tsv` → `shogun` の Gemini alias が生成されることを確認
- Decisions / Assumptions:
  - `cli.default` は未指定役職用のまま `gemini` を維持し、今回の起動対象は全役職を個別指定で固定した。
  - `gunshi` / `ashigaru3` / `ashigaru4` は thinking 未指定のため、Gemini alias は不要として扱う。
- Next:
  1. 実機で `bash scripts/goza_zellij_pure.sh -s && bash scripts/goza_zellij_pure.sh` または stable 側 `bash scripts/goza_zellij.sh -s && bash scripts/goza_zellij.sh` を実行する。
  2. 起動後に `cat queue/runtime/agent_cli.tsv` で role ごとの CLI 割当を確認する。
- Links: config/settings.yaml, queue/runtime/gemini_aliases.tsv

### 2026-03-09 16:05 (JST)
- Goal: `shogun` の Gemini pane で `mas-shogun` alias 表示と初動停滞が出る問題を、runtime ログに基づいて切り分けて修正する。
- Findings:
  - `queue/runtime/pure_zellij_goza-no-ma-ui_shogun.log` では `model mas-shogun` のまま長時間 spinner が継続していた。
  - `queue/runtime/pure_zellij_goza-no-ma-ui_gunshi.log` は `Auto (Gemini 3)` 表示で通常応答していた。
  - 原因は `shogun` にだけ適用していた Gemini implicit thinking alias (`LOW`) で、`config/settings.yaml` に明示 thinking が無くても `mas-shogun` alias を強制していたこと。
- Changes (files):
  - `lib/cli_adapter.sh` — Gemini は `thinking_level=auto/未設定` の場合 alias を使わず、明示 `minimal|low|medium|high` または `thinking_budget` があるときだけ alias を使うよう更新。
  - `scripts/sync_gemini_settings.py` — `thinking_level: auto` を alias 生成対象から除外し、`shogun` の implicit default alias を削除。
  - `scripts/configure_agents.sh` — Gemini thinking の既定値を `auto` / 空へ戻し、Shogun だけに暗黙値を入れないよう更新。
  - `tests/unit/test_cli_adapter.bats` / `tests/unit/test_sync_gemini_settings.bats` — `shogun` の未設定 Gemini は alias を使わない回帰テストへ更新。
  - `docs/REQS.md` / `docs/EXECPLAN_2026-03-07_upstream_restart_zellij_gemini.md` — Gemini alias は明示設定時のみ、という仕様へ更新。
- Commands + Results:
  - `python3 scripts/sync_gemini_settings.py` → PASS (`0 alias(es)`)
  - `bats tests/unit/test_cli_adapter.bats tests/unit/test_sync_gemini_settings.bats` → `1..102` PASS
- Decisions / Assumptions:
  - `Claude/Codex` の Shogun 既定最小思考は維持するが、Gemini だけは UX と初動安定性を優先して implicit alias を廃止した。
  - Gemini の thinking は explicit 設定時だけ alias を作る。未設定時は `Auto (Gemini 3)` の素の表示を使う。
- Next:
  1. 実機で `bash scripts/goza_zellij_pure.sh -s && bash scripts/goza_zellij_pure.sh` を再起動し、Shogun pane が `mas-shogun` ではなく `Auto (Gemini 3)` で立ち上がるか確認する。
  2. 必要なら Shogun にだけ explicit `model: gemini-3-pro-preview` を入れるか検討する。
- Links: queue/runtime/pure_zellij_goza-no-ma-ui_shogun.log, queue/runtime/pure_zellij_goza-no-ma-ui_gunshi.log

### 2026-03-09 16:34 (JST)
- Goal: 足軽 ID 混線と pure zellij 上の Codex 初動 race を修正し、Codex の未設定既定を `auto` へ揃える。
- Findings:
  - `queue/runtime/pure_zellij_goza-no-ma-ui_ashigaru1.log` に `tmux display-message -t "$TMUX_PANE" -p '#{@agent_id}'` と `ashigaru4` が残っており、`ashigaru1` が `ashigaru4` と誤認していた。
  - 原因は generated instructions と `AGENTS.md` に残っていた `tmux display-message` 固定の自己識別手順だった。
  - pure `zellij` の `zellij_agent_bootstrap.sh` は `build_cli_command_with_startup_prompt()` で Codex 起動引数へ本文を即埋め込みしており、`update prompt` や CLI ready 前に bootstrap が流れる構造だった。
- Changes (files):
  - `scripts/interactive_agent_runner.py` — pane 内 PTY runner を新規追加。`Codex` の update prompt と `Gemini` preflight を pane 内で処理し、ready 後に bootstrap を送る。
  - `scripts/zellij_agent_bootstrap.sh` — `script -qefc` / startup prompt 引数埋め込みをやめ、専用 PTY runner を呼ぶよう更新。`GOZA_SETUP_ONLY=true` も正しく扱う。
  - `lib/cli_adapter.sh` — `Codex` の未設定既定 `reasoning_effort` を空 (`auto`) に変更。
  - `scripts/configure_agents.sh` — CUI の `Codex reasoning_effort` 既定を role 不問で `auto` に統一。
  - `CLAUDE.md` / `instructions/common/forbidden_actions.md` — agent 自己識別を `AGENT_ID` 優先へ更新。
  - `tests/unit/test_cli_adapter.bats` / `tests/unit/test_goza_pure_bootstrap.bats` — `Codex auto` と PTY runner 前提の回帰テストへ更新。
  - `bash scripts/build_instructions.sh` により `AGENTS.md` と generated instructions を再生成。
- Commands + Results:
  - `bash scripts/build_instructions.sh` → PASS
  - `bash -n scripts/zellij_agent_bootstrap.sh scripts/goza_no_ma.sh scripts/configure_agents.sh lib/cli_adapter.sh` → PASS
  - `python3 -m py_compile scripts/interactive_agent_runner.py scripts/sync_gemini_settings.py` → PASS
  - `bats tests/unit/test_cli_adapter.bats tests/unit/test_goza_pure_bootstrap.bats tests/unit/test_sync_gemini_settings.bats` → `1..109` PASS
- Decisions / Assumptions:
  - pure `zellij` の interactive CLI は、今後も pane 内 PTY runner を正本とする。理由は ready 待ちと preflight を pane 内で完結させる方が race を潰しやすいため。
  - `Codex` の UI に出る `gpt-5.4 high` 表示は CLI 側のモデル表示であり、repo 側の `reasoning_effort` 既定とは分けて扱う。repo 側は未設定時 `auto` とする。
  - `tmux display-message` は tmux fallback に限定し、pure `zellij` では `AGENT_ID` を正本とする。
- Next:
  1. 実機で `bash scripts/goza_zellij_pure.sh -s && bash scripts/goza_zellij_pure.sh` を再起動し、Codex pane が updater を越えた後に初動命令を受けるか確認する。
  2. `ashigaru1` / `ashigaru2` の transcript で `ashigaru4` 誤認が消えたか確認する。
- Links: scripts/interactive_agent_runner.py, scripts/zellij_agent_bootstrap.sh, lib/cli_adapter.sh, CLAUDE.md, instructions/common/forbidden_actions.md

### 2026-03-09 16:40 (JST)
- Goal: `pure zellij` の ID混線 / Codex初動 fix checkpoint を push まで完了する。
- Commands + Results:
  - `git commit -m "codex: pure zellijのID混線とcodex初動を修正"` → PASS (`403ff61`)
  - `git push -u origin codex/auto` → FAIL (`fatal: could not read Username for 'https://github.com': No such device or address`)
- Decisions / Assumptions:
  - 実装とテストは完了しているため、停止理由は GitHub 認証のみ。
  - `config/settings.yaml` / `dashboard.md` / `queue/shogun_to_karo.yaml` / `docs/UPSTREAM_SYNC_2026-03-05.md` は未ステージのまま維持した。
- Next:
  1. GitHub 認証後に `git push -u origin codex/auto` を再実行する。
  2. 実機で `bash scripts/goza_zellij_pure.sh -s && bash scripts/goza_zellij_pure.sh` を実行し、Codex pane の updater 後 bootstrap と足軽 ID 誤認が解消したか確認する。
- Links: 403ff61

### 2026-03-09 23:00 (JST)
- Goal: `bash scripts/goza_zellij_pure.sh -s` 実行後に通常起動でも全 pane が `setup-only` になる回帰を修正する。
- Findings:
  - `queue/runtime/pure_zellij_goza-no-ma-ui_*.meta.log` が全 agent で `setup-only agent=...` のみを記録していた。
  - `/tmp/zellij_pure_goza_goza-no-ma-ui.kdl` には `export GOZA_SETUP_ONLY=true` が焼き込まれており、setup-only 用 layout が通常起動用 session 名 `goza-no-ma-ui` を汚染していた。
  - これにより、ユーザーが `bash scripts/goza_zellij_pure.sh -s` の直後に `bash scripts/goza_zellij_pure.sh` を実行しても、既存 setup-only session を掴んで CLI が一切起動しない状況が発生した。
- Changes (files):
  - `scripts/goza_zellij_pure.sh` — `-s/--setup-only` かつ `--session` 未指定時は `ZELLIJ_UI_SESSION=goza-no-ma-ui-setup` を使うよう変更。
  - `tests/unit/test_goza_wrapper_modes.bats` — setup-only が専用 session 名を使う回帰テストを追加。
- Commands + Results:
  - `bash -n scripts/goza_zellij_pure.sh scripts/goza_no_ma.sh` → PASS
  - `bats tests/unit/test_goza_wrapper_modes.bats tests/unit/test_goza_pure_bootstrap.bats` → `1..11` PASS
- Decisions / Assumptions:
  - pure zellij の setup-only は通常起動用 session と分離する。理由は user workflow が `-s` → 通常起動の2段であり、この導線で session 汚染を起こさないことが最優先のため。
  - `goza_zellij_pure.sh -s` の完全な background setup 化までは、この checkpoint では行わない。最小修正で再現バグを止める。
- Next:
  1. 実機で `bash scripts/goza_zellij_pure.sh -s` 実行後、通常起動 `bash scripts/goza_zellij_pure.sh` を再試験する。
  2. 問題が続く場合は、通常起動後の `/tmp/zellij_pure_goza_goza-no-ma-ui.kdl` と `queue/runtime/pure_zellij_goza-no-ma-ui_*.meta.log` を再採取する。
- Links: scripts/goza_zellij_pure.sh, tests/unit/test_goza_wrapper_modes.bats

### 2026-03-09 23:04 (JST)
- Goal: `pure zellij setup-only session 分離` checkpoint を push まで完了する。
- Commands + Results:
  - `git commit -m "codex: pure zellijのsetup-only sessionを分離"` → PASS (`215767c`)
  - `git push -u origin codex/auto` → FAIL (`fatal: could not read Username for 'https://github.com': No such device or address`)
- Decisions / Assumptions:
  - 実装とテストは完了しているため、停止理由は GitHub 認証のみ。
  - `config/settings.yaml` / `dashboard.md` / `queue/shogun_to_karo.yaml` / `docs/UPSTREAM_SYNC_2026-03-05.md` は既存未整理差分として維持した。
- Next:
  1. GitHub 認証後に `git push -u origin codex/auto` を再実行する。
  2. 実機で `bash scripts/goza_zellij_pure.sh -s` → `bash scripts/goza_zellij_pure.sh` を再試験する。
- Links: 215767c

### 2026-03-09 23:16 (JST)
- Goal: `pure zellij` で bootstrap 本文は入力されるが submit されない問題を修正する。
- Findings:
  - pane 内 runner `scripts/interactive_agent_runner.py` は `send_line()` で「本文 + Enter」を単一 write として PTY へ送っていた。
  - TUI CLI では、この送信方法だと入力欄への貼り付けだけで終わり、submit が無視されるケースがある。
- Changes (files):
  - `scripts/interactive_agent_runner.py` — `send_text()` / `send_enter()` / `deliver_bootstrap()` を追加し、bootstrap 本文送信後に短い待ち時間を入れて Enter を別 write で送るよう変更。
- Commands + Results:
  - `python3 -m py_compile scripts/interactive_agent_runner.py` → PASS
  - `bats tests/unit/test_interactive_agent_runner.bats tests/unit/test_goza_pure_bootstrap.bats` → `1..8` PASS（PTY 不可環境のテストは skip）
- Decisions / Assumptions:
  - 自動送信は「本文入力」と「submit」を分離する。理由は `Codex` / `Gemini` の TUI 入力欄が paste と submit を同一 write で安定処理しないため。
  - retry や二重 Enter はこの checkpoint では入れない。まず最小差分で submit 不発だけを止める。
- Next:
  1. 実機で `bash scripts/goza_zellij_pure.sh` を再起動し、初動命令が「入力欄に入るだけ」で止まらず送信されるか確認する。
  2. なお送信が不発なら、次は CLI ごとの submit キー差分（`Enter` / `Ctrl-J`）を切り分ける。
- Links: scripts/interactive_agent_runner.py

### 2026-03-09 23:18 (JST)
- Goal: `pure zellij 自動送信 submit 分離` checkpoint を push まで完了する。
- Commands + Results:
  - `git commit -m "codex: pure zellijの自動送信をsubmit分離にする"` → PASS (`a79983f`)
  - `git push -u origin codex/auto` → FAIL (`fatal: could not read Username for 'https://github.com': No such device or address`)
- Decisions / Assumptions:
  - 実装とテストは完了しているため、停止理由は GitHub 認証のみ。
  - 既存未整理差分 `config/settings.yaml` / `dashboard.md` / `queue/shogun_to_karo.yaml` / `docs/UPSTREAM_SYNC_2026-03-05.md` は維持する。
- Next:
  1. GitHub 認証後に `git push -u origin codex/auto` を再実行する。
  2. 実機で `bash scripts/goza_zellij_pure.sh` を再起動し、自動送信が submit されるか確認する。
- Links: a79983f

### 2026-03-09 23:29 (JST)
- Goal: `pure zellij` のリサイズ時に足軽 pane が細すぎる問題を緩和する。
- Findings:
  - 既定レイアウト比率は `42 / 28 / 30` で、右列の足軽 2x2 グリッドに割ける横幅が不足していた。
  - 特にウィンドウ幅を詰めた際、`ashigaru1..4` が縦に潰れてテキスト可読性が急激に落ちていた。
- Changes (files):
  - `scripts/goza_no_ma.sh` — pure zellij レイアウト比率を `40 / 24 / 36` に変更し、環境変数 `GOZA_PURE_LEFT_WIDTH` / `GOZA_PURE_MIDDLE_WIDTH` / `GOZA_PURE_RIGHT_WIDTH` で上書きできるよう更新。
  - `tests/unit/test_goza_pure_bootstrap.bats` — 右列を広めに確保する既定比率の回帰テストを追加。
- Commands + Results:
  - `bash -n scripts/goza_no_ma.sh` → PASS
  - `bats tests/unit/test_goza_pure_bootstrap.bats` → `1..8` PASS
- Decisions / Assumptions:
  - まずは固定比率を見直して右列を広げる。理由は KDL レイアウトに動的レスポンシブ判定を増やすより、既定値改善の方が影響が小さいため。
  - 将来的に画面幅ごとの自動再配置はあり得るが、この checkpoint では行わない。
- Next:
  1. 実機で `bash scripts/goza_zellij_pure.sh` を再起動し、足軽 pane の可読性が改善したか確認する。
  2. さらに詰めるなら、環境変数で比率を調整する導線を README に追加する。
- Links: scripts/goza_no_ma.sh, tests/unit/test_goza_pure_bootstrap.bats

### 2026-03-09 23:31 (JST)
- Goal: `pure zellij 既定レイアウト比率調整` checkpoint を push まで完了する。
- Commands + Results:
  - `git commit -m "codex: pure zellijの既定レイアウト比率を調整"` → PASS (`d937e12`)
  - `git push -u origin codex/auto` → FAIL (`fatal: could not read Username for 'https://github.com': No such device or address`)
- Decisions / Assumptions:
  - 実装とテストは完了しているため、停止理由は GitHub 認証のみ。
  - 既存未整理差分 `config/settings.yaml` / `dashboard.md` / `queue/shogun_to_karo.yaml` / `docs/UPSTREAM_SYNC_2026-03-05.md` は維持する。
- Next:
  1. GitHub 認証後に `git push -u origin codex/auto` を再実行する。
  2. 実機で pure zellij を再起動し、右列の足軽 pane 可読性を確認する。
- Links: d937e12

### 2026-03-10 10:20 (JST)
- Goal: pure `zellij` のリサイズ時に足軽 pane が依然として細すぎる問題を追加緩和する。
- Findings:
  - 既定レイアウト比率 `40 / 24 / 36` でも、4足軽 2x2 の右列が still narrow で、`Codex` / `Gemini` の入力欄が潰れやすかった。
  - 現行 KDL は 3列固定のため、最小差分で効く改善は右列比率の追加拡張である。
- Changes (files):
  - `scripts/goza_no_ma.sh` — pure zellij の既定列比率を `38 / 22 / 40` へ変更。
  - `tests/unit/test_goza_pure_bootstrap.bats` — 既定比率の回帰期待値を更新。
- Commands + Results:
  - `bash -n scripts/goza_no_ma.sh` → PASS
  - `bats tests/unit/test_goza_pure_bootstrap.bats` → `1..8` PASS
- Decisions / Assumptions:
  - 今回はレイアウトアルゴリズムを変えず、右列へさらに 4% 返す。理由は、固定 3 列のまま効果が大きく、他ペインへの影響も読みやすいため。
  - まだ極端に狭い画面では限界がある。必要なら次段で「幅しきい値以下なら足軽配置を別形」にする。
- Next:
  1. 実機で pure zellij を再起動し、右列の足軽 pane 可読性を再確認する。
  2. まだ狭いなら、右列 1カラム化または幅しきい値別レイアウトへ進む。
- Links: scripts/goza_no_ma.sh, tests/unit/test_goza_pure_bootstrap.bats

### 2026-03-10 10:22 (JST)
- Goal: `pure zellij 足軽列追加拡張` checkpoint を push まで完了する。
- Commands + Results:
  - `git commit -m "codex: pure zellijの足軽列をさらに拡張"` → PASS (`e27ee20`)
  - `git push -u origin codex/auto` → FAIL (`fatal: could not read Username for 'https://github.com': No such device or address`)
- Decisions / Assumptions:
  - 実装とテストは完了しているため、停止理由は GitHub 認証のみ。
  - 既存未整理差分 `config/settings.yaml` / `dashboard.md` / `queue/shogun_to_karo.yaml` / `docs/UPSTREAM_SYNC_2026-03-05.md` は維持する。
- Next:
  1. GitHub 認証後に `git push -u origin codex/auto` を再実行する。
  2. 実機で pure zellij を再起動し、右列可読性を確認する。
- Links: e27ee20

### 2026-03-10 10:31 (JST)
- Goal: pure `zellij` で pane 内 CLI の内部端末幅が細すぎる問題を緩和する。
- Findings:
  - ユーザー報告の症状は zellij pane 幅ではなく、pane 内で起動した `Codex` / `Gemini` が細い terminal width を見ていることに起因していた。
  - pure zellij 導線では `scripts/interactive_agent_runner.py` が PTY を作っており、ここで child PTY の列数を補正できる。
- Changes (files):
  - `scripts/interactive_agent_runner.py` — `MAS_CLI_COL_MULTIPLIER` を導入し、child PTY の `cols` を倍率補正するよう変更。あわせて `COLUMNS` / `LINES` の環境継承を除去。
  - `scripts/zellij_agent_bootstrap.sh` — pure zellij では既定で `MAS_CLI_COL_MULTIPLIER=2` を export。
  - `tests/unit/test_goza_pure_bootstrap.bats` — 列幅 2 倍補正の回帰テストを追加。
- Commands + Results:
  - `python3 -m py_compile scripts/interactive_agent_runner.py` → PASS
  - `bash -n scripts/zellij_agent_bootstrap.sh` → PASS
  - `bats tests/unit/test_goza_pure_bootstrap.bats` → `1..9` PASS
- Decisions / Assumptions:
  - 補正は pure zellij 導線に限定し、tmux や hybrid には入れない。理由は今回の症状が nested PTY を使う pure zellij runner 固有だから。
  - まずはユーザー要望どおり 2 倍補正を既定とする。必要なら `MAS_CLI_COL_MULTIPLIER` で後から 1/3 へ調整可能。
- Next:
  1. 実機で pure zellij を再起動し、内部 CLI の描画幅が改善したか確認する。
  2. なお狭い場合は CLI ごとに倍率を分けるか、pane 配置と併用して調整する。
- Links: scripts/interactive_agent_runner.py, scripts/zellij_agent_bootstrap.sh, tests/unit/test_goza_pure_bootstrap.bats

### 2026-03-10 10:33 (JST)
- Goal: `pure zellij 内部CLI幅補正` checkpoint を push まで完了する。
- Commands + Results:
  - `git commit -m "codex: pure zellijの内部CLI幅を補正"` → PASS (`c116cef`)
  - `git push -u origin codex/auto` → FAIL (`fatal: could not read Username for 'https://github.com': No such device or address`)
- Decisions / Assumptions:
  - 実装とテストは完了しているため、停止理由は GitHub 認証のみ。
  - 既存未整理差分 `config/settings.yaml` / `dashboard.md` / `queue/shogun_to_karo.yaml` / `docs/UPSTREAM_SYNC_2026-03-05.md` は維持する。
- Next:
  1. GitHub 認証後に `git push -u origin codex/auto` を再実行する。
  2. 実機で pure zellij を再起動し、内部 CLI 幅を確認する。
- Links: c116cef

### 2026-03-11 00:03 (JST)
- Goal: pure `zellij` で内部 CLI の terminal width を 2 倍化した結果、広い pane で描画崩れが起こる問題を是正する。
- Findings:
  - `MAS_CLI_COL_MULTIPLIER=2` を既定化すると、実 pane 幅より広い cols を TUI CLI に報告するため、`Codex` / `Gemini` の描画が横方向に破綻した。
  - この種の TUI は実 terminal width と内部認識 width が一致していることが前提なので、既定での倍率補正は非合理である。
- Changes (files):
  - `scripts/zellij_agent_bootstrap.sh` — `MAS_CLI_COL_MULTIPLIER` の既定値を `2` から `1` へ戻し、必要時のみ環境変数 override で有効化する方式へ変更。
  - `tests/unit/test_goza_pure_bootstrap.bats` — 既定値 `1` と補正機構の存在を確認する回帰テストへ更新。
- Commands + Results:
  - `python3 -m py_compile scripts/interactive_agent_runner.py` → PASS
  - `bash -n scripts/zellij_agent_bootstrap.sh` → PASS
  - `bats tests/unit/test_goza_pure_bootstrap.bats` → `1..9` PASS
- Decisions / Assumptions:
  - 既定では実 pane 幅を正本に戻す。理由は、実 terminal と child PTY の cols をずらすと TUI 表示が構造的に壊れるため。
  - 幅補正機構自体は残し、必要なら `MAS_CLI_COL_MULTIPLIER=2` を手動指定できるようにする。
- Next:
  1. 実機で pure zellij を再起動し、描画崩れが消えたことを確認する。
  2. まだ足軽 pane が狭いなら、幅補正ではなくレイアウト再配置で改善する。
- Links: scripts/zellij_agent_bootstrap.sh, scripts/interactive_agent_runner.py, tests/unit/test_goza_pure_bootstrap.bats

### 2026-03-11 00:04 (JST)
- Goal: `pure zellij 幅補正既定戻し` checkpoint を push まで完了する。
- Commands + Results:
  - `git commit -m "codex: pure zellijの幅補正既定を戻す"` → PASS (`8bb8a34`)
  - `git push -u origin codex/auto` → FAIL (`fatal: could not read Username for 'https://github.com': No such device or address`)
- Decisions / Assumptions:
  - 実装とテストは完了しているため、停止理由は GitHub 認証のみ。
  - 既存未整理差分 `config/settings.yaml` / `dashboard.md` / `queue/shogun_to_karo.yaml` / `docs/UPSTREAM_SYNC_2026-03-05.md` は維持する。
- Next:
  1. GitHub 認証後に `git push -u origin codex/auto` を再実行する。
  2. 実機で pure zellij を再起動し、描画崩れが解消したか確認する。
- Links: 8bb8a34

### 2026-03-11 00:14 (JST)
- Goal: pure `zellij` を wide 画面で最大化した際も、役職配置が読みやすく操作しやすい構造へ寄せる。
- Findings:
  - 旧レイアウトは `shogun/gunshi` を左列へ縦積みし、`karo` を中列 full-height、足軽を右列 2x2 にしていた。
  - この構造は narrow 画面には効くが、wide 画面では `shogun` が full-height にならず、`gunshi` が左列を圧迫し、以前の要求「将軍最大・家老二番手・足軽 compact」にも一致していなかった。
  - `Codex` の scroll/view 問題は、wide 画面でも中核 pane の縦横比が悪いことが主因で、単なる幅比率調整だけでは不十分だった。
- Changes (files):
  - `scripts/goza_no_ma.sh` — pure zellij の wide layout を再構成。`shogun` を full-height 左列、`karo` を full-height 中列、右列を `gunshi` 上段 + `ashigaru` 下段 grid に変更。既定比率は `44 / 24 / 32`、`GOZA_PURE_GUNSHI_HEIGHT` を追加。
  - `tests/unit/test_goza_pure_bootstrap.bats` — 新しい既定比率と `shogun full-height / gunshi 右列上段` の回帰テストを追加。
  - `docs/REQS.md` — wide 画面での pure zellij 可用性要件を追記。
- Commands + Results:
  - `bash -n scripts/goza_no_ma.sh` → PASS
  - `bats tests/unit/test_goza_pure_bootstrap.bats` → `1..10` PASS
- Decisions / Assumptions:
  - wide 画面では、以前の役職優先順位に戻す。理由は、将軍と家老の情報密度が最も高く、maximize 時の可用性が最優先だから。
  - 右列は `gunshi + ashigaru` にまとめる。理由は、軍師は参謀役として常時可視性を保ちつつ、足軽は compact な補助 pane に寄せる方が整合的だから。
- Next:
  1. 実機で pure zellij を最大化し、`shogun` と `karo` の可読性、`gunshi`/足軽の compact 性を再確認する。
  2. なお wide でも問題が残る場合は、画面幅しきい値で narrow/wide レイアウトを切り替える。
- Links: scripts/goza_no_ma.sh, tests/unit/test_goza_pure_bootstrap.bats, docs/REQS.md

### 2026-03-11 00:16 (JST)
- Goal: `pure zellij wide レイアウト再構成` checkpoint を push まで完了する。
- Commands + Results:
  - `git commit -m "codex: pure zellijのwideレイアウトを再構成"` → PASS (`713a1b1`)
  - `git push -u origin codex/auto` → FAIL (`fatal: could not read Username for 'https://github.com': No such device or address`)
- Decisions / Assumptions:
  - 実装とテストは完了しているため、停止理由は GitHub 認証のみ。
  - 既存未整理差分 `config/settings.yaml` / `dashboard.md` / `queue/shogun_to_karo.yaml` / `docs/UPSTREAM_SYNC_2026-03-05.md` は維持する。
- Next:
  1. GitHub 認証後に `git push -u origin codex/auto` を再実行する。
  2. 実機で pure zellij を最大化し、wide レイアウトの可読性を確認する。
- Links: 713a1b1

### 2026-03-11 00:23 (JST)
- Goal: WSL ウィンドウリサイズ時に pure `zellij` の pane 内 TUI (`Codex` / `Gemini`) も追従するようにする。
- Findings:
  - `scripts/interactive_agent_runner.py` は `SIGWINCH` を受けて child PTY の winsize は更新していたが、子プロセス自体へ `SIGWINCH` を伝播していなかった。
  - tmux 版より pure zellij 版が resize 追従で弱いのは、この nested PTY + signal 伝播不足が主因と判断した。
- Changes (files):
  - `scripts/interactive_agent_runner.py` — `copy_winsize()` 実行後、child process group へ `SIGWINCH` を送るよう変更。起動直後にも一度 `SIGWINCH` を送る。
  - `tests/unit/test_goza_pure_bootstrap.bats` — `SIGWINCH` 伝播の回帰テストを追加。
  - `docs/REQS.md` — pure zellij resize 追従の要件を追加。
- Commands + Results:
  - `python3 -m py_compile scripts/interactive_agent_runner.py` → PASS
  - `bats tests/unit/test_goza_pure_bootstrap.bats` → `1..11` PASS
- Decisions / Assumptions:
  - resize 追従は runner 層で完結させる。理由は `zellij` outer shell より child PTY と子プロセス群の整合を取る責務が runner にあるため。
  - `SIGWINCH` は process group へ送る。理由は `bash -lc <command>` 配下の TUI CLI 本体まで確実に届かせるため。
- Next:
  1. 実機で WSL ウィンドウを大小に変更し、`Codex` / `Gemini` pane が崩れず再レイアウトするか確認する。
  2. なお改善が弱い場合は、pure zellij だけ narrow/wide の layout 切替も併用する。
- Links: scripts/interactive_agent_runner.py, tests/unit/test_goza_pure_bootstrap.bats, docs/REQS.md

### 2026-03-11 00:24 (JST)
- Goal: `pure zellij resize追従改善` checkpoint を push まで完了する。
- Commands + Results:
  - `git commit -m "codex: pure zellijのresize追従を改善"` → PASS (`058b2a6`)
  - `git push -u origin codex/auto` → FAIL (`fatal: could not read Username for 'https://github.com': No such device or address`)
- Decisions / Assumptions:
  - 実装とテストは完了しているため、停止理由は GitHub 認証のみ。
  - 既存未整理差分 `config/settings.yaml` / `dashboard.md` / `queue/shogun_to_karo.yaml` / `docs/UPSTREAM_SYNC_2026-03-05.md` は維持する。
- Next:
  1. GitHub 認証後に `git push -u origin codex/auto` を再実行する。
  2. 実機で WSL ウィンドウを resize し、pane 内 TUI が追従するか確認する。
- Links: 058b2a6

### 2026-03-11 00:33 (JST)
- Goal: pure `zellij` のレイアウトを、起動時の terminal 幅に応じて `wide / normal / narrow` で自動選択する。
- Findings:
  - pure zellij の static layout は、起動後に安全に構造変更する仕組みが弱く、runtime live reflow を前提にするのは危険である。
  - 一方で、ユーザー報告は「小さい時は正常、大きいと余白が大きすぎる」であり、起動時の terminal 幅に応じた profile 選択で大半を吸収できる。
- Changes (files):
  - `scripts/goza_no_ma.sh` — `PURE_LAYOUT_PROFILE` / `--layout-profile` を追加。terminal 幅から `wide / normal / narrow` を auto 判定し、narrow では `shogun/gunshi` 左列縦積み、normal/wide では `shogun full-height` 構造を使い分けるよう変更。
  - `tests/unit/test_goza_pure_bootstrap.bats` — auto profile 判定と narrow profile 分岐の回帰テストを追加。
  - `docs/REQS.md` — 起動時 auto layout profile の要件を追加。
- Commands + Results:
  - `bash -n scripts/goza_no_ma.sh` → PASS
  - `bats tests/unit/test_goza_pure_bootstrap.bats` → `1..13` PASS
- Decisions / Assumptions:
  - runtime 中の live 構造変更はこの checkpoint では扱わず、起動時判定に留める。理由は pure zellij の static layout 制約を超えるため。
  - `narrow` では以前の左列縦積みへ戻す。理由は、狭い画面では `gunshi` を右列へ退避させるより `shogun` と同列にまとめた方が横圧迫を減らせるため。
- Next:
  1. 実機で小さいウィンドウと大きいウィンドウの両方から起動し、auto profile の選択結果を確認する。
  2. 必要なら `--layout-profile wide|normal|narrow` の明示指定も README へ追記する。
- Links: scripts/goza_no_ma.sh, tests/unit/test_goza_pure_bootstrap.bats, docs/REQS.md

### 2026-03-11 00:35 (JST)
- Goal: `pure zellij autoレイアウト追加` checkpoint を push まで完了する。
- Commands + Results:
  - `git commit -m "codex: pure zellijのautoレイアウトを追加"` → PASS (`db474b5`)
  - `git push -u origin codex/auto` → FAIL (`fatal: could not read Username for 'https://github.com': No such device or address`)
- Decisions / Assumptions:
  - 実装とテストは完了しているため、停止理由は GitHub 認証のみ。
  - 既存未整理差分 `config/settings.yaml` / `dashboard.md` / `queue/shogun_to_karo.yaml` / `docs/UPSTREAM_SYNC_2026-03-05.md` は維持する。
- Next:
  1. GitHub 認証後に `git push -u origin codex/auto` を再実行する。
  2. 実機で小窓/大窓から pure zellij を起動し、auto profile の選択結果を確認する。
- Links: db474b5

### 2026-03-11 00:48 (JST)
- Goal: upstream `2ef81f9`（compaction 復帰時の persona 再読強制）を、このフォークの複数 CLI 用 root instruction 群へ反映する。
- Findings:
  - `git show 2ef81f9 -- CLAUDE.md` を確認したところ、upstream の差分は `CLAUDE.md` に `Post-Compaction Recovery (CRITICAL)` を追加するものだった。
  - このフォークでは `CLAUDE.md` のみでなく `AGENTS.md` / `.github/copilot-instructions.md` / `agents/default/system.md` も root instruction として使っているため、`CLAUDE.md` だけに反映しても不十分。
  - `upstream/latest` という remote branch は存在せず、最新は `upstream/main` の `2ef81f9` (`v4.0.4`) だった。
- Changes (files):
  - `CLAUDE.md` — upstream 同等の `Post-Compaction Recovery (CRITICAL)` 節を追加。
  - `AGENTS.md` — Codex 用 root instruction に同節を追加。
  - `.github/copilot-instructions.md` — Copilot 用 root instruction に同節を追加。
  - `agents/default/system.md` — Kimi 系 default system instruction に同節を追加。
  - `docs/UPSTREAM_SYNC_2026-03-11_COMPACTION.md` — upstream `2ef81f9` の反映メモを追加。
  - `docs/INDEX.md`, `docs/REQS.md`, `docs/EXECPLAN_2026-03-07_upstream_restart_zellij_gemini.md` — 追補と同期記録を更新。
- Commands + Results:
  - `git show --stat --summary 2ef81f974bbb633a0cdfe00566671d8a64d5f462` → upstream 差分が `CLAUDE.md` 1ファイルであることを確認。
  - `git fetch upstream --prune` → PASS（`upstream/main` が `2ef81f9` に更新、tag `v4.0.4` 取得）。
  - `git rev-list --left-right --count HEAD...upstream/main` → `207 249`（大きく乖離）
  - `git diff --stat HEAD..upstream/main` → 289 files changed（単純 merge 不適）
- Decisions / Assumptions:
  - 今回は upstream 全体 merge ではなく、重要差分 `2ef81f9` のみを先行反映する。理由は `upstream/main` とこのフォークの差分が大きく、単純 merge が非現実的なため。
  - compaction recovery は root instruction 群すべてへ横展開する。理由は CLI ごとに system prompt 入口が分かれているため。
- Next:
  1. root instruction 群の更新をコミットし、runtime/user state (`config/settings.yaml`, `dashboard.md`, `queue/*.yaml`) はコミット対象から外す。
  2. その後、`upstream/main` ベースで再統合する場合は別ブランチで staged migration を行う。
- Links: 2ef81f974bbb633a0cdfe00566671d8a64d5f462, docs/UPSTREAM_SYNC_2026-03-11_COMPACTION.md

### 2026-03-11 00:51 (JST)
- Goal: `upstream 2ef81f9 compaction recovery 反映` checkpoint を push まで完了する。
- Commands + Results:
  - `git commit -m "codex: upstream compaction復帰手順を反映"` → PASS (`29137ea`)
  - `git push -u origin codex/auto` → FAIL (`fatal: could not read Username for 'https://github.com': No such device or address`)
- Decisions / Assumptions:
  - runtime/user state (`config/settings.yaml`, `dashboard.md`, `queue/shogun_to_karo.yaml`) は upstream sync コミットへ混ぜない。
  - `upstream/latest` という remote branch は無く、今回の取り込み対象は `upstream/main` の `2ef81f9` とした。
- Next:
  1. GitHub 認証後に `git push -u origin codex/auto` を再実行する。
  2. upstream 全体を基準に再統合する場合は、`upstream/main` ベースの別ブランチで staged migration を行う。
- Links: 29137ea, 2ef81f974bbb633a0cdfe00566671d8a64d5f462

### 2026-03-11 14:55 (JST)
- Goal: ユーザーが行った merge 後に、conflict / 構文 / 既存 unit test 回帰が無いかを確認する。
- Findings:
  - `git diff --stat --summary HEAD~1..HEAD` の差分は `docs/` と root instruction 群（`AGENTS.md`, `CLAUDE.md`, `.github/copilot-instructions.md`, `agents/default/system.md`）に限定され、コード本体の直接変更は無かった。
  - `rg -n "^(<<<<<<<|=======|>>>>>>>)" -S .` はヒット無しで、merge conflict marker は残っていない。
  - `git status --short` では既存 dirty file として `config/settings.yaml`, `dashboard.md`, `docs/UPSTREAM_SYNC_2026-03-05.md`, `queue/shogun_to_karo.yaml` が残っている。今回の merge 検証とは別系統の user/runtime state とみなす。
- Commands + Results:
  - `bats tests/unit/test_build_system.bats tests/unit/test_cli_adapter.bats tests/unit/test_configure_agents.bats tests/unit/test_goza_pure_bootstrap.bats tests/unit/test_goza_wrapper_modes.bats tests/unit/test_interactive_agent_runner.bats tests/unit/test_mux_parity.bats tests/unit/test_ntfy_auth.bats tests/unit/test_send_wakeup.bats tests/unit/test_sync_gemini_settings.bats tests/unit/test_sync_opencode_config.bats tests/unit/test_topology_adapter.bats tests/unit/test_zellij_bootstrap_delivery.bats` → PASS (`1..235`)
  - `git log --oneline --merges -n 10` → 直近 merge commit は repo 履歴上の過去 merge のみで、現 HEAD に未解決 merge 状態は無い。
- Decisions / Assumptions:
  - 今回は review/検証タスクであり、runtime/user state を巻き込む追加 commit は作らない。
  - dirty file のうち `docs/WORKLOG.md` と `docs/REQS.md` は今回の検証ログ追加によるもの。既存 dirty file とは分けて扱う。
- Next:
  1. もしユーザーが merge した内容で実機不具合を疑っているなら、次は `goza_zellij_pure.sh` または `goza_zellij.sh` の実起動 smoke を行う。
  2. commit/push を行う場合は、user/runtime state を分離してから docs-only で行う。
- Links: docs/REQS.md, docs/WORKLOG.md

### 2026-03-11 15:38 (JST)
- Goal: zellij 廃止・tmux 一本化をコード/文書/テストまで閉じる。
- Changes:
  - `Waste/zellij_2026-03-11/` を作成し、旧 zellij 実装・補助コード・テンプレート・テスト・ランチャーを退避。
  - `scripts/goza_no_ma.sh` を tmux 専用 frontend に差し替え、`scripts/goza_zellij.sh` / `scripts/goza_zellij_pure.sh` / `scripts/goza_hybrid.sh` / `scripts/shutsujin_zellij.sh` は tmux 互換 wrapper 化。
  - `README.md` を tmux 専用運用ガイドへ全面更新。
  - `instructions/common/*.md` / `instructions/roles/*.md` を tmux 前提へ修正し、`bash scripts/build_instructions.sh` で generated / AGENTS / copilot / kimi system を再生成。
  - `tests/unit/test_mux_parity*.bats` と `tests/unit/test_configure_agents.bats` を tmux-only 前提へ更新。
- Commands + Results:
  - `bash scripts/build_instructions.sh` → PASS
  - `bash -n shutsujin_departure.sh scripts/goza_no_ma.sh scripts/goza_tmux.sh scripts/goza_zellij.sh scripts/goza_zellij_pure.sh scripts/goza_hybrid.sh scripts/configure_agents.sh scripts/inbox_watcher.sh scripts/watcher_supervisor.sh first_setup.sh scripts/mux_parity_smoke.sh` → PASS
  - `bats tests/unit/test_build_system.bats tests/unit/test_cli_adapter.bats tests/unit/test_configure_agents.bats tests/unit/test_mux_parity.bats tests/unit/test_mux_parity_smoke.bats tests/unit/test_ntfy_auth.bats tests/unit/test_send_wakeup.bats tests/unit/test_sync_gemini_settings.bats tests/unit/test_sync_opencode_config.bats tests/unit/test_topology_adapter.bats` → PASS (`1..207`)
- Decisions / Assumptions:
  - 旧 `goza_zellij*` 名は削除せず、tmux へ委譲する wrapper として維持する。理由は既存操作導線を壊さないため。
  - `zellij` 記述は履歴 docs と退避先に残すが、現役運用コード/README/instructions からは外す。
  - `dashboard.md` / `queue/shogun_to_karo.yaml` / `docs/UPSTREAM_SYNC_2026-03-05.md` は既存 dirty のため今回の checkpoint から除外する。
- Next:
  1. tmux 実機 smoke (`bash scripts/goza_tmux.sh -s`, `bash scripts/goza_tmux.sh --template goza_room`) を確認する。
  2. 必要なら historical zellij docs も `Waste/` へ追加退避する。
- Links: README.md, scripts/goza_no_ma.sh, scripts/watcher_supervisor.sh, Waste/zellij_2026-03-11/, docs/EXECPLAN_2026-03-11_tmux_only_consolidation.md

### 2026-03-11 15:42 (JST)
- Goal: `tmux 一本化` checkpoint を push まで完了する。
- Commands + Results:
  - `git commit -m "codex: tmux一本化とzellij退避を実施"` → PASS (`880860d`)
  - `git push -u origin codex/auto` → FAIL (`fatal: could not read Username for 'https://github.com': No such device or address`)
- Decisions / Assumptions:
  - 実装とテストは完了しているため、停止理由は GitHub 認証のみ。
  - `docs/UPSTREAM_SYNC_2026-03-05.md` / `dashboard.md` / `queue/shogun_to_karo.yaml` は今回の checkpoint から除外した。
- Next:
  1. GitHub 認証後に `git push -u origin codex/auto` を再実行する。

### 2026-03-11 16:18 (JST)
- Goal: `shutsujin_departure.sh` 一本化を完了し、`goza*` と `startup.template` を現役運用から外す。
- Changes:
  - `scripts/goza_no_ma.sh` / `scripts/goza_tmux.sh` / `scripts/goza_zellij.sh` / `scripts/goza_zellij_pure.sh` / `scripts/goza_hybrid.sh` / `scripts/shutsujin_zellij.sh` / `templates/multiplexer/tmux_templates.yaml` / `start_tmux_goza.bat` / `start_zellij_goza.bat` を `Waste/tmux_unification_2026-03-11/` へ退避。
  - `README.md` を `shutsujin_departure.sh` だけを案内する形へ簡素化。
  - `config/settings.yaml` / `first_setup.sh` / `scripts/configure_agents.sh` から `startup.template` を削除。
  - `tests/unit/test_configure_agents.bats` / `tests/unit/test_mux_parity.bats` を `goza` 非依存の形へ更新。
- Commands + Results:
  - `find Waste -maxdepth 3 -type f | sort` → `tmux_unification_2026-03-11/` 以下へ `goza*` / `shutsujin_zellij.sh` / 旧 template / 旧 bat が退避されたことを確認。
  - `rg -n "goza_|goza_room|shogun_only|startup\\.template|scripts/goza|tmux_templates|shutsujin_zellij|start_.*goza" . -g '!Waste/**'` → 現役コードではヒット無し、履歴 docs のみヒット。
- Decisions / Assumptions:
  - `goza` は tmux-only 化後も単なる別フロントエンドであり、upstream 本線の `shutsujin_departure.sh` と二重入口になるため廃止する。
  - 過去の zellij / goza 経緯は履歴 docs に残すが、現役仕様は `docs/REQS.md` と `README.md` で上書きする。
- Next:
  1. `bash -n` と `bats` を再実行して、tmux-only 最終形の回帰確認を行う。
  2. 問題が無ければ checkpoint commit を作成する。

### 2026-03-11 16:33 (JST)
- Goal: `shutsujin_departure.sh` 一本化 checkpoint を commit/push まで完了する。
- Commands + Results:
  - `bash -n shutsujin_departure.sh scripts/configure_agents.sh scripts/inbox_watcher.sh scripts/watcher_supervisor.sh first_setup.sh scripts/mux_parity_smoke.sh` → PASS
  - `bats tests/unit/test_build_system.bats tests/unit/test_cli_adapter.bats tests/unit/test_configure_agents.bats tests/unit/test_mux_parity.bats tests/unit/test_mux_parity_smoke.bats tests/unit/test_ntfy_auth.bats tests/unit/test_send_wakeup.bats tests/unit/test_sync_gemini_settings.bats tests/unit/test_sync_opencode_config.bats tests/unit/test_topology_adapter.bats` → PASS (`1..207`)
  - `git commit -m "codex: shutsujin_departure一本化でgozaを廃止"` → PASS (`baec4e4`)
  - `git push -u origin codex/auto` → FAIL (`fatal: could not read Username for 'https://github.com': No such device or address`)
- Decisions / Assumptions:
  - `goza*` は tmux-only 化後も別フロントエンドでしかなく、upstream 本線の `shutsujin_departure.sh` と二重導線になるため廃止した。
  - `docs/UPSTREAM_SYNC_2026-03-05.md` は既存の unrelated dirty file として今回の commit から除外した。
- Next:
  1. GitHub 認証後に `git push -u origin codex/auto` を再実行する。
  2. 実機起動確認は `bash shutsujin_departure.sh -s` と `bash shutsujin_departure.sh` で行う。

## 2026-03-11 (upstream tmux base + CLI-only strategy)
- 要求: upstream `main` を正本にし、独自差分を tmux 本線上の CLI 拡張へ限定する方針を docs と導線に反映する。
- 実施:
  - `docs/REQS.md` に「upstream 正本 + CLI拡張限定」の要求と受け入れ条件を追加。
  - `docs/UPSTREAM_SYNC_2026-03-11_CLI_ONLY_STRATEGY.md` を新規作成し、保持する独自差分と捨てる差分を整理。
  - `docs/EXECPLAN_2026-03-11_upstream_cli_only_rebase.md` を新規作成し、README / first_setup / upstream 寄せの段取りを記録。
  - `docs/INDEX.md` に新しい同期ノートと ExecPlan を登録。
  - `README.md` / `README_ja.md` を tmux 本線 + 追加 CLI 差分の説明へ更新。
  - `first_setup.sh` の方針表示を upstream tmux 本線 + CLI 拡張へ更新。
- 検証:
  - `bash -n shutsujin_departure.sh first_setup.sh scripts/configure_agents.sh` → PASS
  - `bats tests/unit/test_build_system.bats tests/unit/test_cli_adapter.bats tests/unit/test_configure_agents.bats tests/unit/test_mux_parity.bats tests/unit/test_mux_parity_smoke.bats tests/unit/test_ntfy_auth.bats tests/unit/test_send_wakeup.bats tests/unit/test_sync_gemini_settings.bats tests/unit/test_sync_opencode_config.bats tests/unit/test_topology_adapter.bats` → 1..207 PASS
- 判断:
  - upstream 正本化は全量 merge ではなく、README / first_setup / CLI adapter 周辺を順に寄せる staged migration を継続する。
  - `docs` 内の zellij 記述は履歴資料として残すが、現役運用文書と導線からは外す。
- Git:
  - `git commit -m "codex: upstream正本とCLI拡張方針を整理"` → `a59dc75`
  - `git push -u origin codex/auto` → GitHub 認証未設定で失敗 (`could not read Username for 'https://github.com'`)

## 2026-03-11 (shutsujin top-level upstream alignment)
- 要求: upstream `main` を正本にしつつ、`shutsujin_departure.sh` を tmux 本線へ寄せる。
- 実施:
  - `shutsujin_departure.sh` の shebang を `#!/usr/bin/env bash` へ戻した。
  - 廃止済み `MULTIPLEXER_SETTING` / `MAS_MULTIPLEXER` / `ORIGINAL_ARGS` の上部処理を削除した。
  - upstream 本線にある Python venv プリフライトチェックを復元し、`.venv` 自動作成と `requirements.txt` 導入をスクリプト上部へ戻した。
  - `TOPOLOGY_ADAPTER` / `inbox_path` / `Gemini/OpenCode/Kilo` 同期関数はそのまま維持し、CLI拡張差分だけを残した。
- 検証:
  - `bash -n shutsujin_departure.sh first_setup.sh scripts/configure_agents.sh` → PASS
  - `bats tests/unit/test_cli_adapter.bats tests/unit/test_configure_agents.bats tests/unit/test_mux_parity.bats tests/unit/test_mux_parity_smoke.bats tests/unit/test_send_wakeup.bats tests/unit/test_sync_gemini_settings.bats tests/unit/test_sync_opencode_config.bats tests/unit/test_topology_adapter.bats` → 1..161 PASS
- 判断:
  - tmux-only 化後の multiplexer 強制分岐は不要なので、上流構造へ戻してよい。
  - `shutsujin_departure.sh` の次段整理対象は、起動メッセージ・モデル説明・CLI ready/bootstrap の役割分離。
- Git:
  - `git commit -m "codex: shutsujin上部をupstream本線へ寄せる"` → `0148864`
  - `git push -u origin codex/auto` → GitHub 認証未設定で失敗 (`could not read Username for 'https://github.com'`)
## 2026-03-11 (shutsujin display cleanup + cli_adapter python fallback)
- 要求: shutsujin の固定モデル説明を削り、実際の CLI 設定表示へ寄せる。あわせて cli_adapter が .venv に PyYAML が無い場合でも壊れないようにする。
- 実施:
  - `shutsujin_departure.sh` に `resolve_model_display_name` / `resolve_cli_summary` を追加し、起動ログと pane 表示を `cli_adapter` ベースの動的表示へ変更。
  - `shutsujin_departure.sh -h` の固定説明（Opus/Sonnet 固定、手動Claude起動など）を削除し、`config/settings.yaml` と `scripts/configure_agents.sh` 基準の説明へ更新。
  - 布陣図に `gunshi` セッションを追加。
  - `lib/cli_adapter.sh` で `.venv/bin/python3` に `yaml` が無い場合は system `python3` へ自動フォールバックするよう修正。
- 検証:
  - `bash -n lib/cli_adapter.sh shutsujin_departure.sh first_setup.sh scripts/configure_agents.sh` → PASS
  - `bats tests/unit/test_cli_adapter.bats tests/unit/test_configure_agents.bats tests/unit/test_mux_parity.bats tests/unit/test_mux_parity_smoke.bats tests/unit/test_send_wakeup.bats tests/unit/test_sync_gemini_settings.bats tests/unit/test_sync_opencode_config.bats tests/unit/test_topology_adapter.bats` → 1..161 PASS
- 判断:
  - `cli_adapter` の Python 選択は起動系全体の前提なので、表示改善より優先して修正した。
  - `docs/UPSTREAM_SYNC_2026-03-05.md` は今回の commit から除外する。
- Git:
  - `git commit -m "codex: shutsujin表示を動的CLI構成へ寄せる"` → `cbc3042`
  - `git push -u origin codex/auto` → GitHub 認証未設定で失敗 (`could not read Username for 'https://github.com': No such device or address`)
- 追加実施:
  - `shutsujin_departure.sh` で `-h/--help` 要求時は venv プリフライトをスキップするようにし、ヘルプ表示だけで失敗しないよう修正。
  - setup-only 案内に `gunshi` と動的CLIコマンド例を追加。
  - Windows Terminal の `-t` 展開に `gunshi` タブを追加。
- 追加検証:
  - `bash shutsujin_departure.sh -h | sed -n "1,140p"` → PASS
- Git:
  - `git commit -m "codex: shutsujinの案内とヘルプ導線を整理"` → `b252b8a`
  - `git push -u origin codex/auto` → GitHub 認証未設定で失敗 (`could not read Username for 'https://github.com': No such device or address`)

## 2026-03-11 17:45 JST — tmux 実機テスト導線の安定化
- `shutsujin_departure.sh` の venv プリフライトを整理し、`.venv` / `requirements.txt` 必須前提を削除。`python3 + PyYAML` が使えれば起動継続とした。
- `lib/cli_adapter.sh` の `.venv/bin/python3` 直参照 13 箇所を `CLI_ADAPTER_PYTHON` へ統一。system `python3` fallback が全関数で効くようにした。
- `wait_for_cli_ready_tmux()` の `codex` / `gemini` ready 判定へ `Working` / `esc to interrupt` 系を追加し、起動直後に待ち続ける問題を解消。
- 検証:
  - `bash -n shutsujin_departure.sh lib/cli_adapter.sh` PASS
  - `bats tests/unit/test_cli_adapter.bats tests/unit/test_configure_agents.bats tests/unit/test_send_wakeup.bats tests/unit/test_sync_gemini_settings.bats tests/unit/test_sync_opencode_config.bats tests/unit/test_topology_adapter.bats` PASS (`1..153`)
  - `bash shutsujin_departure.sh -s` を tmux 実起動 smoke で確認。`shogun/gunshi/multiagent` セッション生成まで成功。
  - `bash shutsujin_departure.sh` を tmux 実起動 smoke で確認。CLI ready 判定、初動命令配信、watcher 起動、完了メッセージまで成功。
- 観測:
  - この sandbox では `gemini` 未導入のため、`resolve_cli_type_for_agent()` により `codex` fallback となった。実機で `gemini` が PATH 上にあれば fallback は発生しない。
  - fallback 時の表示名は `codex / Gemini` のように設定値ベースで見える箇所が残る。これは UX 修正候補だが、起動可否には影響しない。
