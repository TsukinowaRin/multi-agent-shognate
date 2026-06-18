# Requirements (Normalized)

最終更新: 2026-06-17
出典: ユーザー要求「最新の本家リポジトリをベースに Shogunate 独自機能を実装し直す」

## 追補（2026-06-16: cwd-first project runtime / parallel Shogunate）

### 要求

1. Codex / opencode と同じように、ユーザーが作業したいディレクトリへ `cd` してから `shogunate` を実行できるようにする。
2. package install された Shogunate 本体は engine として `~/.shogunate/shogunate` に残し、実行対象 project と runtime state を分離する。
3. `shogunate`, `shogunate clean`, `shogunate resume`, `shogunate attach`, `shogunate configure`, `shogunate pair` は既定で呼び出し元 cwd を project として扱う。
4. 複数 project で同時に Shogunate を起動しても、tmux session、queue、logs、dashboard、runtime metadata が混ざらないようにする。
5. `shogunate --project /path/to/project ...` または command 後の `--project /path/to/project` で対象 project を明示できる。
6. Android Pair は USB / wireless とも、呼び出し元 project に対応する runtime へ接続できるようにする。
7. 既存の source checkout 開発導線は壊さず、package 導線を cwd-first の正本にする。
8. 非エンジニアでも現在の project / runtime / engine / tmux session を確認できる導線を用意する。
9. Android app は Pair 後に project 固有の tmux target を保存し、並列 Shogunate の別 project へ誤接続しない。
10. スモークだけでなく、可能な範囲で実機 runtime / Android build / 接続系の動作確認を行う。

### 制約

1. `main` / `master` へ直接 push しない。
2. Shogunate 本体更新と project runtime の状態を混ぜない。
3. secrets、SSH 秘密鍵、認証 token の内容は読まない・出力しない。
4. 既存の Android app は `project` response を `dashboard.md` / screenshot upload 用に使うため、Pair response の互換性を維持する。

### 受け入れ条件（観測可能）

1. `cd /path/to/project && shogunate` は `/path/to/project` を target project として表示し、project 固有の runtime copy / tmux session 名を使う。
2. 異なる 2 つの project から起動した場合、session 名が衝突せず、`queue/runtime` も別々になる。
3. `shogunate attach` は同じ project から実行すると、その project の session へ attach する。
4. `shogunate pair` は同じ project の runtime を起動し、Android app には runtime root を `project` として返しつつ、target project 情報も response に含める。
5. `shogunate where` は project、runtime、engine、session を表示する。
6. Android app は Pair response の `shogun` / `agents` を保存し、Pair response の `target_project` を接続結果に表示できる。
7. `bash -n`、関連 Python unit tests、package distribution tests、runtime launcher tests、Android unit/build check が PASS する。

## 追補（2026-06-16: upstream core + Shogunate MOD 構造化）

### 要求

1. この repo を「本家 Shogun core + Shogunate MOD」という構造へ段階的に作り直す。
2. 本家由来 runtime core は可能な限り upstream 追従しやすく保ち、Shogunate 独自機能は `shogunate_mod/` を canonical source とする。
3. 既存の cURL URL、`scripts/*` path、Android app、package install、cwd-first、Gunkan、追加 CLI、update manager 等の現行体験は壊さない。
4. 互換 path は残すが、Shogunate-only 実装は MOD 側へ移し、wrapper で呼び出す。
5. 本家更新時にどこが core touchpoint か追える manifest / docs を用意する。

### 制約

1. 一度に巨大 runtime core を全面置換して機能退行させない。
2. 既存ユーザー向けの `scripts/shogunate_package_bootstrap.sh` と `scripts/shogunate_pair_server.py` は互換入口として残す。
3. Android app と release package / npm package に `shogunate_mod/` が含まれること。

### 受け入れ条件（観測可能）

1. `shogunate_mod/manifest.yaml` が MOD canonical paths と core touchpoints を示す。
2. `scripts/shogunate_package_bootstrap.sh`, `scripts/shogunate_pair_server.py`, `scripts/shell_aliases.sh` は互換 wrapper として MOD 実装へ委譲する。
3. MOD 側正本の package bootstrap / package first setup / npm package CLI / package prepublish check / Pair server / CLI adapter / Antigravity keyring preflight / LocalAPI REPL / interactive agent configurator / runtime role configurator and OS launchers / OpenCode-Kilo project config sync / live CLI switch command / generated instruction build and freshness guard / queue YAML slimming / queue history book generation / Claude Code SessionStart persona injection / Stop hook inbox delivery and idle flag publication / branch policy, deploy verification, branch maintenance, and cron setup / update manager and update shell commands / ntfy auth/send/listener / agent status helper and command / rate-limit status command / agent registry / topology adapter / inbox path normalization / inbox writer policy / inbox watcher / file-watch helpers / watcher supervisor / Gunkan helpers and CoDD check command / runtime helper / runtime shell launchers / runtime launcher shared setup / runtime departure entrypoint / Android compatibility sessions / runtime daemon / watcher-bridge startup orchestration / runtime bridge scripts and daemons / live CLI preference sync and daemon / runtime role directives / runtime topology resolution / Goza tmux session construction / Goza layout and pane helpers / view attach-focus-autosave helpers and dashboard viewer / queue-dashboard-runtime state helpers / startup banner・startup-time ASCII banner・runtime CLI metadata helpers / runtime options/help / agent CLI launch flow / runtime lifecycle setup / runtime MCP health check and mux parity smoke / startup-window helpers / startup lock/update/logging helpers / startup bootstrap delivery helpers and delivery flow / runtime blocked relay and dashboard notice helper / completion summary and Windows Terminal tabs / runtime prompt handling / macOS and Windows runtime launchers / shell aliases and shell rc installer に既存機能が残る。
4. npm package `files` に `shogunate_mod/` の正本ファイルが含まれ、生成物は混ざらない。
5. 既存 unit / package / Android / runtime smoke が PASS する。

## 追補（2026-05-22: upstream latest base rebuild）

### 要求

