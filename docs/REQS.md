# Requirements (Normalized)

最終更新: 2026-03-11
出典: 直近ユーザープロンプト

## 追補（2026-03-11: live CLI設定の次回起動反映）
### 要求
1. 各 pane 内で変更した `model` や `reasoning/thinking` のうち、判別可能なものは起動中に約1秒以内で `config/settings.yaml` へ同期すること。
2. 同期は `tmux` の live pane を監視する daemon により継続実行され、次回 `shutsujin_departure.sh` 起動前に既に反映済みであること。
3. 最初の対応対象は `Codex` と `Gemini` とし、`Codex` は `model / reasoning_effort`、`Gemini` は `model` と alias 判別可能な `thinking_level / thinking_budget` を扱うこと。
4. tmux session が存在しない場合は no-op で終了し、起動を妨げないこと。

### 受け入れ条件（観測可能）
1. コマンド: `python3 scripts/sync_runtime_cli_preferences.py`
   - 期待結果: 実行中 tmux pane が存在する場合、`queue/runtime/runtime_cli_prefs.tsv` が生成され、判別できた live 設定が `config/settings.yaml` へ反映される。
2. コマンド: `bash shutsujin_departure.sh`
   - 期待結果: 起動中に `runtime_cli_pref_daemon` が起動し、live 変更が約1秒以内に `config/settings.yaml` へ反映される。
3. コマンド: `bats tests/unit/test_sync_runtime_cli_preferences.bats`
   - 期待結果: fake tmux fixture 上で `Codex` と `Gemini` の live 設定が YAML へ同期される。

## 追補（2026-03-11: tmux御座の間復活 + csg alias）
### 要求
1. `gunshi` へは `csg` で短縮 attach できること。
2. `tmux` ベースで `shogun / gunshi / multiagent` を一望できる `御座の間` を復活させること。
3. `御座の間` は `scripts/goza_no_ma.sh` から起動し、`zellij` を再導入しないこと。
4. `cgo` と通常の `goza_no_ma.sh` は、既存の `shogun / gunshi / multiagent` session を再利用し、不要な再起動をしないこと。
5. backend 起動は `--ensure-backend` または `-s` 指定時だけ行い、通常の `goza_no_ma.sh` では自動起動しないこと。
6. `first_setup.sh` / `README` / `shutsujin_departure.sh` の導線は `csg` と `御座の間` を含むこと。
7. `御座の間` の pane 優先度は `shogun > karo > gunshi > ashigaru` とし、将軍が最大、家老が次点、軍師が三番目、足軽はそれ以下の compact pane とすること。

### 受け入れ条件（観測可能）
1. コマンド: `bash scripts/goza_no_ma.sh --no-attach`
   - 期待結果: 既存 backend session がある場合、`shutsujin_departure.sh` を再実行せずに `tmux` ベースの `goza-no-ma` session が準備される。
2. コマンド: `rg -n "alias csg=|alias cgo=" first_setup.sh`
   - 期待結果: `csg` と `cgo` の alias 追加処理が存在する。
3. コマンド: `rg -n "csg|cgo|goza_no_ma\\.sh|--ensure-backend|御座の間" README.md README_ja.md shutsujin_departure.sh first_setup.sh`
   - 期待結果: ユーザー向け導線に `軍師 attach` と `既存 backend 再利用` 前提の `御座の間` が含まれる。
4. コマンド: `bash -n scripts/goza_no_ma.sh first_setup.sh shutsujin_departure.sh`
   - 期待結果: `tmux` 専用 `御座の間` 導線に構文エラーがない。
5. コマンド: `rg -n "discover_karo_target|discover_ashigaru_targets|goza_mirror_pane\\.sh|split-window -h -p 54|split-window -v -p 36|split-window -h -p 44" scripts/goza_no_ma.sh`
   - 期待結果: `御座の間` が `shogun > karo > gunshi > ashigaru` の優先度で独立 mirror pane を構成している。

## 追補（2026-03-11: tmux 実機テスト導線の安定化）
### 要求
1. `shutsujin_departure.sh` は `.venv` や `requirements.txt` が無くても、`python3 + PyYAML` が利用可能なら起動を継続できること。
2. `lib/cli_adapter.sh` は `.venv/bin/python3` を固定参照せず、利用可能な Python 実行系へフォールバックすること。
3. `shutsujin_departure.sh -s` は tmux セッション生成まで通り、通常起動 `bash shutsujin_departure.sh` は CLI 起動・初動命令配信・watcher 起動・完了メッセージまで返ること。
4. `Codex` が起動直後に `Working` へ遷移しても ready 判定で待ち続けないこと。

### 受け入れ条件（観測可能）
1. コマンド: `bash -n shutsujin_departure.sh lib/cli_adapter.sh`
   - 期待結果: Python 導線修正後も構文エラーがない。
2. コマンド: `bats tests/unit/test_cli_adapter.bats tests/unit/test_configure_agents.bats tests/unit/test_send_wakeup.bats tests/unit/test_sync_gemini_settings.bats tests/unit/test_sync_opencode_config.bats tests/unit/test_topology_adapter.bats`
   - 期待結果: Python フォールバックと ready 判定変更後も関連回帰テストが PASS する。
3. コマンド: `bash shutsujin_departure.sh -s`
   - 期待結果: `gunshi` / `multiagent` / `shogun` の tmux セッションが作成され、セットアップのみモードの完了メッセージが返る。
4. コマンド: `bash shutsujin_departure.sh`
   - 期待結果: `CLI起動確認` が `Codex` の `Working` 状態を ready とみなし、初動命令配信・watcher 起動・完了メッセージまで返る。

## 追補（2026-03-11: upstream 正本 + CLI拡張限定）
### 要求
1. 今後の現役実装は `upstream/main` の `tmux` 本線を正本とし、このフォーク独自の差分は CLI 拡張に限定すること。
2. `zellij` / `goza` / hybrid multiplexer の再導入は行わず、起動入口は `shutsujin_departure.sh` を維持すること。
3. 独自機能として維持・再実装する対象は、少なくとも以下に限定すること。
   - `Gemini CLI`
   - `OpenCode`
   - `Kilo`
   - `localapi`
   - `Ollama` / `LM Studio` 向け provider 設定
   - `gunshi` を含む役職別 CLI / model / thinking 設定
