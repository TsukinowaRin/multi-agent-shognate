# ExecPlan: Upstream v4.4.1 Sync Into Shognate

## Context
- 現在の fork `main` は `fb5e315`、`upstream/main` は `3dafe0a` まで進んでいる。
- 共通基盤は `ac55b73` で upstream v4.2.0 を merge 済みだが、その後この fork は Android release、portable installer/uninstaller、追加 CLI、docs 運用の独自差分を積んでいる。
- 今回は upstream の 12 commit を最新まで取り込みつつ、この fork の独自価値を壊さず共存させる必要がある。

## Scope
- `upstream/main` を `codex/upstream-sync-2026-03-29` に merge する。
- 衝突候補の `android/`, `scripts/ratelimit_check.sh`, `shutsujin_departure.sh`, `instructions/*karo*`, `docs/` を確認し、必要な手動解消を行う。
- docs に今回の判断と停止点を残す。

## Acceptance Criteria
1. `git merge --no-ff --no-edit upstream/main` が完了し、未解決 conflict がない。
2. `bash -n shutsujin_departure.sh scripts/ratelimit_check.sh` が成功する。
3. `cd android && GRADLE_USER_HOME=... ./gradlew :app:assembleDebug` が成功する。
4. `bats tests/unit/test_interactive_agent_runner.bats` と、`pytest` が無い環境では `python3 -m unittest tests.unit.test_update_manager` が成功する。
5. `git diff --check` が空で終わる。

## Work Breakdown
1. upstream 差分と既存同期 docs を読み、今回の衝突面を特定する。
2. `REQS` と本 ExecPlan を作成し、同期方針を固定する。
3. merge を実施し、conflict が出たファイルを fork の独自要件に合わせて解消する。
4. Android build と代表テストで回帰を確認する。
5. `docs/WORKLOG.md` と必要なら `docs/INDEX.md` を更新して checkpoint を切る。

## Progress
- [x] (2026-03-29 14:xx) upstream `main` を fetch し、`3dafe0a` まで進んでいることを確認。
- [x] (2026-03-29 14:xx) `codex/upstream-sync-2026-03-29` を作成。
- [x] (2026-03-29 14:1x) `git merge --no-ff --no-edit upstream/main` を実施し、競合 8 ファイルを解消。
- [x] (2026-03-29 14:2x) `bash -n`, `git diff --check`, `bats tests/unit/test_interactive_agent_runner.bats`, `python3 -m unittest tests.unit.test_update_manager` を通過。
- [x] (2026-03-29 14:3x) Android を workspace-local `GRADLE_USER_HOME` / `HOME` で `:app:assembleDebug` 成功。
- [ ] docs / WORKLOG 更新

## Surprises & Discoveries
- Observation: `HEAD...upstream/main` は `321` 対 `12` で、この fork 側の独自履歴がかなり厚い。
  Evidence: `git rev-list --left-right --count HEAD...upstream/main` → `321 12`
- Observation: upstream 差分は広いが、直近 12 commit での実衝突候補は限定的。
  Evidence: `git diff --stat HEAD...upstream/main` では Android UI/SSH、`scripts/ratelimit_check.sh`、`shutsujin_departure.sh`、`karo` instructions、`reports/` 追加が目立つ。
- Observation: Android build は repo 外の既定 `HOME` を見に行くため、そのままでは sandbox 下で Kotlin/Gradle daemon が失敗する。
  Evidence: `/home/muro/.android/...` と `/home/muro/.local/share/kotlin/...` への書き込みで read-only error が出たため、workspace-local `HOME` / `GRADLE_USER_HOME` に切り替えて build 成功。

## Decision Log
- Decision: 全面コピーではなく `git merge upstream/main` を基準に統合する。
  Rationale: 履歴を保ったまま upstream 追従と local 変更の両立を確認しやすい。
  Date/Author: 2026-03-29 / Codex
- Decision: 競合解消は upstream 優先ではなく、fork 固有導線を残す観点でファイルごとに判断する。
  Rationale: Android release / portable install / extra CLI はこの fork の公開価値であり、単純上書きは不適切。
  Date/Author: 2026-03-29 / Codex
- Decision: `shutsujin_departure.sh` は fork 側の active topology / bootstrap 実装を維持しつつ、upstream の Claude `--effort max` だけを取り込む。
  Rationale: upstream 側の pane 固定前提へ戻すと、この fork の動的配備と Android 互換 layer が壊れるため。
  Date/Author: 2026-03-29 / Codex
- Decision: `SettingsScreen.kt` は upstream の秘密鍵 picker と fork の host update UI を両立させる。
  Rationale: upstream の UX 改善も、fork 独自の host 更新導線も両方必要なため。
  Date/Author: 2026-03-29 / Codex

## Outcomes & Retrospective
- Outcomes: upstream v4.4.1 系の差分を merge し、Android / instructions / rate-limit / reports を取り込んだ。
- Gaps: Android build は workspace-local `HOME` 指定が必要。CI や別 sandbox では同等の環境変数設定が必要。
- Lessons: Android / Kotlin ツールチェーンは repo 外の user home に逃げるため、sandbox では先に閉じ込め先を用意した方が早い。
- Against Purpose: 目的との差分はなし。