1. 最新の本家 `yohey-w/multi-agent-shogun` を取得し、その `upstream/main` をベースにした新しい作業ブランチで Shogunate を再構築する。
2. 既存 Shogunate 独自機能は、可能な限り本家構造に合わせて再実装し、単なる過去差分の無差別コピーにしない。
3. 機能を後で本家へ PR しやすいように、独立性の高い単位へ整理する。
4. AGY 対応だけでなく、package distribution、CLI state isolation、runtime launcher、multi-Karo topology、cross-platform watcher など現行 Shogunate の必要機能を維持する。
5. 実機または実 runtime に近い環境で、Shogunate runtime が起動し、少なくとも Codex / OpenCode / Antigravity の代表構成で破綻しないことを確認する。
6. 完了時に、何を本家ベースから変更したか、何を最適化したか、どの機能が本家 PR 候補かを説明する。

### 制約

1. `main` / `master` へ直接 push しない。
2. secrets、認証 token、秘密鍵の内容は読まない・出力しない。
3. 既存の `codex/upstream-v4.6.0-sync` は参照元として保持し、破壊しない。
4. 大きな移植は機能群ごとに検証し、失敗時に戻せる単位で commit する。
5. 本家に既に入っている OpenCode support は尊重し、Shogunate 側の上書きで退行させない。

### 受け入れ条件（観測可能）

1. コマンド: `git log -1 --oneline upstream/main`
   - 期待結果: 作業開始時点の upstream base commit が確認できる。
2. コマンド: `git merge-base --is-ancestor upstream/main HEAD`
   - 期待結果: 新しい Shogunate 作業ブランチが最新 upstream を祖先に持つ。
3. コマンド: `bash -n` 対象 shell scripts。
   - 期待結果: runtime / CLI adapter / launcher / watcher / update scripts に syntax error がない。
4. コマンド: 関連 Bats / Python tests。
   - 期待結果: 移植した機能群の回帰テストが PASS する。
5. 実機確認: test folder または隔離 runtime で `Shogunate-Runtime.sh` を起動。
   - 期待結果: tmux runtime が起動し、代表 agent に初動命令を配信できる。
6. コマンド: `git diff --check`
   - 期待結果: whitespace error がない。

### 今回の初期再構築では外すもの

- CoDD gate は統合しない。runtime / CLI / package が安定した後に必要性を再評価する。
- Android app / APK 対応は統合しない。Android remote control は後段の独立 PR 候補として扱う。

## 追補（2026-05-22: upstream AGY PR / local model smoke）

### 要求

1. 本家 `yohey-w/multi-agent-shogun` に対して、Shogunate 全体ではなく AGY / Antigravity CLI 対応だけを最小単位で PR できるか検証し、可能なら PR を作成する。
2. 本家向け PR は、本家構造を保ったまま `antigravity` / legacy `gemini` alias / `agy --dangerously-skip-permissions` / role instruction generation / basic runtime ready handling を追加する程度に抑える。
3. Shogunate 側では LocalAPI / LM Studio / Ollama の OpenAI-compatible endpoint 接続を確認する。
4. ROCm 環境で可能なら Ollama の `qwen3.6:27b` 等を一時的にロードし、LocalAPI wrapper から実応答を確認する。

### 制約

1. 本家向け PR ブランチは `upstream/main` から分岐し、Shogunate の package distribution / multi-Karo / runtime hardening などを混ぜない。
2. `main` / `master` へ直接 push しない。
3. secrets、token、API key、OAuth token の内容は読まない・出力しない。
4. Ollama / LM Studio / ROCm の導入や大容量モデル download が必要な場合は、既存環境を破壊しない範囲で行い、できない場合は理由を記録する。
5. 27B model は容量が大きいため、インストール済み runtime / server が無い場合は mock OpenAI-compatible server と endpoint availability check を先に行う。

### 受け入れ条件（観測可能）

1. `upstream/main` ベースの AGY-only branch が作成され、差分に AGY 以外の Shogunate 独自機能が混入していない。
2. AGY branch で `bash -n` と関連 Bats が PASS する。
3. AGY CLI が存在する環境では、少なくとも command construction / availability check が PASS する。
4. LocalAPI wrapper は mock OpenAI-compatible endpoint で chat completion を取得できる。
5. Ollama / LM Studio endpoint が起動していない場合は、その事実と必要手順を明記する。
6. 実機 local model test が通る場合のみ、本家 AGY PR を作成する。local model test が環境不足で止まる場合は、AGY PR を draft として作るか保留理由を明記する。

## 追補（2026-05-25: Shutsujin.bat を本家風の手動 view 起動に戻す）

### 要求

1. `Shutsujin.bat` は `shutsujin_departure.sh` を通常起動し、起動直後から自動で Goza View に attach しない。
2. Windows / WSL から `Shutsujin.bat` を開いた後、ユーザーが同じ端末で `cgo` / `CGO` を入力すると Goza View、`csa` / `CSA` を入力すると足軽 View に切り替えられる状態にする。
3. `Shogunate-Runtime.bat` は従来どおり一発起動で Goza View を自動表示する。
4. 本家由来の `csst` / `css` / `csm` 系の使い勝手を壊さない。特に `csm` は本家どおり multiagent view として扱う。
5. Shogunate 独自の御座の間ショートカットとして `cgo` / `csa` / `csg` / `csk` / `ckr` / `cma` を用意する。
6. `Shutsujin.bat` は数字付きの手順表示や成功時 pause を出さず、選択したら即起動する。

### 制約

1. 既存 tmux session を不用意に kill しない。
2. Windows 側 launcher は WSL Ubuntu 前提のまま扱う。
3. `Runtime.bat` の自動 attach 仕様は変更しない。

### 受け入れ条件（観測可能）

1. `Shutsujin.bat` 実行後、端末は WSL shell に残り、`cgo` / `CGO` / `csa` / `CSA` が入力可能。
2. `cgo` / `CGO` は `bash scripts/goza_no_ma.sh` 相当として Goza View に attach / switch する。
3. `csa` / `CSA` は `bash scripts/goza_no_ma.sh -t ashigaru` 相当として足軽 View に attach / switch する。
4. `css` / `CSS` は将軍、`csm` / `CSM` は multiagent、`csk` / `CSK` または `ckr` / `CKR` は家老に attach / switch する。
5. `Shutsujin.bat` に `[1/3]` / `[2/3]` / `[3/3]` の進行表示が残っていない。
6. `cmd.exe /c Shutsujin.bat --no-attach` または shell syntax check 相当で launcher の基本動作が確認できる。

## 追補（2026-05-26: Shutsujin.bat の Codex TUI 表示安定化）

### 要求