4. `README.md` / `README_ja.md` / `first_setup.sh` / `docs` は、上流との差分が「tmux 本線 + 追加 CLI」に収束していると人間が判断できる形へ整理すること。
5. `Waste/` は廃止 multiplexer 実装の退避先として維持し、現役運用手順からは参照させないこと。

### 受け入れ条件（観測可能）
1. コマンド: `rg -n "zellij|goza|hybrid" README.md README_ja.md first_setup.sh docs -g '!Waste/**'`
   - 期待結果: 現役運用としての `zellij/goza/hybrid` 手順は出現せず、履歴文書または廃止記録に限定される。
2. コマンド: `rg -n "gemini|opencode|kilo|localapi|ollama|lmstudio|gunshi" README.md README_ja.md first_setup.sh scripts/configure_agents.sh lib/cli_adapter.sh`
   - 期待結果: このフォーク独自の現役差分が CLI 拡張に集中していることを確認できる。
3. コマンド: `bash -n shutsujin_departure.sh first_setup.sh scripts/configure_agents.sh`
   - 期待結果: upstream 正本ベースへ寄せた後も主要導線に構文エラーがない。
4. コマンド: `bats tests/unit/test_build_system.bats tests/unit/test_cli_adapter.bats tests/unit/test_configure_agents.bats tests/unit/test_mux_parity.bats tests/unit/test_mux_parity_smoke.bats tests/unit/test_ntfy_auth.bats tests/unit/test_send_wakeup.bats tests/unit/test_sync_gemini_settings.bats tests/unit/test_sync_opencode_config.bats tests/unit/test_topology_adapter.bats`
   - 期待結果: tmux 本線 + CLI 拡張の回帰テストが PASS する。

## 追補（2026-03-11: shutsujin_departure 一本化・goza 廃止）
### 要求
1. このリポジトリのマルチプレクサ対応は `tmux` のみに一本化すること。
2. 現役の起動入口は `shutsujin_departure.sh` のみに一本化し、`goza*` は現役コードから外すこと。
3. `goza*` / `shutsujin_zellij.sh` / 旧テンプレート / 旧 bat ランチャーは、ワークスペース内の `Waste/` 配下へ退避すること。
4. `config/settings.yaml` / `scripts/configure_agents.sh` / `first_setup.sh` / `README.md` から `startup.template` と `goza_room` 前提を外すこと。
5. root instruction と generated instruction から、現役運用としての `zellij` / `goza` 手順を外し、`tmux` 前提へ更新すること。

### 受け入れ条件（観測可能）
1. コマンド: `rg -n "goza_|goza_room|shogun_only|startup.template|scripts/shutsujin_zellij.sh|--mux zellij|--ui zellij|zellij action" README.md first_setup.sh scripts config .gitignore -g '!Waste/**'`
   - 期待結果: 現役運用ファイルから `goza` / `zellij` 前提の記述が除去される。
2. コマンド: `find Waste -maxdepth 3 -type f | sort`
   - 期待結果: 旧 `zellij` 実装に加え、`goza*` / `shutsujin_zellij.sh` / 旧 template / 旧 bat ランチャーが `Waste/` 配下へ退避されている。
3. コマンド: `bash -n shutsujin_departure.sh scripts/configure_agents.sh scripts/inbox_watcher.sh scripts/watcher_supervisor.sh first_setup.sh scripts/mux_parity_smoke.sh`
   - 期待結果: `shutsujin_departure.sh` 一本化後も主要シェルスクリプトに構文エラーがない。
4. コマンド: `bats tests/unit/test_build_system.bats tests/unit/test_cli_adapter.bats tests/unit/test_configure_agents.bats tests/unit/test_mux_parity.bats tests/unit/test_mux_parity_smoke.bats tests/unit/test_ntfy_auth.bats tests/unit/test_send_wakeup.bats tests/unit/test_sync_gemini_settings.bats tests/unit/test_sync_opencode_config.bats tests/unit/test_topology_adapter.bats`
   - 期待結果: tmux 一本化後の残存 unit test が PASS する。

## 追補（2026-03-11: merge 後の健全性確認）
### 要求
1. 直近マージ後の現在ブランチについて、conflict marker や構文破綻が残っていないことを確認すること。
2. 直近マージ差分が `docs/` と root instruction 群に限定されている前提で、既存 unit test 群が回帰していないことを確認すること。
3. もし破綻が無ければ、少なくとも「どこを確認して問題が無かったか」を人間が追える形で残すこと。

### 受け入れ条件（観測可能）
1. コマンド: `rg -n "^(<<<<<<<|=======|>>>>>>>)" -S .`
   - 期待結果: conflict marker が検出されない。
2. コマンド: `bats tests/unit/test_build_system.bats tests/unit/test_cli_adapter.bats tests/unit/test_configure_agents.bats tests/unit/test_goza_pure_bootstrap.bats tests/unit/test_goza_wrapper_modes.bats tests/unit/test_interactive_agent_runner.bats tests/unit/test_mux_parity.bats tests/unit/test_ntfy_auth.bats tests/unit/test_send_wakeup.bats tests/unit/test_sync_gemini_settings.bats tests/unit/test_sync_opencode_config.bats tests/unit/test_topology_adapter.bats tests/unit/test_zellij_bootstrap_delivery.bats`
   - 期待結果: 全 235 テストが PASS する。
3. コマンド: `git diff --stat --summary HEAD~1..HEAD`
   - 期待結果: 直近マージ相当の差分が `docs/` と root instruction 群中心であることを確認できる。

## 追補（2026-03-11: upstream compaction recovery 反映）
### 要求
1. upstream `2ef81f9` の趣旨に従い、compaction 後は system message が "Continue the conversation from where it left off." であっても instructions file の再読を必須とすること。
2. このフォークでは `CLAUDE.md` だけでなく、`AGENTS.md` / `.github/copilot-instructions.md` / `agents/default/system.md` にも同等の `Post-Compaction Recovery` を持たせること。
3. 再開手順では persona / speech style / forbidden actions は compaction summary では復元されない前提を明記すること。

