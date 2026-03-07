# ExecPlan: upstream restart for zellij / gemini

## Context
- ユーザーは、コピー元で内部構造が大きく変わったため、実装を最初からやり直してよいと明示した。
- 上流 2026-03 時点では `agent_status` や `AGENTS.md` が進化しており、このフォークの古い基盤より整っている。

## Scope
- 上流共通基盤の再採用
- `zellij` 対応
- `Gemini CLI` 対応
- 関連 Docs とテスト

## Acceptance Criteria
- 上流基盤の一部が本ワークツリーに再導入される。
- 置換前ファイルは `_trash/restart_2026-03-07_core/` に退避される。
- watcher は `lib/agent_status.sh` を用いた busy 判定に更新される。
- 次段の `shutsujin_departure.sh` / `cli_adapter.sh` 再構築方針が文書化される。

## Work Breakdown
1. REQS を再定義する。
2. 置換前ファイルを退避する。
3. 上流 `AGENTS.md` と `lib/agent_status.sh` を導入する。
4. watcher を上流 busy 判定基盤へ接続する。
5. 次段で `shutsujin_departure.sh` / `cli_adapter.sh` / `build_instructions.sh` を上流ベースで再構築する。

## Progress
- 2026-03-07: 再出発方針を採用。
- 2026-03-07: 旧基盤を `_trash/restart_2026-03-07_core/` に退避し、`AGENTS.md` と `lib/agent_status.sh` を上流基準へ更新。
- 2026-03-07: 上流完全クローン `original_full_2026-03-07` を基準参照として追加し、追跡可能な `Waste/` を正式な退避先として使う方針へ更新。
- 2026-03-07: pure zellij の bootstrap 再失敗を受け、`goza_zellij.sh` を安定経路（zellij UI + tmux backend）へ戻し、pure zellij は `goza_zellij_pure.sh` へ分離。
- 2026-03-07: pure zellij の bootstrap を「外側のアクティブペイン注入」から「paneごとの dedicated runner + bootstrap file」へ切り替えた。
- 2026-03-07: `configure_agents.sh` を拡張し、`gunshi` / `Codex reasoning_effort` / `Gemini thinking_level|thinking_budget` を永続設定できるようにした。
- 2026-03-07: `scripts/sync_gemini_settings.py` を追加し、workspace `.gemini/settings.json` の `customAliases` へ per-agent Gemini 設定を同期するようにした。
- 2026-03-07: `OpenCode` / `Kilo` を CLI種別として追加し、`scripts/sync_opencode_config.py` で project-level `opencode.json` を生成、`configure_agents.sh` から shared provider 設定も保存できるようにした。

## Surprises & Discoveries
- 上流とこのフォークは merge base を素直に辿れないほど履歴が離れている。
- よって Git 履歴マージではなく、ファイル単位での基盤再採用が現実的。

## Decision Log
- 全面削除ではなく「退避して再採用」を選ぶ。
- まず runtime 安全性に寄与する `AGENTS.md` / `agent_status` / watcher から着手する。
- `README_ja.md` の全面同期は runtime が再整備されてから行う。
- shallow 参照ではなくフルクローン参照を正本とする。
- 退避先は `_trash/` のみではなく、追跡可能な `Waste/` にも置く。
- pure zellij は保持するが、ユーザー向け既定コマンドには使わない。理由は実機で「CLI未起動・初動未注入」が継続しているため。
- pure zellij の本文配送は multiplexer 注入でなく file-based bootstrap に寄せる。理由は upstream の inbox 設計が「本文はファイル、multiplexer は起床通知のみ」であり、現状の focus 依存注入は agent 取り違えを起こしているため。
- Gemini の思考設定は CLIフラグ直指定ではなく `.gemini/settings.json` 生成を採用する。理由は公式 schema が `modelConfigs.customAliases` を前提としており、role ごとの恒久設定と相性がよいため。
- Codex の思考設定は `-c model_reasoning_effort='<value>'` を採用する。理由は現行 CLI が `-c key=value` オーバーライドを正式に受け付けているため。
- OpenCode と Kilo は同系統の CLI なので、project provider 設定は `opencode.json` へ一本化し、role ごとの差は `config/settings.yaml` の `type/model` に閉じ込める。理由は provider/base URL/API key まで role ごとに持たせるより設定の一貫性が高いため。

## Outcomes & Retrospective
- 進行中。次段は `scripts/zellij_agent_bootstrap.sh` の実機確認、`Gemini` 初回 trust/high-demand の完全自動化、および `OpenCode/Kilo` の README 導線補強。