1. `Shutsujin.bat` で起動した Codex の入力欄が黒くなる問題を避ける。
2. `Shutsujin.bat` は Goza に attach してから agent CLI を起動する。
3. 数字メニューは復活させない。
4. 旧来の alias shell workflow は `--no-attach` で残す。

### 受け入れ条件（観測可能）

1. `Shutsujin.sh` は `MAS_WAIT_FOR_GOZA_CLIENT_BEFORE_CLI=1` と `MAS_LAUNCHER_RUN_ID` を使い、`shogunate` session 作成後に `tmux attach-session -t shogunate` する。御座の間は `shogunate:goza` view として扱う。
2. `Shutsujin.bat` は `Shogunate-Runtime.sh` ではなく `Shutsujin.sh` を呼び続ける。
3. `Shutsujin.bat` に数字選択メニューが残っていない。
4. `Shutsujin.sh --no-attach` は起動後に `scripts/shell_aliases.sh` を読む manual fallback を維持する。

## 追補（2026-05-26: Windows debug launcher の clean / resume 分離）

### 要求

1. 通常配布は cURL / package command で起動する前提に寄せる。
2. Windows ローカルデバッグ用に clean start と resume を明示した bat を分ける。
3. debug bat は既存の `Shutsujin.bat` を再利用し、通常 launcher の処理を重複させない。

### 受け入れ条件（観測可能）

1. `Shutsujin-Clean.bat` は `Shutsujin.bat --clean` を呼ぶ。
2. `Shutsujin-Resume.bat` は `Shutsujin.bat` をそのまま呼ぶ。
3. どちらも `Shogunate-Runtime.bat` / `Shogunate-Runtime.sh` を経由しない。
4. 起動中の `startup` window は、呼び出し元 launcher が書いている最新ログを表示する。

## 追補（2026-05-26: 初動完了後に Shutsujin command shell へ戻る）

### 要求

1. Codex TUI の表示安定化のため、CLI 起動自体は tmux attach 後に行う。
2. `Shutsujin.bat` は `Runtime.bat` と違い、起動完了後に `cgo` / `CMA` / `csa` などを入力して view を選べる状態にする。
3. 起動直後に agent pane の初動命令処理画面へ移動しない。

### 受け入れ条件（観測可能）

1. 初動命令は、指示適用後に `ready:<agent>` を出す内容にする。
2. `shutsujin_departure.sh` は `ready:<agent>` を待ってから `finish_goza_startup_window` を実行する。
3. ready 待機は `MAS_BOOTSTRAP_READY_TIMEOUT` でタイムアウトし、詰まった場合も起動を継続する。
4. `Shutsujin.bat` 経由では、起動完了後に `overview` ではなく `cgo` / `CMA` / `csa` 等を入力できる command shell へ移動する。
5. `Shogunate-Runtime.bat` 経由では、従来どおり起動完了後に Goza overview へ移動する。

## 追補（2026-05-26: 実LLMデモ検証と再完了通知）

### 要求

1. `Shogunate-test` の構成を使い、隔離フォルダで Codex / OpenCode / Antigravity の実CLIを起動して、デモプロジェクトが完成するところまで検証する。
2. 検証用に `SHOGUNATE_SESSION_NAME` / `GOZA_SESSION_NAME` を変更しても、watcher / bridge / runtime-pref が同じ session を正しく参照する。
3. 家老が完了後に人間または将軍から差戻しを受け、同じ `cmd_id` / `timestamp` を再度 close した場合でも、将軍へ修正版の `cmd_done` を再通知する。
4. CoDD は Shogunate runtime に統合せず、必要になった場合のみ外部 gate / plugin として分離運用する。

### 受け入れ条件（観測可能）

1. 隔離 runtime で `shogun=codex`, `karo=codex`, `gunshi=codex`, `ashigaru1=opencode`, `ashigaru2=opencode`, `ashigaru3=codex`, `ashigaru4=antigravity` が起動する。
2. `watcher_supervisor` が現行 session の pane に inbox nudge を送る。旧 `goza-no-ma` の pane ID へ送らない。
3. demo `Task Lantern` は `index.html`, `styles.css`, `app.js`, `README.md` を生成し、`node --check demo-llm-validation/app.js` と静的整合チェックが通る。
4. 家老は CSS/JS 統合ズレなどの差戻しを受けた場合に active queue へ戻し、修正 task を再割当できる。
5. `scripts/karo_done_to_shogun_bridge.py` は `completed_at` または command/dashboard の完了指紋を完了 identity に含め、同じ command の再完了を将軍へ再通知できる。
6. `git diff --check` と関連 Bats / shell syntax check が PASS する。

## 追補（2026-05-28: Shogunate 独自役職「軍監」追加）

### 要求

1. Shogunate 独自要素として `gunkan`（軍監）ロールを追加する。
2. 軍監は将軍直属の独立監査ラインで、家老の配下ではない。ただし実務上は家老と並列に置き、通常の作業指揮は家老に残す。
3. 軍師は家老配下の参謀・高度QC役とし、軍監とは分離する。
4. 軍監は作業ログ、queue、reports、dashboard、runtime 状態を横断監査し、`queue/reports/gunkan_report.yaml` と必要な inbox 通知で将軍/家老へ報告する。
5. 軍監は通常の中間報告取得を担当しない。中間報告は従来どおり `将軍 -> 家老` で取り寄せる。
6. 軍監LLMは常時ポーリングでトークンを消費しない。通常メッセージは非LLMの軽量イベントログへ記録し、軍監LLMは `audit_requested` / `audit_failed` / `runtime_blocked` / `emergency_stop_requested` などの監査イベントでのみ起動する event-driven 監査役とする。
7. ただし、不正・破壊操作・報告矛盾のリアルタイム検知のため、非LLMの軽量軍監 watcher を常駐させる。軽量 watcher は queue / reports / dashboard / git diff / CoDD 設定を低コストに検査し、異常時だけ軍監 inbox へ `audit_requested` を送る。
8. 軍監は CoDD をオンデマンド監査ツールとして使う。`codd` CLI がない環境では組み込み整合性チェックへフォールバックし、runtime 常駐や周期実行はしない。
8. CLI 種別は既存の簡単設定 CUI/CLI で選択でき、デフォルトは他ロール同様 `codex` とする。
9. Codex / Claude / OpenCode / Antigravity / Kilo / Kimi / Copilot / LocalAPI の生成済み instruction と OpenCode agent 定義に軍監を追加する。
10. 御座の間、focus shortcut、watcher、bootstrap、runtime `agent_cli.tsv` で軍監を一級 role として扱う。

