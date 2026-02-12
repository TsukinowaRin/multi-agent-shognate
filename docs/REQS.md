# Requirements (Normalized)

最終更新: 2026-02-12
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

## 追補（2026-02-11: 混在起動テスト）
### 要求
1. `Codex CLI` と `Gemini CLI` の混在起動を確認する。
2. 配備は `shogun/karo=codex`、`ashigaru1/ashigaru2=gemini` とする。
3. `topology.active_ashigaru` は2名構成（`ashigaru1`, `ashigaru2`）で起動できること。

### 受け入れ条件（観測可能）
1. コマンド: `bash scripts/shutsujin_zellij.sh -s`
   - 期待結果: セッション一覧が `shogun`, `karo`, `ashigaru1`, `ashigaru2` の4つのみになる。
2. コマンド: `bash scripts/shutsujin_zellij.sh`
   - 期待結果: 起動ログに `shogun: codex`, `karo: codex`, `ashigaru1: gemini`, `ashigaru2: gemini` が表示される。
3. コマンド: `cat queue/runtime/agent_cli.tsv`
   - 期待結果: 上記4エージェントのCLI割当が `codex/codex/gemini/gemini` で記録される。

## 追補（2026-02-11: WSL再起動後の一発起動）
### 要求
1. WSL再起動後に1コマンドで起動できる導線を用意する。
2. 画面は「区切りが明確な表示」（ペイン/タブ相当）で各エージェントに接続できること。

### 受け入れ条件（観測可能）
1. コマンド: `bash scripts/goza_no_ma.sh -h`
   - 期待結果: ヘルプが表示される。
2. コマンド: `bash scripts/goza_no_ma.sh`
   - 期待結果: `shutsujin_departure.sh` 実行後、`tmux` の分割ペイン画面に入り、各ペインで `zellij attach <agent>` が実行される。
3. コマンド: `bash scripts/goza_no_ma.sh --view-only`
   - 期待結果: バックエンドを再起動せず、既存 zellij セッションへのビュー接続のみ行う。

## 追補（2026-02-11: 上様向けの部屋設計と色）
### 要求
1. 起動スクリプト名は道場ではなく「上様来訪を意識した部屋名」にする。
2. タブ（ペイン見出し）色は役職ごとに分ける。
   - 将軍: 紫
   - 家老: 紺
   - 足軽: 茶

### 受け入れ条件（観測可能）
1. コマンド: `bash scripts/goza_no_ma.sh --help`
   - 期待結果: 新スクリプト名でヘルプが表示される。
2. コマンド: `bash scripts/goza_no_ma.sh -s --no-attach`
   - 期待結果: tmux `pane-border-format` が以下の色分岐を含む。
     - `shogun` → `bg=colour54`（紫系）
     - `karo` → `bg=colour19`（紺系）
     - その他（`ashigaru*`）→ `bg=colour94`（茶系）

## 追補（2026-02-11: 名称再変更）
### 要求
1. 部屋名は `御座の間` とし、スクリプト名もそれに合わせる。

### 受け入れ条件（観測可能）
1. コマンド: `bash scripts/goza_no_ma.sh --help`
   - 期待結果: ヘルプ表示のコマンド例が `goza_no_ma.sh` になる。
2. コマンド: `bash scripts/goza_no_ma.sh -s --no-attach`
   - 期待結果: `tmux` session 名既定値が `goza-no-ma` として作成される。

## 追補（2026-02-11: タブ色のみ適用）
### 要求
1. ペイン本文の文字色は変更しない。
2. タブ（ペイン見出し）色のみを役職別に適用する。
3. 既存 tmux セッションへ再接続した場合も色設定を再適用する。

### 受け入れ条件（観測可能）
1. コマンド: `bash scripts/goza_no_ma.sh --view-only --no-attach --session <existing>`
   - 期待結果: `pane-border-format` に役職別色分岐が設定される。
