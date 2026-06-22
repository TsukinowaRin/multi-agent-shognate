# ExecPlan: Optimization / Role / CLI Harnesses

最終更新: 2026-06-21

## 目的

Shogunate の最適化処理を、Gunkan の監査・助言と Shogun/Karo の通常指揮系統に分ける。併せて、対応 AI CLI と各役職の harness を MOD 側正本として追加し、生成 instruction に自動挿入する。

## 受け入れ条件

- `shogunate_mod/instructions/source/harnesses/` に common / role / CLI harness がある。
- `scripts/build_instructions.sh` が全 CLI / 全役職の generated instruction へ harness を差し込む。
- OpenCode agent 定義にも同じ MOD harness が入る。
- Gunkan は `optimization_requested` と structured optimization advisory を扱える。
- Role harness は侍・戦国 persona を維持しつつ、command / task / report / advice / audit packet と検証証跡を明示する。
- Bats test が harness と persona / packet discipline の生成契約を確認する。

## 設計判断

- Optimization は自動編集ループにしない。最適化は安全性と役職境界を崩しやすいため、まず advisory とし、実装が必要な場合だけ Shogun/Karo が通常 command/task へ戻す。
- CLI 差分は `cli_specific/*_tools.md` ではなく `harnesses/cli/*.md` に分ける。tool 説明と agentic operation best practice を混ぜないため。
- Role 差分は既存 `roles/*_role.md` を巨大化させず、`harnesses/roles/*.md` として追加する。本家 role 更新時の追従差分を小さく保つため。

## 実装手順

1. `docs/REQS.md` に今回の要求と観測可能な受け入れ条件を追記する。
2. common / role / CLI harness を `shogunate_mod/instructions/source/harnesses/` に追加する。
3. `shogunate_mod/instructions/build.sh` で generated instruction と OpenCode agent 定義へ harness を挿入する。
4. Gunkan role 正本に `optimization_requested` と report schema を追記する。
5. Bats test に harness 生成契約を追加する。
6. instruction を再生成し、`bash -n` と Bats で検証する。

## 検証予定

- `bash -n shogunate_mod/instructions/build.sh`
- `bash scripts/build_instructions.sh`
- `bats shogunate_mod/tests/unit/test_build_system.bats`
- `bats tests/unit/test_build_system.bats`
- `git diff --check`

## 進捗

- [x] 要求を `docs/REQS.md` に追記。
- [x] ExecPlan を作成。
- [x] MOD harness sources を追加。
- [x] builder と OpenCode agent generation を harness 対応。
- [x] Gunkan role に optimization advisory schema を追加。
- [x] Bats 生成契約を追加。
- [x] instruction 再生成。
- [x] 検証実行。

## 検証結果

- PASS: `bash -n shogunate_mod/instructions/build.sh`
- PASS: `bash scripts/build_instructions.sh`
- PASS: `bats tests/unit/test_build_system.bats`
- PASS: `bats shogunate_mod/tests/unit/test_build_system.bats`
- PASS: `git diff --check`

## 追補実施（2026-06-21: role harness refresh）

- `role_best_practices.md` に `Persona Preservation`、`Harness Packet`、narrow delegation、検証失敗時の報告規律を追加。
- `shogun.md` に `Command Packet` と Shogun persona を追加。
- `karo.md` に `Task Packet`、並列化の独立検証条件、Karo persona を追加。
- `ashigaru.md` に plan-act-verify-report、`Report Packet`、Ashigaru persona を追加。
- `gunshi.md` に `Advice Packet`、選択肢・confidence・検証実験、Gunshi persona を追加。
- `gunkan.md` に severity taxonomy、`Audit Packet`、Gunkan persona を追加。
- `test_build_system.bats` に persona / packet discipline の生成契約を追加。

追補検証:

- PASS: `bash scripts/build_instructions.sh`
- PASS: `bats tests/unit/test_build_system.bats`
- PASS: `bats shogunate_mod/tests/unit/test_build_system.bats`

## 残リスク

- 今回は instruction / harness の生成契約までの検証。実AI runtime 上で「Gunkan へ optimization_requested を投げて advisory を返す」E2E は未実施。
- CLI harness の内容は公式 docs と現行 Shogunate 運用に基づく軽量ガードであり、各 CLI の将来仕様変更時は該当 `harnesses/cli/*.md` を更新する。

## 復旧

- 問題が出た場合は `shogunate_mod/instructions/source/harnesses/` と builder の harness 挿入差分だけを見直す。
- 既存 runtime / Android / package 経路はこの計画では変更しない。