### 受け入れ条件（観測可能）
1. コマンド: `git show 2ef81f974bbb633a0cdfe00566671d8a64d5f462 -- CLAUDE.md`
   - 期待結果: upstream 側の変更が `Post-Compaction Recovery (CRITICAL)` 追加であることを確認できる。
2. コマンド: `rg -n "Post-Compaction Recovery|Continue the conversation from where it left off|Compaction summaries do NOT preserve persona" CLAUDE.md AGENTS.md .github/copilot-instructions.md agents/default/system.md`
   - 期待結果: root instruction 群すべてに compaction 復帰節が存在する。
3. コマンド: `rg -n "Session Start Step 3 again|Re-read your instructions file" CLAUDE.md AGENTS.md .github/copilot-instructions.md agents/default/system.md`
   - 期待結果: 再開前に instructions 再読を強制する文言が存在する。

## 追補（2026-03-11: pure zellij の wide 画面での可用性改善）
### 要求
1. pure `zellij` の `goza_room` は、ウィンドウ最大化時でも `shogun` / `karo` / `gunshi` / `ashigaru` の主要 pane が読みやすい配置であること。
2. `shogun` は full-height の最大 pane とし、`karo` はその次に大きい full-height pane とすること。
3. `gunshi` は `shogun` と同列に押し込めず、右列上段へ分離すること。
4. 足軽 pane は compact に維持しつつも、最大化時に `Codex` / `Gemini` の入力欄や直近ログが横方向に破綻しないこと。

### 受け入れ条件（観測可能）
1. コマンド: `bats tests/unit/test_goza_pure_bootstrap.bats`
   - 期待結果: wide layout の既定比率と `shogun full-height / gunshi 右列上段` 構造を含む pure zellij テストが PASS する。
2. コマンド: `rg -n "GOZA_PURE_LEFT_WIDTH|GOZA_PURE_MIDDLE_WIDTH|GOZA_PURE_RIGHT_WIDTH|GOZA_PURE_GUNSHI_HEIGHT" scripts/goza_no_ma.sh`
   - 期待結果: wide 画面向けの既定比率と gunshi 高さ設定がコード上に存在する。
3. コマンド: `rg -n 'zellij_emit_agent_leaf \"            \" \"\\$shogun_agent\" \"focus\" \"\\$left_width\"|zellij_emit_agent_leaf \"                \" \"\\$gunshi_agent\" \"\" \"\\$gunshi_height\"' scripts/goza_no_ma.sh`
   - 期待結果: `shogun` が左 full-height、`gunshi` が右列上段へ配置される実装が存在する。

## 追補（2026-03-11: pure zellij の resize 追従）
### 要求
1. WSL ウィンドウサイズ変更に伴う `zellij` pane のリサイズ時、pane 内で動く `Codex` / `Gemini` / 他 TUI CLI も追従すること。
2. pure `zellij` の nested PTY runner は、child PTY の winsize 更新だけでなく、子プロセスへ `SIGWINCH` を伝播すること。

### 受け入れ条件（観測可能）
1. コマンド: `python3 -m py_compile scripts/interactive_agent_runner.py`
   - 期待結果: resize 伝播ロジック追加後も構文エラーがない。
2. コマンド: `bats tests/unit/test_goza_pure_bootstrap.bats`
   - 期待結果: `SIGWINCH` 伝播を含む pure zellij runner 回帰テストが PASS する。
3. コマンド: `rg -n "copy_winsize\\(|os.killpg\\(proc.pid, signal.SIGWINCH\\)" scripts/interactive_agent_runner.py`
   - 期待結果: child PTY winsize 更新と `SIGWINCH` 伝播の両方が実装されている。

## 追補（2026-03-11: pure zellij の起動時 auto layout profile）
### 要求
1. pure `zellij` の `goza_room` は、起動時の terminal 幅を読み取り `wide / normal / narrow` のレイアウトプロファイルを自動選択できること。
2. `narrow` では `shogun/gunshi` を左列縦積みに戻し、狭い画面での横方向圧迫を避けること。
3. `normal/wide` では `shogun` full-height / `karo` full-height / `gunshi` 右列上段を維持すること。
4. この自動化は「起動時判定」であり、起動後の live 構造変更を前提にしないこと。

### 受け入れ条件（観測可能）
1. コマンド: `bats tests/unit/test_goza_pure_bootstrap.bats`
   - 期待結果: auto profile / narrow profile 分岐を含む pure zellij テストが PASS する。
2. コマンド: `rg -n "PURE_LAYOUT_PROFILE|GOZA_PURE_LAYOUT_PROFILE|print\\(\"wide\"\\)|print\\(\"normal\"\\)|print\\(\"narrow\"\\)" scripts/goza_no_ma.sh`
   - 期待結果: 起動時 terminal 幅の auto 判定ロジックがコード上に存在する。
3. コマンド: `rg -n 'if \\[\\[ \"\\$layout_profile\" == \"narrow\" \\]\\]' scripts/goza_no_ma.sh`
   - 期待結果: narrow profile で別配置へ切り替える実装が存在する。

## 追補（2026-03-09: pure zellij setup-only session 分離）
### 要求
1. `bash scripts/goza_zellij_pure.sh -s` を実行しても、次の `bash scripts/goza_zellij_pure.sh` 通常起動が `setup-only` pane command を再利用しないこと。
2. `pure zellij` の setup-only と通常起動は、既定では別 session 名で扱い、通常起動用 session を汚染しないこと。

### 受け入れ条件（観測可能）
1. コマンド: `bash scripts/goza_zellij_pure.sh -s`
   - 期待結果: setup-only 用 session が通常起動用 session とは別名で作られる。
2. コマンド: `bash scripts/goza_zellij_pure.sh`
   - 期待結果: 通常起動時の pane 内 `zellij_agent_bootstrap.sh` へ `GOZA_SETUP_ONLY=true` が渡らない。
3. コマンド: `bats tests/unit/test_goza_wrapper_modes.bats tests/unit/test_goza_pure_bootstrap.bats`
   - 期待結果: pure wrapper の session 分離回帰テストを含めて PASS する。

