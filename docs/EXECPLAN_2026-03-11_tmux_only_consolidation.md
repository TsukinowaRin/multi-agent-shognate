# ExecPlan: Tmux Only Consolidation

## Context
- ユーザー判断により `zellij` 対応は廃止し、`tmux` のみに一本化する。
- 既存コードは `tmux` / `zellij` / hybrid / pure zellij が混在しており、起動入口・watcher・README・generated instruction まで影響している。
- `zellij` 専用コードは削除ではなく `Waste/` に退避し、必要時に参照できるようにする。

## Scope
- `tmux` を唯一の現役 multiplexer として扱う。
- `zellij` 専用スクリプト・テスト・テンプレート・補助コードを `Waste/` へ退避する。
- `README.md` / `first_setup.sh` / `config/settings.yaml` / `scripts/configure_agents.sh` / `shutsujin_departure.sh` / watcher 系を `tmux` 前提へ更新する。
- 既存 `zellij` 名コマンドは壊さず、tmux へ委譲する薄い互換 wrapper に落とす。

## Acceptance Criteria
1. `config/settings.yaml` と `scripts/configure_agents.sh` が `tmux` 前提である。
2. `shutsujin_departure.sh` が `zellij` へ委譲しない。
3. `scripts/inbox_watcher.sh` / `scripts/watcher_supervisor.sh` に現役の `zellij action` 制御が残らない。
4. `Waste/` に旧 zellij 実装群が退避される。
5. 残存 unit test が PASS する。

## Work Breakdown
1. `REQS` / `INDEX` / `ExecPlan` を更新する。
2. 起動入口を tmux 一本化する。
3. watcher / configurator / setup を tmux 前提へ変更する。
4. zellij 専用コードを `Waste/` へ退避し、必要最小限の互換 wrapper を置く。
5. instruction source を tmux 前提へ更新し、generated を再生成する。
6. README と docs index を整理する。
7. 残存 test を実行し、checkpoint を切る。

## Progress
- 2026-03-11: `Waste/zellij_2026-03-11/` を作成し、旧 zellij 実装・補助コード・テスト・テンプレートを退避。
- 2026-03-11: `goza_no_ma.sh` を tmux 専用 frontend として差し替え。`goza_zellij*.sh` / `goza_hybrid.sh` / `shutsujin_zellij.sh` は tmux 互換ラッパーに変更。
- 2026-03-11: `config/settings.yaml` / `scripts/configure_agents.sh` / `first_setup.sh` / `shutsujin_departure.sh` / `scripts/inbox_watcher.sh` / `scripts/watcher_supervisor.sh` を tmux 前提へ更新。
- 2026-03-11: `README.md` を tmux 専用ガイドへ全面更新。instruction source を tmux 前提へ修正し、generated files を再生成。
- 2026-03-11: `tests/unit/test_mux_parity*.bats` と `tests/unit/test_configure_agents.bats` を tmux-only 前提へ更新し、残存 unit test を通過。
- 2026-03-11: `goza*` / `shutsujin_zellij.sh` / `tmux_templates.yaml` / `start_*goza*.bat` を `Waste/tmux_unification_2026-03-11/` へ退避し、現役起動入口を `shutsujin_departure.sh` のみに縮退。
- 2026-03-11: `startup.template` を `config/settings.yaml` / `first_setup.sh` / `scripts/configure_agents.sh` から削除し、README の起動手順を `shutsujin_departure.sh` へ一本化。

## Surprises & Discoveries
- `scripts/goza_no_ma.sh` は `tmux` 表示と `zellij` 表示の両方を持つ巨大な共通 frontend になっており、単純削除では済まない。
- `inbox_watcher.sh` / `watcher_supervisor.sh` も `zellij action` 分岐を持つため、起動入口だけではなく infrastructure 層まで整理が必要。

## Decision Log
- `zellij` 名のコマンドは完全削除ではなく、tmux への互換 wrapper とする。
- `Waste/` は tracked な退避先として扱う。
- 2026-03-11: 最終判断として `goza*` も現役から外し、wrapper 維持ではなく `Waste/` 退避を採用する。理由は upstream 本線の `shutsujin_departure.sh` と二重導線を持つ意味が薄く、保守負債になるため。

## Outcomes & Retrospective
- tmux-only 方針へ切り替える主要変更は完了。
- 旧 zellij コードは削除せず `Waste/` に退避したため、参照可能性を保ちつつ現役コードから切り離せた。
- 追加で `goza*` と `startup.template` も現役運用から外し、起動導線は `shutsujin_departure.sh` へ一本化した。
- 残る `zellij` / `goza` 記述は履歴 docs と `Waste/` のみで、現役コード・README・設定 CUI には残さない方針へ整理した。