### 制約

1. CoDD は軍監の監査時だけ呼ぶ。常駐 daemon、周期 scan、通常タスク完了ごとの自動LLM監査は入れない。
2. 軍監は足軽へ通常タスクを直接割り振らない。
3. 軍監は将軍の最終判断を代替しない。
4. 既存の本家互換 aliases と `Shutsujin.bat` / `Shogunate-Runtime` の動作を壊さない。

### 受け入れ条件（観測可能）

1. `instructions/roles/gunkan_role.md` と `instructions/gunkan.md` が存在する。
2. `scripts/build_instructions.sh` が全CLI向け `*-gunkan.md` と `.opencode/agents/gunkan.md` を生成する。
3. `scripts/configure_runtime_roles.py --gunkan <cli>` で `config/settings.yaml` の `cli.agents.gunkan.type` を更新できる。
4. `shutsujin_departure.sh -s` 相当の setup path で `queue/inbox/gunkan.yaml`, `queue/tasks/gunkan.yaml`, `queue/reports/gunkan_report.yaml` を初期化し、軍監 pane を `@agent_id=gunkan` として作る。
5. `scripts/focus_agent_pane.sh gunkan` または alias `cgn` / `CGN` で軍監 pane にフォーカスできる。
5a. 軍監 LLM pane はユーザーまたは将軍からの直接指示を常に受け付け、監査・検証・停止判断・功績整理・リスク確認であれば inbox event を待たず即応する。
6. watcher supervisor が軍監 inbox watcher を起動対象に含める。
7. `scripts/inbox_write.sh` が通常メッセージを `queue/runtime/gunkan_events.yaml` へ非ブロッキング記録する。
8. `scripts/gunkan_light_watch.py` が `queue/runtime/gunkan_watch.yaml` に軽量監視結果を書き、重大/警告 finding を cooldown 付きで `queue/inbox/gunkan.yaml` へ `audit_requested` として通知できる。
9. runtime daemon session に `gunkan-watch` window が作られ、軍監LLMを常時動かさずに非LLM監視を継続できる。
10. `scripts/gunkan_codd_audit.py` が `codd` CLI 利用可能時は `codd scan` / `codd impact` / `codd validate` を実行し、未導入時は repo-local `.shogunate/codd-venv/` へ `codd-dev` を bootstrap し、導入失敗時はフォールバック監査結果を書ける。
11. `scripts/gunkan_codd_audit.py` は `PATH` と repo-local `.shogunate/codd-venv/` の `codd` を検出でき、`codd_bootstrap` に導入試行の結果を記録できる。
12. `.codd/codd.yaml` と CoDD 用 frontmatter docs が存在し、CoDD scan が軍監/監視/監査の関係 graph を作れる。
13. 軍監 audit nudge は同一未読イベントで連続投入されず、監査後は発火元 inbox message を `read: true` にする。
14. 軍監 lightweight watcher は同一 signature かつ同一 evidence の finding を cooldown 後も再通知しない。finding の evidence が変化した場合のみ再通知する。
15. 将軍 instruction は legacy `multiagent` tmux session / hard-coded pane に依存せず、`queue/` と `dashboard.md` を軽量確認して家老へ委譲する。
16. 関連 Bats / shell syntax / Python compile / `git diff --check` が PASS する。

### 追補要求（2026-05-30: 軽量軍監 watcher 精度改善）

1. 軽量 watcher は LLM を呼ばず、queue / reports / tasks / dashboard / git の構造化情報だけで検出できる失敗を広げる。
2. 親 command が `done` なのに、同じ `parent_cmd` の report が `failed` / `blocked` / `error` の場合は監査対象として検出する。
3. 親 command が `done` なのに、同じ `parent_cmd` の task が未完了状態で残っている場合は監査対象として検出する。
4. 完了 report が成果物 path / artifact / output を明示している場合、その相対 path が存在しなければ検出する。
5. report の `worker_id` と `queue/reports/<agent>_report.yaml` の agent 名が食い違う場合は検出する。
6. dashboard が command 完了を示す一方、同じ command の report が失敗している場合は検出する。
7. untracked file の中身に秘密情報や破壊的操作パターンがある場合も検出する。
8. 誤検知を避けるため、成果物 path の存在確認は明示的な path/artifact/output 系キーに限定し、URL や自然文は path として扱わない。

## 追補（2026-05-28: upstream/main v5.1.0 反映）

### 要求

1. 最新の本家 `upstream/main` を取得し、Shogunate 作業ブランチへ反映する。
2. 本家 `v5.1.0` の traffic-control roles などの変更を取り込む。
3. Shogunate 独自機能（tmux runtime、Windows/WSL launcher、AGY/OpenCode/LocalAPI/Kilo/Kimi/Copilot対応、軍監、CoDDオンデマンド監査、設定CUI、Test folder 同期前提）は削除しない。
4. 本家側で消えているファイルでも、Shogunate の実運用に必要なファイルは保持する。
5. 取り込み後、関連する生成 instruction を再生成し、最小限の unit / syntax / build check を通す。

### 受け入れ条件（観測可能）

1. `git merge-base HEAD upstream/main` が更新され、履歴上 `upstream/main` の最新コミットが取り込まれている。
2. `README.md` / `README_ja.md` / `CHANGELOG.md` など本家ドキュメント更新のうち Shogunate と矛盾しないものが反映されている。
3. `instructions/roles/*`, `instructions/common/*`, `instructions/cli_specific/*` は本家変更と Shogunate 独自 role/CLI を両立している。
4. `shutsujin_departure.sh`, `scripts/goza_no_ma.sh`, `scripts/watcher_supervisor.sh`, `scripts/configure_runtime_roles.py`, `scripts/gunkan_*` など Shogunate runtime の入口が残っている。
5. `bash scripts/build_instructions.sh` が成功する。
6. 変更範囲に対して `bash -n`, `python3 -m py_compile`, 関連 Bats, `git diff --check` を実行し、結果を記録する。

## 追補（2026-05-30: Android app 接続セットアップ改善）

### 要求

1. Android app は現行 Shogunate runtime の tmux target に合わせやすくする。
2. 設定画面は SSH 接続に必要な値、Shogunate 推奨値、接続確認の結果をユーザーが迷わず確認できるようにする。
3. 旧 `session:window` を前提にした入力だけでなく、`shogunate:goza` のような tmux target を直接指定できる。
4. 接続テストは SSH、`tmux`、project path、将軍 target、エージェント target、`dashboard.md` の状態を確認し、結果をアプリ内に表示する。