## 追補（2026-03-09: pure zellij 自動送信の submit 分離）
### 要求
1. `pure zellij` の pane 内 runner は、bootstrap 本文を入力欄に貼り付けるだけで終わらず、自動で submit まで行うこと。
2. `Codex` / `Gemini` のような TUI CLI では、本文と Enter を同一 write で送らず、分離して送ること。

### 受け入れ条件（観測可能）
1. コマンド: `python3 -m py_compile scripts/interactive_agent_runner.py`
   - 期待結果: pane 内 runner の送信ロジック変更後も構文エラーがない。
2. コマンド: `bats tests/unit/test_interactive_agent_runner.bats tests/unit/test_goza_pure_bootstrap.bats`
   - 期待結果: PTY runner と pure zellij の回帰テストが PASS する。
3. コマンド: `rg -n "send_text|send_enter|deliver_bootstrap" scripts/interactive_agent_runner.py`
   - 期待結果: bootstrap 本文送信と submit が分離実装されている。

## 追補（2026-03-09: 足軽ID混線修正 + Codex既定Auto + Codex ready後初動）
### 要求
1. `pure zellij` では、agent 自己識別を `tmux display-message` 固定にせず、まず `AGENT_ID` 環境変数を正本として使うこと。
2. `ashigaru` / `karo` / `gunshi` / `shogun` の generated instructions と `AGENTS.md` は、`zellij` でも誤った `@agent_id` を読みに行かないこと。
3. `Codex` を使う agent は、未設定時の既定 `reasoning_effort` を `auto` とし、暗黙の `high` や `none` を入れないこと。
4. `pure zellij` の `Codex` 初動命令は、CLI ready 前の引数注入ではなく、pane 内 runner が `update prompt` と `ready pattern` を見てから送信すること。
5. `Gemini` / `Codex` の preflight は、active pane 依存ではなく agent 専用 runner が pane 内で処理すること。

### 受け入れ条件（観測可能）
1. コマンド: `bats tests/unit/test_cli_adapter.bats tests/unit/test_goza_pure_bootstrap.bats tests/unit/test_sync_gemini_settings.bats`
   - 期待結果: `Codex reasoning auto`、`AGENT_ID優先`、`pure zellij runner` の回帰テストが PASS する。
2. コマンド: `bash scripts/build_instructions.sh`
   - 期待結果: `AGENTS.md` と `instructions/generated/*.md` が再生成され、旧 `tmux display-message` 固定の自己識別手順が source から消える。
3. コマンド: `rg -n "interactive_agent_runner.py|AGENT_ID unavailable|Identify self:" scripts/zellij_agent_bootstrap.sh instructions/common/forbidden_actions.md AGENTS.md CLAUDE.md`
   - 期待結果: `interactive_agent_runner.py` と `AGENT_ID` 優先自己識別がコード/文書上に存在する。
4. コマンド: `rg -n "default_codex_reasoning_effort|default_reasoning_for_role" lib/cli_adapter.sh scripts/configure_agents.sh`
   - 期待結果: `Codex` の未設定既定が `auto` 側であることを確認できる。

## 追補（2026-03-07: OpenCode / Kilo CLI 対応）
### 要求
1. `OpenCode` と `Kilo CLI` を、このリポジトリの agent CLI として選択・起動できること。
2. `OpenCode` / `Kilo` は `provider/model` 形式の model 指定を `config/settings.yaml` から受け取り、起動コマンドへ反映できること。
3. pure `zellij` を含む起動導線で、`OpenCode` / `Kilo` の初回命令は active pane への平文注入ではなく `--prompt` 引数で渡すこと。
4. `OpenCode` / `Kilo` の project config である `opencode.json` を、このリポジトリから生成できること。
5. `Kilo CLI` は local model / OpenAI-compatible endpoint の設定を `OpenCode` と同じ `opencode.json` 形式で扱うことを前提にする。
6. `scripts/configure_agents.sh` から `OpenCode/Kilo` の shared provider 設定（`provider` / `base_url` / `api_key_env` / `instructions`）を保存できること。
7. `Ollama` と `LM Studio` は `OpenCode/Kilo` 用 provider として明示選択でき、`base_url` 未指定時でも既定URLへ補完されること。

### 受け入れ条件（観測可能）
1. コマンド: `bats tests/unit/test_cli_adapter.bats`
   - 期待結果: `opencode` / `kilo` の CLI種別判定、起動コマンド、`--prompt` 付き起動、可用性判定、指示書解決が PASS する。
2. コマンド: `bash scripts/build_instructions.sh`
   - 期待結果: `instructions/generated/opencode-*.md` と `instructions/generated/kilo-*.md` が再生成される。
3. コマンド: `python3 scripts/sync_opencode_config.py`
   - 期待結果: `config/settings.yaml` に `cli.opencode_like` がある場合、project root の `opencode.json` が生成される。
4. コマンド: `bats tests/unit/test_sync_opencode_config.bats`
   - 期待結果: `opencode.json` 生成と skip/noop 条件のテストが PASS する。
5. コマンド: `bats tests/unit/test_configure_agents.bats`
   - 期待結果: `configure_agents.sh` が `cli.opencode_like` と `Gemini thinking_level` を崩さず保存できる。
6. コマンド: `bats tests/unit/test_sync_opencode_config.bats`
   - 期待結果: `ollama` と `lmstudio` が `base_url` 未指定でも既定URLに補完される。
7. コマンド: `rg -n "opencode|kilo|opencode_like|ollama|lmstudio" lib/cli_adapter.sh scripts/configure_agents.sh first_setup.sh scripts/sync_opencode_config.py`
   - 期待結果: CLI追加、shared provider 設定UI、local provider 既定値、初回セットアップ案内がコード上に存在する。