2. コマンド: `tmux show-options -w -t <existing>:agents | rg '^pane-style'`
   - 期待結果: `pane-style` が設定されず、本文色が変更されない。

## 追補（2026-02-11: zellij/tmux 両モード起動）
### 要求
1. zellij と tmux の両方で起動できること。
2. 実行コマンドでモードを選択できること（zellijコマンド / tmuxコマンド）。

### 受け入れ条件（観測可能）
1. コマンド: `bash scripts/goza_zellij.sh -s --no-attach`
   - 期待結果: zellij モードで `shutsujin_departure.sh` が呼ばれ、zellij 向け起動導線が実行される。
2. コマンド: `bash scripts/goza_tmux.sh -s --no-attach`
   - 期待結果: tmux モードで起動し、`attach shogun/multiagent` の案内が表示される。
3. コマンド: `bash scripts/goza_no_ma.sh --mux tmux -s --no-attach`
   - 期待結果: `--mux` 指定で tmux 強制起動が可能。
4. コマンド: `bash scripts/goza_no_ma.sh --mux zellij -s --no-attach`
   - 期待結果: `--mux` 指定で zellij 強制起動が可能。

## 追補（2026-02-11: README刷新）
### 要求
1. ルート `README.md` を新ツール中心の説明に書き換える。
2. zellij/tmux 両モードの起動コマンドと使い分けが先頭で分かる構成にする。

### 受け入れ条件（観測可能）
1. コマンド: `sed -n '1,120p' README.md`
   - 期待結果: `goza_zellij.sh` / `goza_tmux.sh` / `goza_no_ma.sh --mux` の説明が含まれる。
2. コマンド: `rg -n \"goza_zellij|goza_tmux|--mux\" README.md`
   - 期待結果: 新しい運用コマンドがREADME内に複数箇所で記載される。

## 追補（2026-02-11: README運用補強）
### 要求
1. `Codex/Gemini/LocalAPI` の混在設定例を README に明記する。
2. WSL再起動後の最短起動手順と、誤入力しにくいセッション確認コマンドを README に追加する。

### 受け入れ条件（観測可能）
1. コマンド: `rg -n \"localapi|LOCALAPI_BASE_URL|LOCALAPI_MODEL\" README.md`
   - 期待結果: LocalAPIの設定説明がREADMEに存在する。
2. コマンド: `rg -n \"WSL再起動後の最短手順|zellij list-sessions -n\" README.md`
   - 期待結果: 最短手順と正しいセッション確認コマンドが記載される。

## 追補（2026-02-12: zellij演出強化とCLI依存緩和）
### 要求
1. zellijモードでも tmuxモード相当の出陣演出（バナー）を表示する。
2. zellijの直接attach時に役職の視認性を上げる（タブ名の役職ラベル化）。
3. tmuxモードが `claude` 未導入だけで停止しないようにする（利用可能CLIへのフォールバック）。

### 受け入れ条件（観測可能）
1. コマンド: `bash scripts/shutsujin_zellij.sh -s`
   - 期待結果: 出陣バナー表示後に zellij セッション作成ログが続く。
2. コマンド: `rg -n "rename-tab|role_tab_label" scripts/shutsujin_zellij.sh`
   - 期待結果: zellijタブ名に役職ラベル（絵文字付き）を設定する実装がある。
3. コマンド: `rg -n "resolve_cli_type_for_agent|build_cli_command_with_type|get_first_available_cli" lib/cli_adapter.sh shutsujin_departure.sh`
   - 期待結果: CLI未導入時のフォールバック経路が実装され、tmux起動時に利用される。

## 追補（2026-02-12: 御座の間枠色の役職別適用）
### 要求
1. zellij運用時の御座の間ビューで、枠色を階級別に分ける（全枠黄緑を解消）。
2. `pane-border-format` の崩れ表示（色コード文字列露出）を防ぐ。

