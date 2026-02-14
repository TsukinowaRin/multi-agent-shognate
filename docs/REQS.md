# Requirements (Normalized)

最終更新: 2026-02-14
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

## 追補（2026-02-14: 複数家老時の足軽均等割り振り）
### 要求
1. 家老が複数人（`karo1..karoN`）のとき、足軽を起動時にラウンドロビンで均等割り振りする。
2. 割り振り結果を `queue/runtime/ashigaru_owner.tsv` に保存する（`ashigaru<TAB>karo`）。
3. 足軽は担当家老にのみ報告可能とし、非担当家老宛は拒否する。
4. 家老同士の直接通信を禁止する。
5. 単一家老（`karo`）時は既存挙動を維持する。

### 受け入れ条件（観測可能）
1. コマンド: `bash shutsujin_departure.sh -s`（`karo_count>=2` となる設定）
   - 期待結果: `queue/runtime/ashigaru_owner.tsv` が再生成され、全足軽に担当家老が1件ずつ割り当たる。
2. コマンド: `awk -F '\t' 'NF>=2{c[$2]++} END{min=-1; max=0; for(k in c){if(min<0||c[k]<min)min=c[k]; if(c[k]>max)max=c[k]} print max-min}' queue/runtime/ashigaru_owner.tsv`
   - 期待結果: 出力が `0` または `1`（家老間の人数差が最大1）。
3. コマンド: `bash scripts/inbox_write.sh karo1 "x" report_received ashigaru9`（owner が `karo2` の場合）
   - 期待結果: エラー終了し、非担当宛送信拒否メッセージが出る。
4. コマンド: `bash scripts/inbox_write.sh karo2 "x" report_received ashigaru9`（owner が `karo2` の場合）
   - 期待結果: 正常終了し、`queue/inbox/karo2.yaml` に追記される。
5. コマンド: `bats tests/unit/test_send_wakeup.bats tests/unit/test_topology_adapter.bats tests/test_inbox_write.bats`
   - 期待結果: 全テストPASS（SKIPなし）。

### 仮定
1. 家老複数化の命名規則は `karo1..karoN` を採用し、起動中の動的再配分は行わない。
2. 既存の `queue/tasks/ashigaruN.yaml` と `queue/reports/ashigaruN_report.yaml` の命名は変更しない。

## 追補（2026-02-14: tmux/zellij 起動挙動の同一化）
### 要求
1. `tmux` と `zellij` の起動で、`queue/inbox` の準備挙動を同一化する（常にローカルディレクトリとして扱う）。
2. `queue/inbox` が壊れた状態（ファイル化・擬似symlink化）でも、起動時に自動復旧する。
3. 起動モード差によらず、inbox watcher が同じ inbox パス前提で動作できること。

### 受け入れ条件（観測可能）
1. コマンド: `bash shutsujin_departure.sh -s` と `bash scripts/shutsujin_zellij.sh -s`
   - 期待結果: どちらの起動後も `test -d queue/inbox` が成功する。
2. コマンド: `printf '/tmp/fake\n' > queue/inbox && bash scripts/inbox_write.sh shogun "x"`
   - 期待結果: `queue/inbox` がディレクトリへ復旧し、`queue/inbox/shogun.yaml` が作成される。
3. コマンド: `bats tests/unit/test_mux_parity.bats tests/test_inbox_write.bats`
   - 期待結果: PASS。
4. コマンド: `bash scripts/goza_no_ma.sh --mux zellij --ui zellij --template goza_room -s --no-attach`
   - 期待結果: `topology.karo` が複数家老を返す設定時、`goza_no_ma` が `karo1..karoN` を編成対象として扱う（単一家老固定にならない）。
5. コマンド: `bash scripts/mux_parity_smoke.sh --dry-run`
   - 期待結果: `MAS_MULTIPLEXER=tmux` と `MAS_MULTIPLEXER=zellij` の setup-only コマンドが両方表示される。
6. コマンド: `bash scripts/mux_parity_smoke.sh`
   - 期待結果: 両モード setup-only が成功した環境では `owner map parity: tmux == zellij` が表示される。
7. コマンド: `bash scripts/mux_parity_smoke.sh`
   - 期待結果: 両モード setup-only 後に `queue/ntfy_inbox.yaml` が存在し、通知inboxの初期化挙動が一致する。

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