### 受け入れ条件

1. 設定画面から Shogunate 標準 target を一発入力できる。
2. 設定画面で保存後すぐに接続診断を実行できる。
3. 既存の `shogun` / `multiagent` のような session 名だけの入力は、従来互換 target に解決される。
4. `./gradlew testDebugUnitTest` または同等の Android unit/build check が PASS する。

## 追補（2026-05-31: Android app USB/無線セットアップと将軍単体表示）

### 要求

1. Android app はホストPCへ USB または無線で SSH 接続しやすい導線を持つ。
2. USB 接続は `adb reverse` を使い、Android から `127.0.0.1:2222` へ接続すればホストの SSH に届く構成を標準にする。
3. 無線接続は Tailscale / LAN IP を使う前提で、アプリ上のプリセットとホスト側セットアップ手順を用意する。
4. Android app の将軍タブは、既定では御座の間全体ではなく将軍 pane のみを表示する。
5. Android 互換 session が無効でも、`@agent_id=shogun` から実 pane を解決できる。
6. USB セットアップ時は、可能なら `shogunate://setup` intent で Android app に設定を自動投入する。

### 受け入れ条件

1. 設定画面に USB / 無線の接続プリセットがある。
2. ホスト側に `android/tools/setup_android_ssh.sh` と Windows/WSL 用 `android/tools/setup_android_ssh.bat` がある。
3. 標準の将軍 target は `agent:shogun` で、`tmux list-panes -a` から `@agent_id=shogun` を解決する。
4. 既存の明示 target (`shogunate:goza`, `shogun:main`) と旧 session 名入力は維持される。
5. Android app は `shogunate://setup?...` を受け取り、SSH host/port/user/project/tmux target を保存できる。

## 追補（2026-06-05: Android app setup URI 取り込み改善）

### 要求

1. 無線 / Tailscale 接続でも、ユーザーが IP / port / project path / tmux target を個別に写さなくて済むようにする。
2. ホスト側セットアップスクリプトは、候補 IP ごとの完成済み `shogunate://setup?...` URI を表示する。
3. `qrencode` が利用可能な環境では、スマホで読み取りやすいように setup URI のターミナル QR を表示する。
4. Android app 設定画面は setup URI を貼り付けて接続設定を取り込める。

### 受け入れ条件

1. `bash android/tools/setup_android_ssh.sh --wireless` が host SSH port を自動検出し、候補 host ごとの setup URI を表示する。
2. `qrencode` が無い環境でも script は失敗せず、URI のテキスト表示にフォールバックする。
3. Android app の設定画面で `shogunate://setup?...` を貼り付けると SSH host/port/user/project/tmux target が入力欄に反映される。
4. 不正な URI は既存設定を上書きせず、ユーザーに失敗を知らせる。

## 追補（2026-06-05: Android app USB SSH鍵ペアリング）

### 要求

1. USB デバッグでユーザーが許可した Android 端末に対して、SSH host/port/user/key path を手入力せず接続できる導線を用意する。
2. ホスト側スクリプトはユーザー同意後に Shogunate Android 専用 SSH 鍵を生成または再利用し、公開鍵をホストの `authorized_keys` へ追加する。
3. 秘密鍵は Android app の専用領域へ転送し、内容は標準出力や docs に出さない。
4. スクリプトは USB `adb reverse` と `shogunate://setup` intent を設定し、Android app が鍵認証で接続できる状態にする。
5. 将来的な release APK では、debug `run-as` 依存ではなく app 内 key generation / 一時ペアリング endpoint / QR などへ移行できる設計余地を残す。

### 受け入れ条件

1. `bash android/tools/setup_android_ssh.sh --pair-usb` が同意 prompt を出し、`--yes` 指定時は非対話で実行できる。
2. USB デバッグ許可済み端末が1台の場合、専用鍵を `.shogunate/android-ssh/` に生成または再利用する。
3. 公開鍵は `~/.ssh/authorized_keys` に重複なく追加される。
4. Android app prefs に `ssh_host=127.0.0.1`, `ssh_port=2222`, `ssh_key_path=<app files>/ssh_keys/<key>` が保存される。
5. host 側で同じ鍵による SSH publickey 認証が確認できる。

## 追補（2026-06-05: Android app ワンタッチ接続とマニュアルモード）

### 要求

1. Android app の接続設定は、USB / Tailscale / LAN / setup URI を問わず、通常導線では詳細項目入力を不要にする。
2. 旧来のホスト、ポート、ユーザー、鍵、パスワード、tmux target の個別入力は `マニュアルモード` として残す。
3. USB デバッグが使える初回セットアップでは、Android app が app 内で SSH 鍵を生成または再利用し、ホスト側スクリプトは公開鍵だけを取得して `authorized_keys` に登録する。
4. 秘密鍵は Android app の private storage に残し、PCへ取り出さない。古い debug APK で app 内鍵 provider が使えない場合だけ、既存の `run-as` fallback を使う。
5. `--pair-usb` は USB reverse まで設定して、Android app を `127.0.0.1:2222` に自動設定する。
6. `--pair-wireless` は USB デバッグを初回設定の搬送路として使い、以後は Tailscale / LAN の直接 SSH へ自動設定する。
7. 無線接続先は自動検出候補から選ぶ。USB 接続中の Android 端末の現在の IPv4 に近い候補を優先し、必要なら `SHOGUNATE_PAIR_HOST=<ip-or-host>` で明示できる。

### 受け入れ条件（観測可能）

1. `content://com.shogun.android.pairing/profile` が `public_key`, `key_path`, `device_label` を返す。`public_key` は公開鍵で、秘密鍵本文は返さない。
2. `bash android/tools/setup_android_ssh.sh --pair-usb --yes` が app 内生成鍵の公開鍵を `authorized_keys` に追加し、USB reverse と鍵認証つき setup intent を送る。
3. `bash android/tools/setup_android_ssh.sh --pair-wireless --yes` が同じ app 内生成鍵を使い、Tailscale / LAN 候補の接続設定を app に送る。
4. Android app の設定画面では `ワンタッチ接続` が通常表示され、SSH詳細入力は `マニュアルモード` を開いた時だけ表示される。
5. `cd android && ./gradlew testDebugUnitTest assembleDebug`、`bash -n android/tools/setup_android_ssh.sh`、`git diff --check` が PASS する。

