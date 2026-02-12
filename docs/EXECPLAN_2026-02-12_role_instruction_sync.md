# ExecPlan: 役職指示書の必読化と最適化指示書の自動同期

## Context
- 現状の起動初動はCLI別の指示書参照が中心で、役職共通の正本MDを必ず読む保証が弱い。
- `instructions/generated/*.md` は `scripts/build_instructions.sh` で生成されるが、起動時の自動再生成は未実装だった。
- 要求は「役職別正本MDを必読化」「正本変更時にCodex/Gemini/Claude最適化MDを追従更新」。

## Scope
- `lib/cli_adapter.sh` に役職共通MD解決関数を追加。
- tmux/zellij両起動スクリプトで、初動命令を「正本MD → CLI最適化MD」の順に変更。
- 生成物の更新判定スクリプトを追加し、起動時に自動実行。
- 関連ユニットテストと要件ドキュメントを更新。

## Acceptance Criteria
1. 起動時に各役職で `instructions/<role>.md` が必ず参照される。
2. CLIごとの最適化指示書（`instructions/generated/*`）が追補として参照される。
3. 正本/部品更新後、起動前に自動で `scripts/build_instructions.sh` が走る。
4. `bats tests/unit/test_cli_adapter.bats tests/unit/test_send_wakeup.bats --timing` がPASSする。

## Work Breakdown
1. 役職共通MD解決APIを追加。
2. CLI最適化指示書の返却パスを `instructions/generated/*` に統一。
3. `ensure_generated_instructions.sh` を追加し、更新判定と再生成を実装。
4. tmux/zellij起動フローに再生成チェックと初動命令更新を反映。
5. テスト・REQS・INDEX・WORKLOGを更新。

## Progress
- 2026-02-12: `get_role_instruction_file()` を追加し、`get_instruction_file()` を generatedパス返却へ統一。
- 2026-02-12: `scripts/ensure_generated_instructions.sh` を追加し、source更新時のみ再生成する仕組みを実装。
- 2026-02-12: `shutsujin_departure.sh` / `scripts/shutsujin_zellij.sh` に自動同期と初動命令（正本→最適化）を反映。
- 2026-02-12: `tests/unit/test_cli_adapter.bats` を新仕様に合わせて更新し、回帰テストPASSを確認。

## Surprises & Discoveries
- 既存の `get_instruction_file()` は `codex`/`copilot` で実在しないパスを返すケースがあり、起動初動の案内が実体とずれる余地があった。
- zellij側はtmux側と異なり初動命令投入が未実装だったため、同等化が必要だった。

## Decision Log
- 役職共通MDはCLIに依存しない正本として `instructions/<role>.md` を採用。
- 最適化MDは `instructions/generated/*` を単一の正規パスとして採用。
- 自動再生成は「毎回強制」ではなく「mtime差分検知」で必要時のみ実行し、起動時間と一貫性を両立。
- 再生成失敗時は起動を止めず警告継続とし、運用停止リスクを下げる。

## Outcomes & Retrospective
- 役職ベース運用（将軍/家老/足軽の共通指示）とCLI最適化差分の分離が明確になった。
- 生成物の手動メンテ負担を軽減し、正本更新の反映漏れリスクを下げた。
- 今後は `scripts/build_instructions.sh` の出力対象追加時に `ensure_generated_instructions.sh` のターゲット配列も合わせて更新する必要がある。
