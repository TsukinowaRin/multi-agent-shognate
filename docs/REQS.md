# Requirements (Normalized)

最終更新: 2026-05-25
出典: ユーザー要求「最新の本家リポジトリをベースに Shogunate 独自機能を実装し直す」

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