## 追補（2026-06-05: Android app 接続先入力の追加）

### 要求

1. Android app の通常導線に `接続先` 入力欄を追加する。
2. 接続先は DNS 名、SSH/HTTPS 等のURL、Tailscale IP、LAN IP を受け付ける。
3. URLが入力された場合、SSH接続に使う host と port だけを取り出し、path / query / fragment は無視する。
4. URLまたは `host:port` に port が含まれる場合は、その port をSSHポートとして反映する。port が無い場合は現在のSSHポート設定を維持する。
5. ホスト側スクリプトの `--pair-wireless` でも `--host <dns-url-or-ip>` / `SHOGUNATE_PAIR_HOST=<dns-url-or-ip>` を受け付け、同じ正規化を行う。

### 受け入れ条件（観測可能）

1. `normalizeConnectionEndpoint()` は DNS 名、`host:port`、HTTPS URL、SSH URL、Tailscale/LAN IP を正規化できる。
2. Android app 設定画面の `接続先` 欄から、手入力した接続先をSSH host/portへ反映できる。
3. `shogunate://setup?host=<URL>&port=<fallback>` を取り込むと、URL内 host/port が優先される。
4. `bash android/tools/setup_android_ssh.sh --pair-wireless --host 'https://192.168.1.5:2223/path' --yes` が Android app へ `192.168.1.5:2223` を送る。
5. 実機で URL setup URI 取り込み後、Android app が `接続中 — 将軍セッション` になる。

## 追補（2026-06-05: Android app 実機総合QAとUI整理）

### 要求

1. USB接続済みの実機 Android 端末を使い、主要タブとセットアップ導線を実際に操作する。
2. スクリーンショットと UI dump を確認し、表示崩れ、分かりにくい文言、接続設定の迷いやすさを洗い出す。
3. 将軍、エージェント、戦況、設定、BGM/音声/送信ボタン、接続設定リンク取込、接続先入力、マニュアルモード、通知設定を可能な範囲で確認する。
4. 実機で見つかったUI/UX上の問題は、過剰な再設計ではなく小さく修正する。
5. 修正後に実機で再確認し、Android unit/build と shell syntax check を通す。

### 受け入れ条件（観測可能）

1. `adb install -r android/app/build/outputs/apk/debug/app-debug.apk` が成功する。
2. Shogunate runtime が未起動でも、将軍タブとエージェントタブが空白ではなく target 未検出の状態を表示する。
3. 接続設定画面は通常導線でSSH詳細を隠し、必要時だけマニュアルモードで編集できる。
4. 戦況タブの表はスマホ幅で主要列が読める。
5. 使用量チェックはスクリプト未配置または取得失敗時に、待機表示のまま固まらず結果または失敗理由を表示する。
6. 実機スクリーンショットまたは UI dump で、4タブの主要要素が確認できる。
7. 設定画面のワンタッチ接続、接続先入力、マニュアルモード、通知設定が破綻なく表示される。
8. `bash -n android/tools/setup_android_ssh.sh`、`git diff --check`、`cd android && ./gradlew testDebugUnitTest assembleDebug` が PASS する。

## 追補（2026-06-09: Android app ワンタッチ接続UIの簡略化）

### 要求

1. 通常のワンタッチ接続画面は `接続先`、`USB`、`無線`、`接続` に絞る。
2. `標準に戻す`、`接続診断`、`接続先を反映`、`接続設定リンク`、`貼付`、`設定取込` は通常画面から削除する。
3. `接続先` は入力中に常時検証し、DNS / URL / Tailscale IP / LAN IP を SSH 用 host/port へ正規化して表示する。
4. `接続` を押すと現在の接続先を保存し、SSH 接続を試行する。設定が変わるまで同じ host/port で再接続を試みる。
5. USB で SSH セットアップした場合でも、`接続先` に Tailscale / LAN / DNS など到達可能なアドレスが入っていれば、そのアドレスで接続できる。
6. USB へ切り替えても、前回使った無線 host/port を保持し、`無線` を押すとその値を復元する。
7. 将軍CLIが `Working` 中はスマホから新規プロンプトを送れないようにし、将軍側に未送信 composer テキストが残っている時は送信時にキャンセルしてからスマホ側の入力を送る。
8. スマホ側の入力中テキストは、タブ移動や表示切替で失われないように保持する。
9. 入力欄の同じ行に、入力欄展開と送信ボタンを置く。`C-c` は特殊キーバー側に集約し、初期表示で重複させない。

### 受け入れ条件（観測可能）

1. 実機設定画面の通常表示で `USB`、`無線`、`接続` が表示される。
2. 実機設定画面の通常表示で `接続診断`、`接続先を反映`、`接続設定リンク` が表示されない。
3. `接続先` に `100.71.16.5` と保存済み port `2223` がある場合、補助表示が `接続先: 100.71.16.5:2223` になる。
4. `接続` 押下後、SSH 接続結果がアプリ内に表示される。
5. `USB` 押下後に `無線` を押すと、直前または保存済みの無線接続先が再表示される。
6. 実機で将軍CLIが `Working` 中のとき、ステータスが `処理中 — 将軍セッション` になり、送信欄は `将軍が処理中です` を表示する。
7. 実機で将軍側に未送信 composer テキストが残っているとき、ステータスが `入力待ち — 将軍側の下書きあり` になり、送信欄は1行の高さを維持する。
8. 実機で将軍タブに文章を入力後、別タブへ移動して戻っても入力中テキストが残る。
9. 実機で入力欄の同じ行に展開ボタンと送信ボタンが表示され、特殊キーバーは Enter / C-c / 矢印などを raw key として送れる。
10. BGM ボタンは小さい曲名だけに依存せず、`BGM` または現在の曲名を読めるサイズで表示する。

## 追補（2026-06-10: 本家最新反映と Shogunate-test 再起動）

### 要求

1. 開発用リポジトリでは Shogunate runtime を動かし続けず、作業は停止した状態で行う。
2. 本家 `upstream/main` の最新コードを取得し、Shogunate 独自機能を消さずに適用する。
3. テスト実行は `Shogunate-test` に最新内容を反映してから行う。
4. 既存のテスト runtime を停止し、テストフォルダで clean start する。
5. 適用前の未コミット差分は復旧できる形で保全する。

### 受け入れ条件（観測可能）

