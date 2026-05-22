# ExecPlan: CoDD Agent-Native Gate

作成日: 2026-05-22

## 目的

CoDD を「開発者が手動で `make codd` する外部 gate」から、Shogunate の各 agent が通常 workflow の中で使える agent-native quality gate へ引き上げる。

## 方針

- CoDD 本体は vendoring しない。既存どおり `scripts/codd_check.sh` が `.shogunate/codd-venv` に `codd-dev` を導入・更新する。
- agent からの入口は `scripts/agent_codd_gate.sh` に集約する。
- `agent_codd_gate.sh` は CoDD 実行結果を `queue/runtime/codd/` に YAML report と log として残す。
- 役職指示には「いつ CoDD を使うか」「失敗時にどう扱うか」「report YAML にどう記録するか」を入れる。
- Karo は implementation / refactor / release / multi-file 変更の closure 前 gate として CoDD を使う。
- Ashigaru は通常 verification の後に task-local gate として使える。
- Gunshi は CoDD report を設計・QC 判断の証拠として使う。
- package 配布に `.codd/codd.yaml` と agent-facing wrapper を含める。

## 進捗

- [x] 既存 CoDD 統合と role instructions を確認した。
- [x] `scripts/agent_codd_gate.sh` を追加する。
- [x] `instructions/common/codd_gate.md` を追加し、generated instructions / OpenCode agents に組み込む。
- [x] tests / README / package metadata を更新する。
- [x] 検証を実行し、結果を記録する。

## 検証

1. `bash -n scripts/codd_check.sh scripts/agent_codd_gate.sh`
2. `bats tests/unit/test_codd_integration.bats tests/unit/test_codd_agent_gate.bats`
3. `bash scripts/build_instructions.sh`
4. `bats tests/unit/test_build_system.bats`
5. `npm pack --dry-run`
6. `git diff --check`

## 検証結果

2026-05-22 実行:

- `bash -n scripts/codd_check.sh scripts/agent_codd_gate.sh scripts/build_instructions.sh` passed.
- `bats tests/unit/test_codd_integration.bats tests/unit/test_codd_agent_gate.bats tests/unit/test_build_system.bats` passed: 67 tests.
- `npm pack --dry-run` passed with `.codd/codd.yaml` and `scripts/agent_codd_gate.sh` included, and `.codd/dag.json` excluded.
- `git diff --check` passed.
- `bash scripts/agent_codd_gate.sh codex codd_agent_native_gate verify` passed and wrote `queue/runtime/codd/codex_codd_agent_native_gate_verify.yaml`; CoDD reported amber warnings for existing DAG reachability / propagation-output gaps, but exit code was 0.

## 実装結果

- Agent-facing entrypoint として `scripts/agent_codd_gate.sh` を追加した。
- Gate report/log は `queue/runtime/codd/` 配下に agent/task/command 単位で保存する。
- 共通 role instruction `instructions/common/codd_gate.md` を追加し、生成済み instructions と OpenCode agent definitions に組み込んだ。
- `make codd-agent-gate AGENT_ID=<agent> TASK_ID=<task> CODD_COMMAND=verify` を追加した。
- package 配布対象は `.codd/` 全体ではなく `.codd/codd.yaml` に限定し、生成物を混入させない。
- `scripts/build_instructions.sh` は生成 markdown の行末と末尾空白を全 CLI 出力で正規化する。

## 復旧

- agent-facing gate が runtime に悪影響を出す場合は、`scripts/agent_codd_gate.sh` と `instructions/common/codd_gate.md` の組み込みだけを revert する。
- `scripts/codd_check.sh` / `.codd/codd.yaml` の既存統合は維持する。