## 追補（2026-03-07: gunshi設定 + Codex/Gemini思考モード）
### 要求
1. `scripts/configure_agents.sh` で `gunshi` も `shogun/karo/ashigaruN` と同様に設定できること。
2. `config/settings.yaml` に保存した役職別CLI設定は、再起動後も保持されること。
3. `Codex` は agent ごとに `reasoning_effort` を設定できること。
4. `Gemini` は agent ごとに、`Gemini 3` 系では `thinking_level`、`Gemini 2.5` 系では `thinking_budget` を設定できること。
5. `Gemini` の思考設定は workspace の `.gemini/settings.json` へ自動同期され、起動コマンドは per-agent alias を用いて反映されること。
6. `shogun` は、`Claude` では明示設定が無い場合でも最小思考へ寄せること。`Codex` は未設定時 `auto` とすること。
7. `Gemini` は `thinking_level` / `thinking_budget` を明示設定した場合だけ alias を生成し、未設定時は素の `Gemini 3` モデル表示で起動すること。

### 受け入れ条件（観測可能）
1. コマンド: `bash scripts/configure_agents.sh`
   - 期待結果: `gunshi` を含む全役職の CLI / model / thinking 設定を保存できる。
2. コマンド: `cat config/settings.yaml`
   - 期待結果: `cli.agents.gunshi`、`reasoning_effort`、`thinking_level`、`thinking_budget` の各キーが保存される。
3. コマンド: `python3 scripts/sync_gemini_settings.py && sed -n '1,200p' .gemini/settings.json`
   - 期待結果: `modelConfigs.customAliases.mas-<agent>` が生成される。
4. コマンド: `bats tests/unit/test_cli_adapter.bats tests/unit/test_sync_gemini_settings.bats`
   - 期待結果: `Codex` の `reasoning_effort` と `Gemini` alias 同期テストが PASS する。
5. コマンド: `rg -n "default_codex_reasoning_effort|default_claude_thinking|get_agent_gemini_runtime_model|normalize_level" lib/cli_adapter.sh scripts/sync_gemini_settings.py`
   - 期待結果: `shogun` の `Claude` 既定最小思考、`Codex` 未設定 `auto`、`Gemini` の明示設定時のみ alias を使うロジックがコード上に存在する。

## 追補（2026-03-07: pure zellij の dedicated bootstrap 化）
### 要求
1. `pure zellij` の初動は、外側スクリプトがアクティブペインへ平文注入する方式をやめる。
2. 各 pane は `AGENT_ID` 固定の専用 runner で起動し、agent ごとの bootstrap file を読んで自律起動する。
3. 初回命令の本文は `tmux/zellij write-chars` ではなく、pane 内の CLI 起動引数で渡せるものは引数に畳み込む。
4. 元リポジトリと同様に「本文は file-based、multiplexer は起床または表示だけ」という原則へ寄せる。

### 受け入れ条件（観測可能）
1. コマンド: `bats tests/unit/test_goza_pure_bootstrap.bats`
   - 期待結果: pure zellij が `dedicated runner + bootstrap file` 前提のテストで PASS する。
2. コマンド: `rg -n "prepare_pure_zellij_bootstrap_files|zellij_agent_bootstrap.sh|build_cli_command_with_startup_prompt" scripts/goza_no_ma.sh scripts/zellij_agent_bootstrap.sh lib/cli_adapter.sh`
   - 期待結果: 外側注入ではなく agent-local bootstrap の経路が実装されている。
3. コマンド: `rg -n "bootstrap delivered agent=\\$agent cli=\\$cli_type mode=send-line" scripts/goza_no_ma.sh`
   - 期待結果: pure zellij の bootstrap 本文を外側 send-line する旧ログが残っていない。

## 追補（2026-03-07: 上流完全クローン基準 + Waste退避）
### 要求
1. 上流 `yohey-w/multi-agent-shogun` をワークスペース内へ完全クローンし、それを基準に再実装する。
2. 現在の独自基盤が邪魔なら、新設した `Waste/` 配下へ退避してよい。
3. 今回の主対象は `zellij` 対応と `Gemini CLI` 対応の2点に限定する。
4. 作業はユーザー確認なしで継続する。未確定事項は仮定して進める。

### 受け入れ条件（観測可能）
1. コマンド: `git -C _upstream_reference/original_full_2026-03-07 rev-parse --short HEAD`
   - 期待結果: 上流完全クローンの HEAD が取得できる。
2. コマンド: `find Waste -maxdepth 2 -type f | sort`
   - 期待結果: 退避した旧基盤または退避内容を説明するファイルが存在する。
3. コマンド: `bats tests/unit/test_cli_adapter.bats`
   - 期待結果: 上流ベースへ寄せた `cli_adapter` でも `gemini` 系テストが PASS する。
4. コマンド: `bash scripts/build_instructions.sh`
   - 期待結果: `instructions/generated/gemini-*.md` を含む generated instructions が再生成される。

## 追補（2026-03-07: 上流最新構造への再出発）
### 要求
1. `yohey-w/multi-agent-shogun` の最新内部構造を基準に、このフォークの実装を実質的にやり直してよい。
2. ただし今回の実装対象は `zellij` 対応と `Gemini CLI` 対応に限定する。
3. 上流の整理された共通基盤（`AGENTS.md`、`agent_status`、watcher、instruction build など）は可能な限り採用し、その上に `zellij` と `Gemini` を載せ直す。
4. 既存の独自実装が邪魔な場合は、ワークスペース内に退避用フォルダを作って保管してよい。

### 受け入れ条件（観測可能）
1. コマンド: `test -f _trash/restart_2026-03-07_core/AGENTS.md.before_upstream && test -f lib/agent_status.sh`
   - 期待結果: 旧基盤が退避され、新しい上流基盤ファイルが存在する。
2. コマンド: `bats tests/unit/test_send_wakeup.bats`
   - 期待結果: 上流 `agent_status` を取り込んでも watcher 回帰がない。
3. コマンド: `rg -n "agent_is_busy_check|Created initial idle flag" scripts/inbox_watcher.sh lib/agent_status.sh`
   - 期待結果: watcher が上流の busy 判定基盤を参照している。
4. コマンド: `rg -n "zellij|gemini" docs/EXECPLAN_2026-03-07_upstream_restart_zellij_gemini.md docs/UPSTREAM_SYNC_2026-03-07_RESTART.md`
   - 期待結果: 再出発方針と対象範囲が文書化されている。

