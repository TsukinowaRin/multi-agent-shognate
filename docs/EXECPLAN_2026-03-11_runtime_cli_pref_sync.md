# ExecPlan: Runtime CLI設定の次回起動反映

## Context
- ユーザーは各 pane 内で `model` や `thinking/reasoning` を変更した後、次回起動時にも同じ設定で再起動してほしいと要求している。
- 現状の正本は `config/settings.yaml` だが、pane 内での live 変更は設定ファイルへ戻していない。
- tmux 本線では既存 session を起動前に破棄するため、破棄前に live state を同期すれば次回起動へ反映できる。

## Scope
- `tmux` pane の live state を読み取り、`config/settings.yaml` へ同期するスクリプトを追加する。
- `shutsujin_departure.sh` の既存 session cleanup 前に同期を自動実行する。
- 対象はまず `Codex` と `Gemini` の runtime 変更とする。

## Acceptance Criteria
1. `Codex` pane での model / reasoning 変更が、次回 `shutsujin_departure.sh` 実行前に `config/settings.yaml` へ同期される。
2. `Gemini` pane での model 変更が、次回 `shutsujin_departure.sh` 実行前に `config/settings.yaml` へ同期される。
3. `Gemini` alias が判別できる場合、対応する `thinking_level` / `thinking_budget` も同期される。
4. session が存在しない場合は no-op で終わり、起動を妨げない。

## Work Breakdown
1. `REQS` / `INDEX` / ExecPlan を更新する。
2. `scripts/sync_runtime_cli_preferences.py` を追加する。
3. `shutsujin_departure.sh` に pre-cleanup 同期フックを追加する。
4. 単体テストを追加する。
5. `WORKLOG` を更新し、checkpoint で commit する。

## Progress
- 2026-03-11: 開始。

## Surprises & Discoveries
- なし（開始時点）。

## Decision Log
- live state の同期は background watcher ではなく、次回起動直前の pre-cleanup で行う。
- 最初の対象 CLI は `Codex` / `Gemini` とし、他 CLI は明示対応まで現状維持にする。

## Outcomes & Retrospective
- 進行中。