1. `shogunate` / `goza-runtime` など開発側 runtime session が停止している。
2. `git fetch upstream --prune` 後の `upstream/main` との差分を確認している。
3. 本家 v5.2.0 系の CLI / watcher / startup hardening 修正が、Shogunate の軍監・Android・launcher 拡張と共存している。
4. `Shogunate-test` は開発リポジトリの最新内容で同期され、`.git` や認証情報はコピーされない。
5. `Shogunate-test` で clean start し、少なくとも tmux session と主要 pane の起動状態を確認する。

## 追補（2026-06-10: Android APK release とローカル package install）

### 要求

1. 本家 `v5.2.0` 反映後の Android app を release asset として配布する。
2. Android APK version は Shogunate 本体版に従い、`5.2.0.2` へ更新する。
3. Shogunate package も同じ release tag へ固定 asset として配置し、cURL installer でこのPCへ導入できることを確認する。
4. Android app は GitHub Release の APK asset として配布し、runtime package archive には Android app を含めない。

### 受け入れ条件（観測可能）

1. `android/app/build.gradle.kts` の `versionName` が `5.2.0.2`、`versionCode` が `52002`。
2. Android debug APK build が成功し、release asset としてアップロードされている。
3. `multi-agent-shognate-package.tar.gz` / `.zip` が同じ release tag にアップロードされている。
4. `scripts/shogunate_package_bootstrap.sh --version <tag> --prefix ~/.shogunate/shogunate --no-setup` 相当の導入がこのPCで成功する。
5. package release workflow は prepublish check 前に `upstream/main` を fetch し、CI 用の upstream ancestry / upstream-modified root surface contract を release channel でも実行する。
6. package release workflow は GitHub Release へ upload/publish する前に、作成済み `dist/multi-agent-shognate-package.tar.gz` を使って cURL install smoke を実行する。
7. package release workflow の tar.gz / zip は、package distribution test と同じ `git archive --worktree-attributes` 境界で作成する。
8. package distribution contract は release tar archive と zip archive の実ファイル一覧が一致することを検査する。
9. package release workflow のバージョン付き package asset は、通常名 package asset から `cp` で作成し、同一内容として公開する。
10. GitHub Release notes には固定 release 用 cURL と latest channel 用 cURL を明示し、固定 release 用 cURL は tag と `--version` の両方に同じ `${TAG}` を使う。

## 追補（2026-06-11: README package install 導線）

### 要求

1. README の導入手順を Shogunate package distribution 中心に整理する。
2. 導入用 cURL を、実際に再現できるタグ固定コマンドとして明示する。
3. 導入後に使う `shogunate` コマンド、既定 install path、PATH 注意点を README から分かるようにする。

### 受け入れ条件（観測可能）

1. `README.md` / `README_ja.md` の冒頭 Quick Start で cURL install が最初に提示される。
2. `v5.2.0.3` 固定の install command と、将来 main 反映後の moving command の違いが分かる。
3. `shogunate`, `shogunate resume`, `shogunate configure`, `shogunate status`, `shogunate aliases` が導入後コマンドとして記載される。
4. CI の MOD verification job は `make mod-check` の前提として `curl` を明示導入し、cURL install smoke が runner の既定状態に依存しない。

## 追補（2026-06-12: package clean 警告と軍監口調維持）

### 要求

1. cURL/package install 後の `shogunate clean` で、`scripts/ensure_generated_instructions.sh` が存在するのに実行ビット不足だけで「指示書再生成スクリプトが見つからない」と警告しない。
2. package 展開後の生成指示書再構築は、script file が存在すれば `bash` 経由で実行できる。
3. 軍監（`gunkan`）pane は直接会話でも通常の Codex / 汎用アシスタント口調に戻らず、軍監 persona と戦国口調を維持する。
4. YAML、shell command、file path、正確な技術名は口調より正確性を優先する。

### 受け入れ条件（観測可能）

1. package 内で `scripts/ensure_generated_instructions.sh` / `scripts/build_instructions.sh` が `0644` でも、`shogunate clean` の生成指示書確認が file existence 判定で進む。
2. `bash scripts/ensure_generated_instructions.sh` が generated instruction を再生成または up-to-date 判定できる。
3. `queue/runtime/bootstrap_gunkan.md` に、軍監として振る舞うための明示的な口調規則が含まれる。
4. `instructions/generated/*-gunkan.md` と `.opencode/agents/gunkan.md` に、直接応答時も軍監 persona を維持する規則が含まれる。
5. `bash -n shutsujin_departure.sh scripts/ensure_generated_instructions.sh scripts/build_instructions.sh` と `git diff --check` が PASS する。

## 追補（2026-06-13: README 全面再整理）

### 要求

1. `README.md` / `README_ja.md` を package install 前提の導入文書として全面的に書き直す。
2. 冒頭 Quick Start に、現在の通常 release tag `v5.2.0.3` 固定の cURL install command を明示する。
3. 導入後に使う `shogunate` command、alias、role/CLI 設定、軍監、Android companion、開発 checkout、troubleshooting、release versioning を短く辿れる構成にする。
4. `-preview` 前提の記述や重複した古い導入導線を README から外す。

### 受け入れ条件（観測可能）

1. `README.md` / `README_ja.md` の冒頭に `v5.2.0.3` 固定 cURL がある。
2. README 内の導入例は `~/.shogunate/shogunate`、`~/.local/bin/shogunate`、`shogunate clean/resume/configure/status/aliases` を説明する。
3. README 内に `v5.2.0.1-preview` や古い preview install 導線が残っていない。
4. README の cURL URL が `scripts/shogunate_package_bootstrap.sh` の実在 path を指している。
5. `git diff --check` が PASS する。

## 追補（2026-06-15: Android 初回 Shogunate Pair）

### 要求

