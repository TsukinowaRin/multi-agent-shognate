# Upstream Issue Apply Plan

## Context

2026-05-13 に `yohey-w/multi-agent-shogun` の open Issue を取得した。対象は #151, #143, #131, #48。

- #151: `watcher_supervisor.sh` / `shutsujin_departure.sh` の hardcoded pane mapping drift。
- #143: README に「最初の1案件／ソリューションを扱う流れ」を追加してほしい。
- #131: Merxex / agent commerce integration proposal。
- #48: 軍師の自律 PDCA ループと能動ヒアリング。

この fork は既に `goza-no-ma` + `@agent_id` を runtime 正本にしており、複数家老・active ashigaru の動的 roster もある。したがって #151 は実装済み挙動を regression test と docs で固定する方針にする。

## Scope

In scope:

- README / README_ja の初回案件チュートリアル追加。
- 家老 / 軍師 role instruction への proactive clarification と autonomous PDCA loop の追加。
- generated instructions の再生成。
- watcher / mux regression test の補強。
- docs/REQS.md, docs/INDEX.md, docs/WORKLOG.md の同期。

Out of scope:

- #131 の commerce / payment / wallet / escrow 実装。外部決済と secrets を扱うため、別途 security design と明示要求が必要。
- Android App 本体に変更がない場合の APK prerelease。

## Acceptance Criteria

- `gh issue list -R yohey-w/multi-agent-shogun --state open --limit 100 --json number,title,url,updatedAt` で open Issue を確認済み。
- `rg -n "First project|最初の1案件|solution|ソリューション|project workspace" README.md README_ja.md` が該当チュートリアルを検出する。
- `bash scripts/build_instructions.sh && bats tests/unit/test_build_system.bats` が PASS。
- `bats tests/unit/test_mux_parity.bats tests/unit/test_watcher_supervisor.bats` が PASS。
- `git diff --check` が PASS。

## Work Breakdown

1. Upstream Issue を取得し、適用可否を分類する。
2. README 英日へ first project walkthrough を追加する。
3. Karo / Gunshi role source へ自律 PDCA と能動質問ルールを追加する。
4. generated instructions を再生成し、build-system regression を追加する。
5. #151 の `@agent_id` 動的 pane 解決を regression test で固定する。
6. 検証後に commit / push する。
7. Android App 本体に変更が入った場合のみ prerelease APK を公開する。

## Progress

- [x] Upstream open Issue を取得した。
- [x] README / README_ja を更新する。
- [x] role instruction を更新し generated files を再生成する。
- [x] regression test を補強する。
- [x] 検証する。
- [ ] commit / push する。

## Surprises & Discoveries

- #151 の中心問題である fixed pane mapping は、この fork では既に `goza-no-ma` の `@agent_id` 動的解決で解消済み。
- #151 の `gunshi2` は upstream 側の編成案だが、この fork の現在設計は単一 `gunshi` + 複数 Karo / active ashigaru。今回は未定義 role を増やさず、drift 防止の contract を固定する。

## Decision Log

- #131 は通常取り込み対象外にする。理由は wallet / payment / escrow / micro-contract が secrets と法務・セキュリティ領域を含むため。
- #48 は runtime daemon 追加ではなく、まず role instruction contract として実装する。既存の Karo / Gunshi 分業と event-driven 制約を壊さない。

## Outcomes & Retrospective

Validation:

- `bash scripts/build_instructions.sh` -> PASS
- `bats tests/unit/test_build_system.bats` -> PASS
- `bats tests/unit/test_watcher_supervisor.bats` -> PASS
- `bats tests/unit/test_mux_parity.bats` -> PASS
- `rg -n "First project|最初の1案件|solution|ソリューション|project workspace" README.md README_ja.md` -> PASS
- `gh issue list -R yohey-w/multi-agent-shogun --state open --limit 100 --json number,title,url,updatedAt` -> PASS
- `git diff --check` -> PASS

Android App 本体には今回変更を入れていないため、新規 APK prerelease は作成しない。次に Android App 本体を改良した commit では、検証後に prerelease APK を公開する。
