# ExecPlan: Shogunate 軍監 Role 追加

作成日: 2026-05-28

## 目的

Shogunate 独自の `gunkan`（軍監）を、将軍直属・家老並列の独立監査 role として追加する。軍監は CoDD をオンデマンド監査ツールとして使い、通常フローの進行管理や中間報告取得は家老に残す。

## 現状

- 本家/現行の `gunshi` は `Karo -> Gunshi -> Karo` の参謀・高度QC役。
- Shogunate runtime は `shogun`, `gunshi`, `karo*`, `ashigaru*` を固定的に扱う箇所が多い。
- instruction generation は `scripts/build_instructions.sh` が `instructions/roles/<role>_role.md` を CLI 別に展開する。
- role CLI 設定は `scripts/configure_runtime_roles.py` の `CORE_ROLES` が対象。

## 判断

- 軍監LLMは常時監視AIにはしない。通常の状況把握・中間報告取り寄せは `将軍 -> 家老` で行う。
- リアルタイム検知は非LLMの軽量 watcher で行う。軽量 watcher は queue / reports / dashboard / git diff / CoDD 設定を低コストに検査し、異常時だけ軍監LLMへ `audit_requested` を送る。
- `inbox_write` は非LLMの軽量イベントログを残す。軍監LLMへの nudge は `audit_requested` / `audit_failed` / `runtime_blocked` / `emergency_stop_requested` 等の監査イベント時のみ。
- ただし、御座の間の軍監 pane は常時対話可能な LLM pane として扱う。ユーザーまたは将軍が軍監 pane へ直接指示した場合は、inbox event を待たず監査・検証・停止判断・功績整理・リスク確認に即応する。
- CoDD は常駐 runtime ではなく `scripts/gunkan_codd_audit.py` 経由で呼び出す。`codd` CLI が入っていない環境では組み込みの整合性チェックへフォールバックする。
- 軍監は `queue/reports/gunkan_report.yaml` を canonical report とし、必要に応じて `queue/inbox/shogun.yaml` / `queue/inbox/<karo>.yaml` へ通知する。
- 軍監は通常タスク割当をしない。是正要求は家老宛に出し、最終判断は将軍が行う。
- `scripts/gunkan_codd_audit.py` は `PATH` 上の `codd` に加え、repo-local `.shogunate/codd-venv/bin/codd` / `.shogunate/codd-venv/Scripts/codd.exe` も検出する。
- 軍監 audit nudge は、同じ未読監査イベントで Codex 入力欄に同文を積み続けないよう cooldown する。監査後は発火元 inbox message を `read: true` にする。

## 手順

1. role source と base instruction を追加する。
2. build system / OpenCode permissions / generated outputs を軍監対応にする。
3. CLI adapter / role configurator を軍監対応にする。
4. Shutsujin runtime の pane、bootstrap、queue init、watcher、shortcuts を軍監対応にする。
5. 軽量イベントログと CoDD audit wrapper を追加する。
6. 軽量軍監 watcher を追加し、runtime daemon session へ組み込む。
7. CoDD config と frontmatter docs を追加し、軍監/監視/監査の関係 graph を作る。
8. docs と unit tests を更新し、生成・構文・Bats を実行する。

## 検証

- `bash scripts/build_instructions.sh`
- `bash -n Shutsujin.sh Shogunate-Runtime.sh shutsujin_departure.sh scripts/goza_no_ma.sh scripts/focus_agent_pane.sh scripts/inbox_watcher.sh scripts/watcher_supervisor.sh`
- `python3 -m py_compile scripts/configure_runtime_roles.py`
- `python3 -m py_compile scripts/gunkan_event_log.py scripts/gunkan_codd_audit.py`
- `bats tests/unit/test_build_system.bats tests/unit/test_configure_runtime_roles.bats tests/unit/test_runtime_launchers.bats tests/unit/test_watcher_supervisor.bats`
- `git diff --check`

## 実LLM検証（2026-05-28）