1. 初回セットアップ時は PC 側で `shogunate pair` を起動し、短時間の pairing 待受を行う。
2. Android app は USB/Tailscale/LAN の接続先を入力して **接続** を押した時、既存 SSH 鍵や password で接続できない場合、同じ host の pairing server へ app 内生成 SSH 公開鍵を送る。
3. PC 側 pairing server は端末名、接続元、接続先、公開鍵 fingerprint を表示し、ユーザーが端末名を確認して Pair Password prompt に入力した場合だけ `~/.ssh/authorized_keys` へ公開鍵を追加する。
4. pairing 成功後、Android app は返却された `host/port/user/project/shogun target/agents target/key path` を保存し、SSH 再接続を試みる。
5. 以後は保存済み app 内秘密鍵と PC 側 `authorized_keys` により、`shogunate pair` を再実行せず直接 Shogunate に接続できる。
6. pairing server は秘密鍵や SSH password を扱わず、公開鍵登録だけを行う。Pair Password は PC terminal 上のローカル承認入力としてのみ使い、既存 authorized key の削除や上書きはしない。
7. `shogunate pair` は USB と Tailscale/LAN の両方で待ち受ける。USB が接続済みなら adb reverse で Android `127.0.0.1:8765` を pairing server、`127.0.0.1:2222` を PC 側 SSH へ転送する。USB が無い場合も Tailscale/LAN の待受は継続する。
8. `shogunate pair --usb` は廃止し、導入済み package では `shogunate pair` だけを初回セットアップ入口にする。source checkout helper の `--pair-usb` は互換 alias として統合 Pair を起動する。
9. pairing 成功後、PC 側は best-effort で `Shogunate-Runtime.sh --resume --no-attach` を起動し、Android app はその後の SSH 接続確認へ進む。

### 受け入れ条件（観測可能）

1. `shogunate pair` または `python3 scripts/shogunate_pair_server.py` で pairing server が起動し、`/health` と `/pair` を提供する。
2. Android app の設定画面で USB/Tailscale/LAN 接続先を入れて **接続** を押し、SSH が未設定で失敗した場合、pairing server への自動 pairing を試みる。
3. PC 側で表示端末名を確認し、Pair Password prompt に入力した時だけ、公開鍵が `~/.ssh/authorized_keys` に重複なく追加される。
4. pairing response を受けた Android app は SSH key path と接続設定を SharedPreferences に保存し、同じ操作内で SSH 接続確認を再試行する。
5. `shogunate pair` は USB reverse を自動試行しつつ Tailscale/LAN でも待ち受ける。USB request には Android 側 SSH port `2222`、無線 request には PC 側 SSH port を返す。
6. `android/tools/setup_android_ssh.sh --pair-usb` は互換 alias として統合 Pair を起動し、Android app の USB 接続先 `127.0.0.1` から同じ pairing flow を使える。
7. `bash -n scripts/shogunate_package_bootstrap.sh android/tools/setup_android_ssh.sh`、pairing server unit/smoke、Android unit/build、`git diff --check` が PASS する。

## 追補（2026-06-15: Shogunate Pair Android app release）

### 要求

1. `shogunate pair` を USB/無線統合入口にした Android app を release asset として配布する。
2. Android APK version は `5.2.0.3`、`versionCode` は `52003` にする。
3. README の固定 cURL / APK 名は `v5.2.0.3` に更新する。
4. package command の `shogunate help` に `pair` と Pair Password の案内を表示する。

### 受け入れ条件（観測可能）

1. `android/app/build.gradle.kts` の `versionName` が `5.2.0.3`、`versionCode` が `52003`。
2. `shogunate-android-v5.2.0.3.apk` が GitHub Release asset としてアップロードされる。
3. `multi-agent-shognate-package.tar.gz` / `.zip` も同じ release tag にアップロードされる。
4. `shogunate help` に `shogunate pair [opts]` と `SHOGUNATE_PAIR_PASSWORD` が表示される。

## 追補（2026-06-16: cURL install の shogunate pair shim 更新）

### 要求

1. cURL/package install は、`first_setup.sh` が依存不足などで non-zero 終了しても、`~/.local/bin/shogunate` の command shim を最新化する。
2. 導入後の `shogunate pair` は `Shogunate-Runtime.sh pair` に流れず、`scripts/shogunate_pair_server.py` を直接起動する。
3. `shogunate help` は `pair` と `SHOGUNATE_PAIR_PASSWORD` を表示する。

### 受け入れ条件（観測可能）

1. `scripts/shogunate_package_bootstrap.sh` は `first_setup.sh` 実行前に command shim を生成する。
2. 生成される command shim の `pair)` branch は `python3 scripts/shogunate_pair_server.py` を実行する。
3. `python3 -m unittest tests.unit.test_package_distribution`、`bash -n scripts/shogunate_package_bootstrap.sh`、`git diff --check` が PASS する。

## 追補（2026-06-16: Pair 成功後の SSH 再接続安定化）

### 要求

1. `shogunate pair` は、TCP port が open しているだけの壊れた Windows portproxy / stale forwarding を SSH service と誤判定しない。
2. SSH port 自動検出は SSH banner を確認し、実際に SSH として応答する port を app へ返す。
3. USB 接続では Android 側 `127.0.0.1:2222` を返し、無線/Tailscale/LAN 接続では app が入力した PC address と検出済み SSH port を返す。
4. PC terminal には、承認後に app へ返した SSH 接続先 `user@host:port` を表示する。
5. 内部 SSH port と Android へ返す外向き port が違う構成では `--client-ssh-port` / `SHOGUNATE_CLIENT_SSH_PORT` で上書きできる。

### 受け入れ条件（観測可能）

1. `detect_ssh_port()` は SSH banner を返さない open port をスキップする。
2. Pair approval 後、terminal に `returning SSH destination: user@host:port` が表示される。
3. 無線/Tailscale/LAN では、app が入力した host に対して SSH banner を返す port を候補から選ぶ。
4. `python3 -m unittest tests.unit.test_shogunate_pair_server`、`python3 -m py_compile scripts/shogunate_pair_server.py`、`git diff --check` が PASS する。

## 追補（2026-06-16: Pair 完了表示と自動終了）

### 要求

1. `shogunate pair` は非エンジニアにも完了が分かるよう、成功時に `Pairing complete`、端末名、保存された SSH 接続先、次の操作を表示する。
2. 既定では1台の pairing 成功後に server を自動終了する。
3. 複数端末を連続 pairing したい場合だけ `shogunate pair --keep-running` を使う。
4. `Ctrl-C` で中断した場合は、成功完了と誤解される表示を出さない。

### 受け入れ条件（観測可能）

1. Pair 成功後、terminal に `Pairing complete` と `Shogunate pair stopped after successful setup.` が表示される。
2. `--keep-running` 指定時は成功後も server が待受を継続する。
3. `python3 -m unittest tests.unit.test_shogunate_pair_server`、`python3 -m py_compile scripts/shogunate_pair_server.py`、`git diff --check` が PASS する。