### 受け入れ条件（観測可能）
1. コマンド: `rg -n "apply_role_border_styles|role_border_color|pane-border-style|pane-active-border-style" scripts/goza_no_ma.sh`
   - 期待結果: 役職ごとに枠色を適用する処理が存在する。
2. コマンド: `rg -n "pane-border-format" scripts/goza_no_ma.sh`
   - 期待結果: `#{pane_index}:#{pane_title}` の単純形式が使われ、条件式内カンマ衝突を回避している。

## 追補（2026-02-12: tmuxのactive_ashigaru追従）
### 要求
1. tmuxモードでも `topology.active_ashigaru` を反映し、配備人数を動的化する。
2. CLI起動・watcher起動・表示メッセージが active 構成と一致する。

### 受け入れ条件（観測可能）
1. コマンド: `rg -n "ACTIVE_ASHIGARU|MULTIAGENT_IDS|MULTIAGENT_COUNT" shutsujin_departure.sh`
   - 期待結果: active_ashigaru を読み取って配備配列を組み立てる実装がある。
2. コマンド: `rg -n "for i in \\\"\\$\\{!ACTIVE_ASHIGARU\\[@\\]\\}\\\"" shutsujin_departure.sh`
   - 期待結果: 足軽のCLI起動・watcher起動が active_ashigaru のみ対象になっている。
3. コマンド: `rg -n "MULTIAGENT_COUNT" shutsujin_departure.sh`
   - 期待結果: 配備人数・手動起動案内・布陣表示に動的人数が使われている。

## 追補（2026-02-12: CLI起動判定の汎用化 + zellij優先）
### 要求
1. 起動判定を `Claude Code` 固有文字列依存から、各エージェントのCLI種別に基づく判定へ変更する。
2. マルチプレクサ未設定時の既定は `zellij` を優先し、`tmux` はサブ手段とする。
3. 枠色/背景色の変更責務（リポジトリ側とユーザー環境側）をREADMEに明記する。

### 受け入れ条件（観測可能）
1. コマンド: `rg -n "エージェントCLIの起動を確認中|pane_current_command|@agent_cli" shutsujin_departure.sh`
   - 期待結果: CLI種別ベースの起動確認ロジックが存在する。
2. コマンド: `rg -n "MULTIPLEXER_SETTING=\\\"zellij\\\"|MULTIPLEXER_SETTING=\\$\\{MULTIPLEXER_SETTING:-zellij\\}" shutsujin_departure.sh`
   - 期待結果: 既定マルチプレクサが zellij になっている。
3. コマンド: `rg -n "zellij モード優先|zellij attach.*配色|zellij テーマ" README.md`
   - 期待結果: zellij優先方針と配色責務の説明がREADMEに存在する。

## 追補（2026-02-12: tmux/zellij テンプレート運用）
### 要求
1. tmux/zellij それぞれの表示テンプレート定義を用意する。
2. Multi Agents Shogunate の既定起動でテンプレートを適用できるようにする。
3. 既定テンプレートは `shogun_only` とし、`goza_room` を明示指定で利用可能にする。

### 受け入れ条件（観測可能）
1. コマンド: `ls templates/multiplexer/*.yaml`
   - 期待結果: `tmux_templates.yaml` と `zellij_templates.yaml` が存在する。
2. コマンド: `rg -n "--template|shogun_only|goza_room" scripts/goza_no_ma.sh`
   - 期待結果: テンプレート指定オプションと分岐処理がある。
3. コマンド: `rg -n "startup:\\n  template: shogun_only|template: shogun_only" config/settings.yaml first_setup.sh`
   - 期待結果: 既定テンプレートが `shogun_only` に設定されている。

## 追補（2026-02-12: テスト優先の設定反映）
### 要求
1. ユーザー編集なしで `config/settings.yaml` をテストしやすい構成へ更新する。
2. テスト時は全体俯瞰できるよう `startup.template` を `goza_room` にする。