## 追補（2026-02-12: 初動自動送信・イベント駆動安定化・言語統一）
### 要求
1. 起動直後の最初の命令は、ユーザー手動Enterなしで自動送信されること（Ready後すぐ人間が入力できる状態）。
2. Gemini既定モデルを `auto` とし、CLI側に最新モデル選択を委ねること。
3. 全エージェント運用をイベント駆動優先とし、watcherの過剰エスカレーション（`/new` 割り込み）を抑止すること。
4. システム言語（`config/settings.yaml` の `language`）を、将軍/家老/足軽の全初動命令に反映すること。
5. 家老→将軍→人間の報告フロー、および「将軍は原則家老へ委譲」を初動命令へ明示すること。
6. 人間向けの履歴要約「歴史書」を自動生成すること。
7. zellij UI（tmux backend表示）で下部操作バー（status/help）を表示し、操作導線を復元すること。

### 受け入れ条件（観測可能）
1. コマンド: `rg -n "send_startup_bootstrap_tmux|language_directive|event_driven_directive|ready:" shutsujin_departure.sh scripts/shutsujin_zellij.sh`
   - 期待結果: 初動命令に言語指定・イベント駆動指定・ready応答指示が含まれている。
2. コマンド: `rg -n "ASW_DISABLE_ESCALATION=1|ASW_PROCESS_TIMEOUT=0" shutsujin_departure.sh scripts/shutsujin_zellij.sh`
   - 期待結果: watcher起動時にエスカレーション抑止設定が適用される。
3. コマンド: `rg -n "model: auto|gemini model|gemini --yolo" lib/cli_adapter.sh config/settings.yaml README.md`
   - 期待結果: Gemini既定モデル・設定例が `auto` 運用へ更新される。
4. コマンド: `bash scripts/history_book.sh && sed -n '1,80p' queue/history/rekishi_book.md`
   - 期待結果: 歴史書が生成され、直近のcmd/タスク/報告要約が人間可読で記録される。
5. コマンド: `rg -n "default_tab_template|zellij:status-bar|zellij:tab-bar" scripts/goza_no_ma.sh`
   - 期待結果: zellij UI layoutにstatus/tab bar pluginが含まれる。

## 追補（2026-02-12: pure zellij / hybrid / tmux の運用分離 + Gemini高負荷再試行）
### 要求
1. `zellij` 操作をそのまま使いたい場合に、tmux内包なしの pure zellij モードで起動できること。
2. 御座の間俯瞰（tmux画面）を使いたい場合に、hybrid モード（tmux backend + zellij ui）を明示コマンドで起動できること。
3. Gemini CLI が `We are currently experiencing high demand` を返したとき、tmux/hybrid起動では `Keep trying` を自動選択して再試行すること。

### 受け入れ条件（観測可能）
1. コマンド: `sed -n '1,40p' scripts/goza_zellij.sh scripts/goza_hybrid.sh scripts/goza_tmux.sh`
   - 期待結果: `goza_zellij.sh` は `--mux zellij --ui zellij`、`goza_hybrid.sh` は `--mux tmux --ui zellij`、`goza_tmux.sh` は `--mux tmux --ui tmux` を呼ぶ。
2. コマンド: `rg -n "pure zellij|goza_hybrid|goza_room 俯瞰ビューは未対応" scripts/goza_no_ma.sh README.md`
   - 期待結果: pure zellij と hybrid の責務分離が明記されている。
3. コマンド: `rg -n "auto_retry_gemini_busy_tmux|experiencing high demand|Keep trying" shutsujin_departure.sh README.md`
   - 期待結果: Gemini高負荷時の自動再試行処理と運用説明が存在する。

## 追補（2026-02-12: pure zellij の goza_room ペイン分割表示）
### 要求
1. `goza_zellij.sh --template goza_room` で、pure zellij のまま複数ペイン（将軍/家老/足軽）を表示すること。
2. 起動直後に将軍ペインが見える（単一の素のコマンドライン画面で終わらない）こと。

### 受け入れ条件（観測可能）
1. コマンド: `rg -n "zellij_pure_goza_layout_file|zellij_pure_attach_goza_room|zellij_agent_attach_cmd|pure zellij 御座の間" scripts/goza_no_ma.sh`
   - 期待結果: pure zellij goza_room 用のlayout生成と起動処理が存在する。
2. コマンド: `rg -n "zellij_agent_pane_cmd|export AGENT_ID|build_cli_command_with_type" scripts/goza_no_ma.sh`
   - 期待結果: ネストattachではなく、pane内でエージェントCLIを直接起動する実装がある。
