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