### 受け入れ条件（観測可能）
1. コマンド: `rg -n "startup:|template: goza_room" config/settings.yaml`
   - 期待結果: 既定テンプレートが `goza_room` になっている。

## 追補（2026-02-12: 構成CUI + zellij表示改善）
### 要求
1. 足軽人数と各エージェントCLI種別を、対話的に設定できるCUIを追加する。
2. 起動時バナーの足軽人数表示を `topology.active_ashigaru` に連動させる。
3. `zellij` の御座の間ビューで、将軍ペインを大きく表示する（tmux同等の主従レイアウト）。
4. `zellij` モード起動時にも tmux 相当のAA演出を表示する。

### 受け入れ条件（観測可能）
1. コマンド: `bash scripts/configure_agents.sh` を実行し、対話入力で保存
   - 期待結果: `config/settings.yaml` の `topology.active_ashigaru` と `cli.agents` が入力値どおり更新される。
2. コマンド: `bash scripts/shutsujin_zellij.sh -s`
   - 期待結果: バナーに `【 足 軽 隊 列 ・ N 名 配 備 】` が表示され、`N` が `active_ashigaru` の件数と一致する。
3. コマンド: `bash scripts/goza_no_ma.sh --mux zellij --template goza_room -s --no-attach`
   - 期待結果: 御座の間ビューが作成され、`main-pane-width 65%` を使った将軍優先レイアウトになる。
4. コマンド: `rg -n "show_battle_cry|ACTIVE_ASHIGARU_COUNT|main-pane-width 65%" scripts/shutsujin_zellij.sh scripts/goza_no_ma.sh shutsujin_departure.sh`
   - 期待結果: zellij/tmux両起動系でAA演出と人数連動、将軍優先レイアウトの実装が確認できる。

## 追補（2026-02-12: zellij御座の間の表示責務明確化 + size missing対策）
### 要求
1. `bash scripts/goza_zellij.sh --template goza_room` の動作責務を明確化する（バックエンド=zellij、ビュー=tmux）。
2. `tmux` ビュー生成時の `size missing` エラーを回避する。

### 受け入れ条件（観測可能）
1. コマンド: `rg -n "zellij \\+ goza_room は tmux ビュー" scripts/goza_no_ma.sh README.md`
   - 期待結果: zellij goza_room の表示責務が明示されている。
2. コマンド: `rg -n "TMUX_VIEW_WIDTH|TMUX_VIEW_HEIGHT|tmux new-session -d -x|tmux_split_right_ratio|tmux_split_down_pane" scripts/goza_no_ma.sh README.md`
   - 期待結果: tmux ビューに仮想サイズ指定と分割リトライ処理が実装されている。

## 追補（2026-02-12: 御座の間タブ色反映 + zellij CLI投入安定化）
### 要求
1. 御座の間（tmuxビュー）で、役職別タブ色が確実に反映されること。
2. zellijセッションへのコマンド投入で Enter が効かない環境差分を吸収し、CLI自動起動を安定化すること。

### 受け入れ条件（観測可能）
1. コマンド: `rg -n "pane-border-format|m:\\*shogun\\*|m:\\*karo\\*|m:\\*ashigaru\\*" scripts/goza_no_ma.sh`
   - 期待結果: 役職別のタブ色分岐が `pane-border-format` に実装されている。
2. コマンド: `rg -n "action write 13|action write 10|write-chars \\$'\\\\n'" scripts/shutsujin_zellij.sh scripts/inbox_watcher.sh`
   - 期待結果: zellij Enter送信の互換フォールバックが実装されている。

## 追補（2026-02-12: zellij操作デフォルト + tmux内部運用）
### 要求
1. デフォルト運用は zellij UI とし、内部オーケストレーションは tmux で動作させる。
2. tmux派ユーザー向けに、tmux直接運用導線を維持する。
3. `inotifywait` 未導入時に watcher が即死し続ける問題を起動時に明示し、不要な起動を抑止する。