3. コマンド: `bash scripts/goza_zellij.sh --template goza_room`
   - 期待結果: zellijで分割ペイン表示が開き、`shogun` ペインが表示される。

## 追補（2026-02-13: pure zellij goza_room の縦長優先レイアウト）
### 要求
1. `goza_zellij.sh --template goza_room` の表示が横長すぎる問題を解消する。
2. 将軍ペインを最も大きい縦長領域にし、家老は次点サイズ、足軽は小さな正方形に近いグリッドで右下へまとめる。
3. active 足軽数（`topology.active_ashigaru`）が増減しても、足軽領域でコンパクト配置を維持する。

### 受け入れ条件（観測可能）
1. コマンド: `rg -n "zellij_emit_ashigaru_grid|zellij_emit_ashigaru_row|pane split_direction=\\\"horizontal\\\"|size=\\\"66%\\\"|size=\\\"58%\\\"" scripts/goza_no_ma.sh`
   - 期待結果: pure zellij layout 生成に、将軍優先の左右分割・家老優先の右上配置・足軽グリッド生成が実装されている。
2. コマンド: `bash scripts/goza_zellij.sh --template goza_room`
   - 期待結果: 起動後、左に将軍の大ペイン、右上に家老、右下に足軽の小型グリッドが表示される。
3. コマンド: `bash -n scripts/goza_no_ma.sh`
   - 期待結果: 構文エラーなし。

## 追補（2026-02-13: pure zellij 初動命令の自動注入）
### 要求
1. pure zellij の `goza_room` 起動直後に、将軍/家老/足軽へ初動命令を自動注入する。
2. 人間は起動後すぐに将軍へ入力できる状態にする（手動で最初のEnterを押さない）。
3. 初動命令は「入力欄への挿入」だけで止まらず、送信（Enter確定）まで自動実行する。

### 受け入れ条件（観測可能）
1. コマンド: `rg -n "zellij_bootstrap_pure_goza_background|goza_startup_bootstrap_message|ready:" scripts/goza_no_ma.sh`
   - 期待結果: pure zellij 向けの初動命令生成と自動注入処理が存在する。
2. コマンド: `rg -n "focus-next-pane|focus=true" scripts/goza_no_ma.sh`
   - 期待結果: 起動時フォーカスを将軍に置きつつ、各paneへ順次初動命令を投入する実装がある。
3. コマンド: `rg -n "write-chars .*\\$'\\\\r'|action write 13|action write 10" scripts/goza_no_ma.sh`
   - 期待結果: 改行同梱送信と改行キー送信のフォールバックが実装されている。
4. コマンド: `bash scripts/goza_zellij.sh --template goza_room`
   - 期待結果: 起動後、将軍/家老/足軽の各paneに初動命令が自動投入され、将軍paneがアクティブになる。

## 追補（2026-02-13: pure zellij 初動送信の安定化）
### 要求
1. Codex で「文面は注入されるが送信されない」事象を解消する。
2. Gemini で「CLI起動前に初動命令が送られる」事象を抑止する。
3. 足軽ペインを縦長ではなく正方形寄りにする。

### 受け入れ条件（観測可能）
1. コマンド: `rg -n "zellij_send_line_to_session|action write 13|action write 10" scripts/goza_no_ma.sh`
   - 期待結果: 初動送信が Enter キー送信を優先し、再試行する実装がある。
2. コマンド: `rg -n "wait_sec|gemini\\) wait_sec=|for attempt in 1 2 3" scripts/goza_no_ma.sh`
   - 期待結果: CLI種別に応じた待機と再送で、起動前送信を抑止する実装がある（`gemini/codex/others` の待機差分）。
3. コマンド: `rg -n "size=\\\"46%\\\"|size=\\\"32%\\\"|size=\\\"22%\\\"|count == 2|split_direction=\\\"horizontal\\\"" scripts/goza_no_ma.sh`
   - 期待結果: 将軍・家老の縦長優先と、足軽の正方形寄り配置が実装されている。

## 追補（2026-02-13: Claude連携の実機検証）
### 要求
1. Claude Code導入済み環境で、将軍/家老を Claude 起動へ切り替えて検証できること。
2. Gemini/Codex は Auto 方針（モデル固定しない）を維持すること。