- Test folder: `/mnt/d/git_workspace/multi-agent-shognate/Shogunate-test`
- Config:
  - `shogun`, `karo`, `gunshi`: Codex
  - `ashigaru1`, `ashigaru2`: OpenCode
  - `ashigaru3`: Codex
  - `ashigaru4`: Antigravity
  - `gunkan`: Codex `gpt-5.5`, reasoning `high`
- CoDD: Test folder の `.shogunate/codd-venv` に `codd-dev` を導入し、`scripts/gunkan_codd_audit.py --scope runtime --parent-cmd cmd_gunkan_llm_001` から実行できることを確認。
- Runtime: dedicated tmux session `shogunate-gunkan-llm-20260528155816` で実CLI起動を確認。8/8 pane が起動し、軍監 Codex は `gpt-5.5 high` で起動。
- Scenario: 完了扱いの demo task に対し、検証未実行・README 手順不足・実装/報告不整合を含む状態で `audit_requested` を送信。
- Result: 軍監は CoDD wrapper を実行し、`queue/reports/gunkan_report.yaml` に `status: failed` を記録。`queue/inbox/gunkan.yaml` は `read: true` へ更新し、将軍へ `audit_report`、家老へ `audit_action_required` を通知。
- Observed fixes:
  - 初回起動で端末幅に対して右カラム幅を固定しすぎ、shogun/gunkan pane が 1 列、gunshi pane が 0 高さになる問題を修正。
  - 軍監が作業中でも watcher が同じ audit nudge を連続投入する問題を cooldown で修正。
- CoDD note: 現状の docs は CoDD YAML frontmatter を持たないため、`codd validate` は repo-wide warning を出す。軍監はこれを対象 task の失敗とは分離して扱う。

## 軽量監視 + CoDD graph 追加（2026-05-28）

- 軍監LLMの常時稼働は避け、`scripts/gunkan_light_watch.py` を非LLMの常駐監視器として追加。
- 監視対象:
  - `queue/**/*.yaml` の YAML parse error
  - `queue/reports/*_report.yaml` の failed/error/blocked 報告
  - 完了扱いなのに verification / tests / evidence が無い報告
  - `dashboard.md` の完了扱いと検証不足の同居
  - `.codd/codd.yaml` / `docs/codd/*.md` の欠落
  - git diff の新規 dirty file のうち、秘密情報っぽい path や破壊的コマンドを含む差分
- 出力:
  - `queue/runtime/gunkan_watch.yaml`
  - `queue/runtime/gunkan_light_watch_state.yaml`
  - warning/error finding が cooldown を超えた時だけ `queue/inbox/gunkan.yaml` へ `audit_requested`
  - 初回起動時の既存 finding は baseline として記録し、古い report や dirty diff だけで軍監LLMを起こさない。新規または cooldown 超過の finding だけ通知する。
- runtime:
  - `shutsujin_departure.sh` が runtime daemon session に `gunkan-watch` window を作る。
  - 既定 interval は `MAS_GUNKAN_WATCH_INTERVAL=20` 秒、cooldown は `MAS_GUNKAN_WATCH_COOLDOWN=300` 秒。
- CoDD:
  - `.codd/codd.yaml` を tracked config として追加。
  - `docs/codd/` に frontmatter docs を置き、軍監監視 requirement、軽量 watcher design、CoDD audit design、tests を graph 化。
  - `scripts/codd_check.sh` と `make codd*` targets で install / scan / validate / gunkan audit を呼べる。
- Verification:
  - `/mnt/d/.../Shogunate-test/.shogunate/codd-venv/bin/codd scan --path .` → 4 frontmatter docs, 24 graph nodes, 16 edges。
  - `/mnt/d/.../Shogunate-test/.shogunate/codd-venv/bin/codd validate` → PASS。
  - `PATH=<codd-venv> python3 scripts/gunkan_codd_audit.py --scope manual --parent-cmd smoke_gunkan_watch` → `status: passed`, `scan/impact/validate` all returncode 0。

## 復旧

問題が出た場合は、軍監を `cli.agents.gunkan` から削除し、`BACKEND_AGENT_IDS` / generated instruction 追加を戻せば既存 role 構成に戻せる。既存 queue の軍監ファイルは未参照なら無害。