### 受け入れ条件（観測可能）
1. コマンド: `sed -n '1,40p' scripts/goza_zellij.sh scripts/goza_tmux.sh`
   - 期待結果: `goza_zellij.sh` は `--mux tmux --ui zellij`、`goza_tmux.sh` は `--mux tmux --ui tmux` を呼ぶ。
2. コマンド: `rg -n "--ui|zellij UI \\+ tmux backend|zellij_ui_attach_tmux_target" scripts/goza_no_ma.sh README.md`
   - 期待結果: `--ui` オプションと zellij UI + tmux backend 導線が実装・文書化されている。
3. コマンド: `rg -n "inotifywait 未導入|command -v inotifywait" shutsujin_departure.sh scripts/shutsujin_zellij.sh`
   - 期待結果: watcher 起動前に inotifywait 前提チェックが追加されている。

## 追補（2026-02-12: zellij UI attach の安定化）
### 要求
1. zellij UI モードで「zellijは起動するが tmux attach が走らない」不安定挙動を解消する。
2. `zellij action write-chars` 依存を下げ、セッション起動時に tmux attach を確実に実行する。

### 受け入れ条件（観測可能）
1. コマンド: `rg -n "zellij_ui_layout_file|new-session-with-layout|--layout .*attach -c" scripts/goza_no_ma.sh`
   - 期待結果: zellij UI 起動が layout ベースになっている。
2. コマンド: `bash scripts/goza_zellij.sh --template goza_room`
   - 期待結果: zellij UI 内で tmux 画面（`goza-no-ma`）へ直接入る。

## 追補（2026-02-12: tmux内部運用時のCLI割当可視化）
### 要求
1. `--mux tmux` 運用でも `queue/runtime/agent_cli.tsv` に実割当を記録し、役職ごとのCLI起動結果を確認できるようにする。

### 受け入れ条件（観測可能）
1. コマンド: `rg -n "queue/runtime/agent_cli.tsv|printf .*\\t.*_cli_type" shutsujin_departure.sh`
   - 期待結果: 将軍/家老/足軽のCLI割当が `agent_cli.tsv` に書き込まれる実装がある。
2. コマンド: `bash scripts/goza_zellij.sh --template goza_room`
   - 期待結果: 起動ログに `ashigaru1（...）` / `ashigaru2（...）` のCLI種別が表示される。

## 追補（2026-02-12: 即作業開始の初動自動化）
### 要求
1. 起動後に各エージェントが「ただCLIを開くだけ」で止まらず、役割指示書を自動読込して待機すること。
2. Gemini初回の trust folder プロンプトを自動承認し、手動操作を減らすこと。

### 受け入れ条件（観測可能）
1. コマンド: `rg -n "send_startup_bootstrap_tmux|初動命令を投入" shutsujin_departure.sh`
   - 期待結果: 全エージェントへ初動命令を送る実装がある。
2. コマンド: `rg -n "auto_accept_gemini_trust_prompt_tmux|Do you trust this folder" shutsujin_departure.sh`
   - 期待結果: Gemini trust プロンプト自動承認ロジックがある。

## 追補（2026-02-12: 人間は将軍ペイン固定）
### 要求
1. 起動直後のアクティブペインは将軍に固定する。
2. zellij表示時のペイン切替方法（tmux操作）をREADMEに明記する。

### 受け入れ条件（観測可能）
1. コマンド: `rg -n "tmux_focus_shogun_for_human|select-pane -t .*overview.0|select-window -t .*overview" scripts/goza_no_ma.sh`
   - 期待結果: 御座の間で将軍ペインをアクティブ化する処理がある。
2. コマンド: `rg -n "操作方法（zellij表示時）|Ctrl\\+b|起動直後のアクティブペイン: 将軍" README.md`
   - 期待結果: 人間向けの操作説明がREADMEにある。