### 受け入れ条件（観測可能）
1. コマンド: `claude --version`
   - 期待結果: Claude Code CLI のバージョンが表示される。
2. コマンド: `source lib/cli_adapter.sh && resolve_cli_type_for_agent shogun && build_cli_command shogun`
   - 期待結果: `claude` が解決され、`claude --dangerously-skip-permissions` 系コマンドが返る。
3. コマンド: `bash scripts/goza_zellij.sh --template goza_room`
   - 期待結果: 将軍/家老ペインで Claude が起動し、初動命令が自動送信される。

## 追補（2026-02-13: 役職別CLI配備の固定 + 初動注入先ずれ修正）
### 要求
1. 役職CLI配備を以下へ固定する。
   - 将軍: Claude Code
   - 家老: Codex
   - 足軽: Gemini CLI
2. pure zellij の初動注入で、役職ごとの命令が別ペインへずれる問題を解消する。
3. 足軽2名時はコンパクト表示を維持しつつ、注入順序を安定させる。

### 受け入れ条件（観測可能）
1. コマンド: `cat config/settings.yaml`
   - 期待結果: `shogun=claude`, `karo=codex`, `ashigaru1/2=gemini` になっている。
2. コマンド: `rg -n "zellij_focus_shogun_anchor|zellij_focus_direction|zellij_send_bootstrap_current_pane" scripts/goza_no_ma.sh`
   - 期待結果: 将軍アンカーへ寄せてから役職順に注入する処理がある。
3. コマンド: `rg -n "count -ge 4|focus_direction.*down|for attempt in 1 2 3" scripts/goza_no_ma.sh`
   - 期待結果: 4ペイン構成（将軍/家老/足軽1/足軽2）の順次注入と再試行が実装されている。

## 追補（2026-02-13: 足軽2沈黙/足軽1読込失敗の改善）
### 要求
1. pure zellij `goza_room` で `ashigaru2` が沈黙しないよう、4ペイン注入順（将軍→家老→足軽1→足軽2）をレイアウトに対して安定化する。
2. `ashigaru1`（Gemini）が起動直後にファイル読込を失敗しにくいよう、初期ゲート（trust/high-demand）を跨いだ初動投入へ改善する。
3. Gemini向け初動文面は `@AGENTS.md` / `@instructions/...` を明示し、読込対象を機械的に解釈しやすい形式にする。

### 受け入れ条件（観測可能）
1. コマンド: `rg -n "zellij_focus_agent_index|zellij_prepare_gemini_gate_current_pane|for idx in \"\\$\\{!agents\\[@\\]\\}\"" scripts/goza_no_ma.sh`
   - 期待結果: 注入対象ペインをインデックスで再フォーカスして送る実装と、Gemini向け初期ゲート対策が存在する。
2. コマンド: `rg -n "この順で読む: @AGENTS.md" scripts/goza_no_ma.sh`
   - 期待結果: Gemini向け初動命令に `@` 形式の明示的読込指示が含まれる。
3. コマンド: `bash scripts/goza_zellij.sh --template goza_room`
   - 期待結果: 将軍/家老/足軽1/足軽2の各ペインで初動命令が自動送信され、`ashigaru2` が沈黙しない。

## 追補（2026-02-13: 足軽増員時の初動注入スケーラビリティ）
### 要求
1. 足軽が増えても、初動注入がフォーカス移動順序に依存してズレないこと。
2. pure zellij の各ペインで、対象エージェント自身が初動命令を受け取ること（役職混線しないこと）。

### 受け入れ条件（観測可能）
1. コマンド: `rg -n "bootstrap_line=|tty_path=\\\"\\$\\(tty\\)\\\"|printf \\\"%s\\\\r\\\" \\\"\\$bootstrap_line\\\"" scripts/goza_no_ma.sh`
   - 期待結果: 各pane内のTTYへ初動命令を直接送る実装が存在する。
2. コマンド: `rg -n "pure zellij では各pane内で自動初動送信" scripts/goza_no_ma.sh`
   - 期待結果: 外部フォーカス注入ではなく、pane内送信方式を採用している。
3. コマンド: `bash scripts/goza_zellij.sh --template goza_room`（`active_ashigaru` を3名以上に設定）
   - 期待結果: 増員構成でも各足軽ペインが自分向け初動命令を受け取り、沈黙しない。