## 追補（2026-03-06: 上流最新の反映対象を zellij / Gemini CLI に限定）
### 要求
1. `yohey-w/multi-agent-shogun` の最新状況を確認し、このフォークでは `zellij` 対応と `Gemini CLI` 対応に関係する差分だけを反映する。
2. pure `zellij` の御座の間起動で、各ペインの CLI が自動起動し、初動命令が自動送信されること。
3. `Gemini CLI` の初回 `Trust folder` / 一時的な `high demand` 表示を、zellij 起動導線で自動的に処理または再試行できること。
4. 既存の複雑な実験コードが邪魔であっても、今回は無理に全面整理せず、zellij / Gemini に必要な変更へ絞る。

### 受け入れ条件（観測可能）
1. コマンド: `git rev-parse --short upstream/main`
   - 期待結果: 上流最新コミットを確認でき、対応する同期ノートが `docs/` に記録される。
2. コマンド: `bats tests/unit/test_goza_pure_bootstrap.bats tests/unit/test_zellij_bootstrap_delivery.bats`
   - 期待結果: pure zellij と zellij session-per-agent のブートストラップ関連テストが PASS する。
3. コマンド: `bats tests/unit/test_send_wakeup.bats`
   - 期待結果: watcher 回りの回帰がない。
4. コマンド: `rg -n "gemini trust accepted|gemini keep_trying|Created initial idle flag" scripts/goza_no_ma.sh scripts/shutsujin_zellij.sh scripts/inbox_watcher.sh`
   - 期待結果: Gemini preflight と watcher の false-busy 対策がコード上に存在する。

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

## 追補（2026-02-21: 上流最新同期 + pure zellij 起動安定化）
### 要求
1. 上流 `yohey-w/multi-agent-shogun` の最新設計差分を確認し、本リポジトリへ必要分を反映する。
2. Codex 起動オプションを上流整合に合わせる（`--search` 有効化）。
3. `inbox_watcher` の Codex escalation `/clear` 抑止は command-layer（将軍/軍師/家老系）のみに限定する。
4. pure zellij の `Waiting to run` 状態を自動解除し、初動命令が各ペインへ入る前提を満たす。

### 受け入れ条件（観測可能）
1. コマンド: `bats tests/unit/test_cli_adapter.bats`
   - 期待結果: Codex コマンド期待値が `--search` 付きで PASS する。
2. コマンド: `bats tests/unit/test_send_wakeup.bats`
   - 期待結果: command-layer の escalation `/clear` 抑止テストを含め PASS する。
3. コマンド: `bats tests/unit/test_goza_pure_bootstrap.bats`
   - 期待結果: pure zellij の command pane 自動解除（Enter送信）検証を含め PASS する。
4. コマンド: `bash scripts/goza_no_ma.sh --mux zellij --ui zellij --template goza_room`
   - 期待結果: 各ペインが `Waiting to run` で停止せず、CLI起動後に初動プロンプトが注入される。

## 追補（2026-02-23: attachブロッキングでresume未実行になる不具合）
### 要求
1. pure zellij (`goza_no_ma.sh --mux zellij --ui zellij --template goza_room`) で、attach中でも初動resume処理が確実に動くこと。
2. `zellij --new-session-with-layout` のブロッキングにより、resumeがセッション終了後まで遅延する不具合を解消すること。

### 受け入れ条件（観測可能）
1. コマンド: `bats tests/unit/test_goza_pure_bootstrap.bats`
   - 期待結果: `attachブロッキング前にresume予約を行う` テストがPASSする。
2. コマンド: `bash scripts/goza_no_ma.sh --mux zellij --ui zellij --template goza_room`
   - 期待結果: 起動直後に `queue/runtime/goza_bootstrap_*.log` に `bootstrap delivered` が記録される。

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

## 追補（2026-02-17: Docs/AGENTS確認後の開発再開 - zellij初動注入安定化）
### 要求
1. `AGENTS.md` と `docs/INDEX.md` / Must-read を確認した上で、続きの開発を再開する。
2. zellij 起動時の初動注入で混線しにくいよう、起動フローを安定化する。
3. tmux/zellij 並行運用に影響を出さない最小差分で修正する。

### 受け入れ条件（観測可能）
1. コマンド: `rg -n "初動命令をエージェント単位で順次配信|wait_for_cli_ready \"\\$agent\" \"\\$cli_type\"" scripts/shutsujin_zellij.sh`
   - 期待結果: zellij側で agent 単位の「CLI起動→ready確認→初動配信」が実装されている。
2. コマンド: `rg -n "grep -qiE \"\\$ready_pattern\"" scripts/shutsujin_zellij.sh`
   - 期待結果: ready 判定が CLI種別パターンで実装され、シェルプロンプト依存 (`\\$`) がない。
3. コマンド: `bash -n scripts/shutsujin_zellij.sh`
   - 期待結果: 構文エラーなし。
4. コマンド: `bats tests/unit/test_zellij_bootstrap_delivery.bats tests/unit/test_mux_parity.bats`
   - 期待結果: 全テストPASS。

## 追補（2026-02-17: pure zellij のアクティブペイン注入廃止）
### 要求
1. ログをもとに、注入失敗/誤送信の再発要因を特定して解決策を提示する。
2. pure zellij では「アクティブペインへ外部注入」方式をやめる。
3. 各ペインが自分のTTYに対して初動命令を自律注入する方式に変更する。

### 受け入れ条件（観測可能）
1. コマンド: `rg -n "tty_path=\"\$\(tty\)\"|bootstrap_line=|printf \"%%s\\\\r\" \"\$bootstrap_line\" >\"\$tty_path\"" scripts/goza_no_ma.sh`
   - 期待結果: pure zellij の pane 起動コマンドに、各ペインTTYへの自律注入が実装されている。
2. コマンド: `rg -n 'zellij_bootstrap_pure_goza_background "\\$ZELLIJ_UI_SESSION"' scripts/goza_no_ma.sh`
   - 期待結果: `zellij_pure_attach_goza_room` からフォーカス移動注入呼び出しが消えている。
3. コマンド: `bats tests/unit/test_goza_pure_bootstrap.bats tests/unit/test_mux_parity.bats tests/unit/test_zellij_bootstrap_delivery.bats`
   - 期待結果: 全テストPASS。