## 追補（2026-02-12: 役職別正本MDの必読 + 最適化MD自動同期）
### 要求
1. 起動時に、将軍/家老/足軽それぞれが役職共通の正本MD（`instructions/shogun.md` / `instructions/karo.md` / `instructions/ashigaru.md`）を必ず読む。
2. その後、CLI種別に応じた最適化MD（Codex/Gemini/Claude等）を追読できるようにする。
3. 正本や部品MDが更新された場合、最適化MD（`instructions/generated/*.md`）を自動再生成して起動時に反映する。

### 受け入れ条件（観測可能）
1. コマンド: `rg -n "get_role_instruction_file|send_startup_bootstrap_tmux|send_startup_bootstrap_zellij" lib/cli_adapter.sh shutsujin_departure.sh scripts/shutsujin_zellij.sh`
   - 期待結果: 役職共通MDとCLI最適化MDを分けて扱う実装がある。
2. コマンド: `rg -n "ensure_generated_instructions|ensure_generated_instructions.sh" shutsujin_departure.sh scripts/shutsujin_zellij.sh`
   - 期待結果: 起動時に再生成チェックを実行するフローがある。
3. コマンド: `bash scripts/ensure_generated_instructions.sh`
   - 期待結果: source変更時は `scripts/build_instructions.sh` が実行され、未変更時は up-to-date メッセージを出して終了する。
4. コマンド: `bats tests/unit/test_cli_adapter.bats tests/unit/test_send_wakeup.bats --timing`
   - 期待結果: 全テストPASS（既存の環境依存skipのみ許容）。

## 追補（2026-02-12: zellij表示名の正常化 + 将軍→家老→足軽の連携順序強制）
### 要求
1. `zellij UI + tmux backend` 利用時に、枠タイトルへ長い `bash -lc ...` コマンド文字列が露出しないようにする。
2. 起動初動命令で、将軍・家老・足軽それぞれに「将軍→家老→足軽」連携順序を明示し、役割外の直接連携を抑止する。
3. 実装方針はオリジナルREADME_ja（将軍→家老→足軽の階層連携）に沿う。

### 受け入れ条件（観測可能）
1. コマンド: `rg -n "pane name=|tmux target session not found|zellij_ui_layout_file" scripts/goza_no_ma.sh`
   - 期待結果: zellijレイアウトで pane 名を明示し、attach先tmuxセッション存在チェックがある。
2. コマンド: `rg -n "role_linkage_directive|将軍→家老→足軽|queue/shogun_to_karo.yaml|queue/tasks/ashigaruN.yaml|queue/reports/" shutsujin_departure.sh scripts/shutsujin_zellij.sh`
   - 期待結果: 役職別の連携順序ルールが初動命令へ組み込まれている。
3. コマンド: `bash -n scripts/goza_no_ma.sh shutsujin_departure.sh scripts/shutsujin_zellij.sh`
   - 期待結果: 構文エラーなし。

## 追補（2026-02-12: 足軽AAの人数連動 + zellij KDLクォート修正）
### 要求
1. 起動バナーの足軽AAを `topology.active_ashigaru` の人数に応じて増減させる。
2. `goza_zellij` 起動時の `Failed to parse Zellij configuration`（KDLクォート崩れ）を解消する。

### 受け入れ条件（観測可能）
1. コマンド: `rg -n "render_ashigaru_ascii|ACTIVE_ASHIGARU_COUNT" shutsujin_departure.sh scripts/shutsujin_zellij.sh`
   - 期待結果: 両起動スクリプトで人数連動のAA描画関数が使われている。
2. コマンド: `rg -n "kdl_escape|tmux_attach_session_cmd|args \\\"-lc\\\"" scripts/goza_no_ma.sh`
   - 期待結果: zellij layout 生成時にKDLエスケープ処理がある。
3. コマンド: `bash -n scripts/goza_no_ma.sh shutsujin_departure.sh scripts/shutsujin_zellij.sh`
   - 期待結果: 構文エラーなし。