## 追補（2026-02-13: 足軽9名以上対応 + watcher同期ずれ改善）
### 要求
1. 足軽人数の上限を撤廃し、`active_ashigaru` で `ashigaru9` 以上を指定しても起動できること。
2. `shutsujin_departure.sh` / `shutsujin_zellij.sh` / `goza_no_ma.sh` で `ashigaruN` パースを 9以上に対応させること。
3. `watcher_supervisor.sh` で stale pane を掴んだ watcher を再同期し、偽通知ループ（同期ずれ）を抑止すること。
4. CUI設定 (`configure_agents.sh`) で足軽人数入力を 9以上へ拡張すること。

### 受け入れ条件（観測可能）
1. コマンド: `rg -n "ashigaru\\[1-9\\]\\[0-9\\]\\*|i >= 1|x >= 1" shutsujin_departure.sh scripts/shutsujin_zellij.sh scripts/goza_no_ma.sh scripts/configure_agents.sh`
   - 期待結果: 足軽番号の上限固定（1..8）が撤廃されている。
2. コマンド: `rg -n "ASW_DISABLE_ESCALATION=1 ASW_PROCESS_TIMEOUT=0 ASW_DISABLE_NORMAL_NUDGE=0|scripts/inbox_watcher.sh \\$\\{agent\\} \\$\\{pane\\}" scripts/watcher_supervisor.sh`
   - 期待結果: supervisor 起動 watcher に安全フラグが付き、pane不一致時に再同期する実装がある。
3. コマンド: `bash -n shutsujin_departure.sh scripts/shutsujin_zellij.sh scripts/goza_no_ma.sh scripts/configure_agents.sh scripts/watcher_supervisor.sh`
   - 期待結果: 構文エラーなし。

## 追補（2026-02-14: 上流リポジトリ更新の同期）
### 要求
1. 上流 `yohey-w/multi-agent-shogun` の直近更新を確認し、本リポジトリに必要な更新を判断してDocsへ記録する。
2. 上流更新のうち、実運用に直結する改善を本リポジトリへ反映する。
   - Codex CLI の `--model` 対応
   - inbox watcher の self-watch 誤検知抑止
3. 上流との差分適用結果（採用/非採用）を追跡可能にする。

### 受け入れ条件（観測可能）
1. コマンド: `sed -n '1,220p' docs/UPSTREAM_SYNC_2026-02-14.md`
   - 期待結果: 上流主要更新、採用/非採用、反映理由が記録されている。
2. コマンド: `source lib/cli_adapter.sh && CLI_ADAPTER_SETTINGS=/tmp/nonexistent true`
   - 期待結果: 構文エラーなく読み込める。
3. コマンド: `rg -n "codex --model|_cli_adapter_get_configured_model" lib/cli_adapter.sh`
   - 期待結果: Codex model指定の実装が存在する。
4. コマンド: `rg -n "agent_has_self_watch\(|PGID|non-Claude|claude" scripts/inbox_watcher.sh`
   - 期待結果: self-watch判定がclaude限定 + PGID除外で実装されている。
5. コマンド: `bats tests/unit/test_cli_adapter.bats tests/unit/test_send_wakeup.bats`
   - 期待結果: 全テストPASS。

## 追補（2026-02-14: 実機テストで判明した起動不具合の修正）
### 要求
1. pure zellij (`goza_zellij.sh --template goza_room`) 起動時に、将軍/家老/足軽へ初動プロンプトが自動送信されること。
2. tmux UI (`goza_tmux.sh`) 起動時に、実行後そのままtmuxへアタッチされること（ネスト環境でも接続失敗しにくいこと）。
3. 起動待機の体感遅延を抑えるため、`goza_no_ma.sh` 経由時のCLI起動確認タイムアウトを短縮可能にすること。

### 受け入れ条件（観測可能）
1. コマンド: `bash scripts/goza_zellij.sh --template goza_room`
   - 期待結果: 起動直後に各役職へ初動命令が自動送信される（ready送信指示を含む）。
2. コマンド: `bash scripts/goza_tmux.sh --template goza_room`
   - 期待結果: 実行後に tmux 画面へ遷移する（失敗時は明示エラー）。
3. コマンド: `rg -n "zellij_bootstrap_pure_goza_background|TMUX= tmux attach|MAS_CLI_READY_TIMEOUT" scripts/goza_no_ma.sh shutsujin_departure.sh`
   - 期待結果: 初動注入の背景送信、tmux attachの`TMUX=`明示、タイムアウト設定が実装されている。