## 追補（2026-02-21: エージェント未起動問題のログ分析）
### 要求
1. ログを読んで、起動できていない原因と解決策を提示する。
2. 「アクティブペイン注入」依存を廃止し、起動直後に各エージェントが自動で立ち上がる状態にする。

### 受け入れ条件（観測可能）
1. コマンド: `rg -n "start_suspended=false|command=\"bash\"" scripts/goza_no_ma.sh`
   - 期待結果: zellij layout で command pane が待機状態に入らない設定がある。
2. コマンド: `rg -n "tty_path=\"\$\(tty\)\"|printf \"%%s\\\\r\" \"\$bootstrap_line\" >\"\$tty_path\"" scripts/goza_no_ma.sh`
   - 期待結果: pure zellij は各ペインTTYへの自律注入になっている。
3. コマンド: `bats tests/unit/test_goza_pure_bootstrap.bats tests/unit/test_mux_parity.bats tests/unit/test_zellij_bootstrap_delivery.bats`
   - 期待結果: 全テストPASS。

## 追補（2026-02-21: 起動後に初動プロンプトが入らない問題）
### 要求
1. 起動は成功しているが、各エージェントCLIへ初動プロンプトが入らない不具合を解消する。
2. 注入文面の巨大なコマンド直埋めを避け、注入の可観測性（成功/失敗ログ）を持たせる。

### 受け入れ条件（観測可能）
1. コマンド: `rg -n "goza_bootstrap_.*\.txt|bootstrap delivered" scripts/goza_no_ma.sh`
   - 期待結果: 初動プロンプトをファイル経由で注入し、配信ログを書き出す実装がある。
2. コマンド: `bash -n scripts/goza_no_ma.sh`
   - 期待結果: 構文エラーなし。
3. コマンド: `bats tests/unit/test_goza_pure_bootstrap.bats tests/unit/test_mux_parity.bats tests/unit/test_zellij_bootstrap_delivery.bats`
   - 期待結果: 全テストPASS。

## 追補（2026-02-23: bootstrap injection 根本修正）
### 要求
1. TTY直書き方式（stdout 側書き込み）を廃止し、CLI引数渡し方式でブートストラップを注入する。
2. tmux path では `pane_current_command` に依存せず、`tmux capture-pane` によるスクリーン内容でCLI ready を判定する。
3. 各CLIタイプ（codex/gemini/claude/copilot/kimi/localapi）に対応した ready_pattern を定義する。

### 受け入れ条件（観測可能）
1. コマンド: `rg -nF 'tty_path="$(tty)"' scripts/goza_no_ma.sh`
   - 期待結果: マッチなし（exit 1）。TTY直書き方式が完全に除去されている。
2. コマンド: `rg -nF 'startup_msg' scripts/goza_no_ma.sh`
   - 期待結果: マッチあり。CLI引数渡し方式が使われている。
3. コマンド: `rg -nF 'wait_for_cli_ready_tmux' shutsujin_departure.sh`
   - 期待結果: マッチあり。スクリーン内容ベースのready判定が実装されている。
4. コマンド: `rg -n '^[^#]*pane_current_command' shutsujin_departure.sh`
   - 期待結果: マッチなし（exit 1）。pane_current_command への依存がコードから除去されている。
5. コマンド: `bats tests/unit/test_goza_pure_bootstrap.bats tests/unit/test_zellij_bootstrap_delivery.bats`
   - 期待結果: 全テストPASS。

## 追補（2026-02-23: 引き継ぎ文書の整備）
### 要求
1. 「起動はするがプロンプト注入されない」未解決事象について、次エージェント向けに課題・問題点・次アクションを文書化する。
2. どの起動経路（`goza_no_ma.sh` / `shutsujin_zellij.sh` / `shutsujin_departure.sh`）で再現したかを切り分け可能な資料にする。

### 受け入れ条件（観測可能）
1. コマンド: `sed -n '1,260p' docs/HANDOVER_2026-02-23_prompt_injection_open_issues.md`
   - 期待結果: 症状、再現条件、仮説、優先タスク、検証手順、受け入れ条件が記載されている。
2. コマンド: `rg -n "HANDOVER_2026-02-23_prompt_injection_open_issues.md" docs/INDEX.md`
   - 期待結果: Docs INDEX の Specs に新規引き継ぎ文書が登録されている。

## 追補（2026-03-05: 上流最新クローン + Gemini/Zellij 安定化）
### 要求
1. 上流 `yohey-w/multi-agent-shogun` の最新コードをワークスペース内へ参照クローンし、差分を追跡可能にする。
2. `inbox_watcher` で busy中の `/clear` を延期し、作業中コンテキスト破壊を防ぐ。
3. `shutsujin_zellij.sh` で初動注入の run-id ログと `ready:<agent>` ACK確認を行い、未検出時は1回再送する。

### 受け入れ条件（観測可能）
1. コマンド: `git worktree list --porcelain`
   - 期待結果: `_upstream_reference/upstream_latest_2026-03-05_86ee80b` が含まれる。
2. コマンド: `rg -n "deferred to next cycle|clear_sent" scripts/inbox_watcher.sh`
   - 期待結果: busy延期と `clear_sent` ベース判定の実装が存在する。
3. コマンド: `rg -n "BOOTSTRAP_RUN_LOG|wait_for_ready_ack_zellij|ready ack" scripts/shutsujin_zellij.sh`
   - 期待結果: run-idログ・ACK確認・未検出時再送の実装が存在する。
4. コマンド: `bats tests/unit/test_send_wakeup.bats tests/unit/test_zellij_bootstrap_delivery.bats`
   - 期待結果: 追加テストを含めPASSする。

## 追補（2026-03-06: pure zellij goza_room の ACK監視と配信ログ）
### 要求
1. `goza_no_ma.sh --mux zellij --ui zellij --template goza_room` の pure zellij 経路で、run-id 付き配信ログを保存する。
2. `ready:<agent>` ACKを各ペインで確認し、未検出時は同一ペインへ初動命令を1回再送する。

