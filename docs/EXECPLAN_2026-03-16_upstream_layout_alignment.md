# ExecPlan: Upstream Layout Alignment

## Context
- ユーザー要求は、最新 upstream を反映したうえで、このフォークのファイル配置と構成を upstream に近づけること。
- 現在の履歴上では `upstream/main` はすでに取り込み済みだが、トップレベルに upstream にはない退避済みランチャーが残っている。
- このフォーク独自の価値は CLI 拡張、Android 配布、運用 docs にあり、現役導線を壊さずに upstream に寄せる必要がある。

## Scope
- 最新 `upstream/main` が反映済みであることを Git の merge 結果で確定する。
- 現役トップレベル構成を upstream に近づける。
- 独自差分は `docs/`, `scripts/`, `lib/`, `Waste/` に閉じ込め、履歴上の退避物をトップレベルから外す。

## Acceptance Criteria
1. `git merge --no-ff --no-edit upstream/main` が `Already up to date.` を返すこと。
2. top-level に upstream 由来でない現役外ランチャーが残っていないこと。
3. `docs/INDEX.md`, `docs/REQS.md`, `docs/WORKLOG.md` に今回の整理方針が反映されていること。

## Work Breakdown
1. upstream 追従状態を Git で確定する。
2. 現役でない top-level 退避ファイルを削除または `Waste/` に閉じ込める。
3. docs に今回の判断を記録する。
4. 最低限の構文/回帰確認を行う。

## Progress
- 2026-03-16: `git fetch upstream --prune` 実施。
- 2026-03-16: top-level 差分、scripts/lib/tests の独自差分を棚卸し。

## Surprises & Discoveries
- `upstream/main` に対する ahead/behind は `0 268` で、最新 upstream はすでに履歴へ取り込み済みだった。
- top-level の現役差分として最も不要だったのは、未参照の `start_zellij_pure.bat` だった。

## Decision Log
- upstream 最新反映は no-op merge をもって確認する。
- 構成整理は「現役構成を upstream に寄せる」範囲に留め、CLI 拡張や docs は既存位置を維持する。
- `Waste/` は archive として保持し、現役トップレベルとは分離したままにする。

## Outcomes & Retrospective
- 進行中。
