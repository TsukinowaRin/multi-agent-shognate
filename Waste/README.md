# Waste

このディレクトリは、上流 `multi-agent-shogun` を基準に再出発する際に退避した旧基盤の保管場所です。

- 目的: 置換前の独自実装を参照可能な状態で残す
- 方針: runtime で参照しない。比較・復旧・差分確認のためだけに保持する
- 基準日: 2026-03-07

現在の主な退避内容:
- `restart_2026-03-07_core/AGENTS.md.before_upstream`
- `restart_2026-03-07_core/shutsujin_departure.sh.before_upstream`
- `restart_2026-03-07_core/first_setup.sh.before_upstream`
- `restart_2026-03-07_core/cli_adapter.sh.before_upstream`
- `restart_2026-03-07_core/build_instructions.sh.before_upstream`
- `restart_2026-03-07_core/inbox_watcher.sh.before_upstream`
- `zellij_2026-03-11/` - 廃止した zellij 実装と関連テストの初回退避。
- `tmux_unification_2026-03-11/` - `shutsujin_departure.sh` 一本化に伴い廃止した `goza*` / `shutsujin_zellij.sh` / 旧テンプレート / 旧 bat ランチャー。