### 受け入れ条件（観測可能）
1. コマンド: `rg -n "GOZA_BOOTSTRAP_LOG|goza_bootstrap_\$\{GOZA_BOOTSTRAP_RUN_ID\}" scripts/goza_no_ma.sh`
   - 期待結果: `queue/runtime/goza_bootstrap_<run-id>.log` への出力実装が存在する。
2. コマンド: `rg -n "zellij_wait_ready_ack_current_pane|ready ack missing first_try agent=\$agent|bootstrap retry sent agent=\$agent" scripts/goza_no_ma.sh`
   - 期待結果: ACK確認と再送ロジックが存在する。
3. コマンド: `bats tests/unit/test_goza_pure_bootstrap.bats`
   - 期待結果: 追加した pure zellij ログ/ACK テストを含めPASSする。

## 追補（2026-03-07: zellij運用コマンドの安定経路切替）
### 要求
1. ユーザー向け既定コマンド `bash scripts/goza_zellij.sh` は、`zellij UI + tmux backend` の安定経路を使う。
2. pure `zellij` 経路は `bash scripts/goza_zellij_pure.sh` として明示分離し、experimental 扱いにする。
3. `goza_no_ma.sh --mux zellij --ui zellij --template goza_room` も、明示opt-inなしでは stable 側へフォールバックする。
4. `bash first_setup.sh && bash scripts/goza_zellij.sh -s && bash scripts/goza_zellij.sh` の導線で、少なくとも backend 側の CLI 起動と初動注入が pure `zellij` 不具合に巻き込まれないこと。

### 受け入れ条件（観測可能）
1. コマンド: `sed -n '1,20p' scripts/goza_zellij.sh scripts/goza_zellij_pure.sh`
   - 期待結果: `goza_zellij.sh` は `--mux tmux --ui zellij`、`goza_zellij_pure.sh` は `--mux zellij --ui zellij` を呼ぶ。
2. コマンド: `rg -n "MAS_ENABLE_PURE_ZELLIJ|フォールバック" scripts/goza_no_ma.sh`
   - 期待結果: 明示opt-inなしでは stable 側へ切り替える実装が存在する。
3. コマンド: `rg -n "goza_zellij_pure|既定の運用コマンド|experimental" README.md`
   - 期待結果: stable / experimental の責務分離が README に記載されている。
4. コマンド: `bats tests/unit/test_goza_wrapper_modes.bats`
   - 期待結果: PASS。

## 追補（2026-03-07: pure zellij の shell pane 起動化 + Codex updater抑止）
### 要求
1. pure `zellij` は command pane 前提をやめ、通常の shell pane に `launch command` を送って CLI を起動する。
2. pure `zellij` 起動時に `Waiting to run` が前提にならないこと。
3. Codex CLI 起動時の update prompt が bootstrap を塞がないようにする。

### 受け入れ条件（観測可能）
1. コマンド: `rg -n "zellij_agent_boot_cmd|launch command sent agent=\\$agent" scripts/goza_no_ma.sh`
   - 期待結果: pure zellij が shell pane への launch command 送信で起動する実装が存在する。
2. コマンド: `rg -n "NO_UPDATE_NOTIFIER=1 codex|zellij_handle_codex_preflight_current_pane|codex update skipped" lib/cli_adapter.sh scripts/goza_no_ma.sh`
   - 期待結果: Codex updater 抑止と preflight 処理が実装されている。
3. コマンド: `bats tests/unit/test_goza_pure_bootstrap.bats tests/unit/test_goza_wrapper_modes.bats`
   - 期待結果: PASS。

## 追補（2026-03-12: cgo の既存session再利用と nested attach 廃止）
### 要求
1. `cgo` / `bash scripts/goza_no_ma.sh` は、既存の `goza-no-ma` session がある場合、それを壊さず再利用すること。
2. tmux 内から `cgo` した時は nested attach を行わず、`switch-client` で御座の間へ切り替えること。
3. 御座の間の既定レイアウトは `shogun` を最大、`karo` を次点、`gunshi` を三番手、`ashigaru` を残り領域へ compact 配置すること。

### 受け入れ条件（観測可能）
1. コマンド: `bash scripts/goza_no_ma.sh --no-attach` を2回続けて実行する。
   - 期待結果: 2回目は `既存の御座の間 session を再利用します` と表示され、再生成しない。
2. コマンド: `rg -n "switch-client -t|attach_or_switch_session|--refresh" scripts/goza_no_ma.sh`
   - 期待結果: tmux 内では `switch-client` を使い、再生成は `--refresh` 明示時だけであることが確認できる。
3. コマンド: `rg -n "placeholder_cmd|mirror_cmd .*shogun:main|mirror_cmd .*gunshi:main|split-window -h -l|split-window -v -l" scripts/goza_no_ma.sh`
   - 期待結果: 役職優先レイアウトの構成要素が存在する。

## 追補（2026-03-12: 御座の間から backend エージェントへ指示できること）
### 要求
1. `cgo` / `bash scripts/goza_no_ma.sh` で開く御座の間から、backend の実エージェントへ直接指示を送れること。
2. 御座の間は `shogun` 最大、`karo` 二番手、`gunshi` 三番手、`ashigaru` compact で表示すること。
3. tmux 内から `cgo` しても nested attach せず、入力が壊れないこと。

### 受け入れ条件（観測可能）
1. コマンド: `rg -n "goza_dispatcher\.sh|dispatcher_cmd|goza-dispatch" scripts/goza_no_ma.sh scripts/goza_dispatcher.sh`
   - 期待結果: 御座の間に指示用 pane が存在する。
2. コマンド: `rg -n "/target <agent_id>|<agent_id>: <message>|send-keys -t .* -l --" scripts/goza_dispatcher.sh`
   - 期待結果: 使者 pane から実エージェントへ送信する実装が存在する。
3. コマンド: `rg -n "switch-client -t|attach_or_switch_session" scripts/goza_no_ma.sh`
   - 期待結果: tmux 内では nested attach せず `switch-client` を使う。
4. コマンド: `bats tests/unit/test_mux_parity.bats tests/unit/test_mux_parity_smoke.bats`
   - 期待結果: PASS。
