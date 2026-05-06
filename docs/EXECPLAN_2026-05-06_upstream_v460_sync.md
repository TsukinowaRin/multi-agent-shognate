# Upstream v4.6.0 Sync

## Context

現在の実Gitリポジトリは `multi-agent-shognate/` で、作業ブランチは `codex/upstream-v4.6.0-sync`。フォーク元は `upstream=https://github.com/yohey-w/multi-agent-shogun.git`、上流の HEAD branch は `main`。

2026-05-06 19:51 JST 時点で `git fetch upstream --prune` 済み。`upstream/main` は `4ee1377`、最新タグは `v4.6.0`。現在のフォークは merge-base `d108517` から見て `HEAD` が 391 commits ahead、`upstream/main` が 19 commits ahead。

## Scope

上流 `upstream/main` の最新変更をこのフォークへ取り込み、その後フォーク独自機能を維持・再適用する。単純に上流で上書きせず、既存の Shogunate 独自機能、runtime 改修、multi-CLI、Android/installer、docs/tests を保持する。

対象:
- `AGENTS.md` / `CLAUDE.md` / instruction source / generated instruction
- `scripts/inbox_write.sh`, `scripts/inbox_watcher.sh`, `scripts/switch_cli.sh`, `shutsujin_departure.sh`
- README / CHANGELOG / GitHub metadata
- 上流で追加された `scripts/dashboard-viewer.py`, `scripts/session_start_hook.sh`, `.github/FUNDING.yml`
- 回帰テストと docs

対象外:
- `template-temp/` の削除
- push / release
- runtime 実機 burn-in の長時間再検証

## Acceptance Criteria

- `git merge upstream/main` が完了し、未解決 conflict がない。
- 上流新規ファイルと変更が取り込まれている。
- フォーク独自機能の主要差分が残っている。
- 変更範囲に近い静的検証が通る。
- フォーク元との差分の概要をユーザーへ説明できる。

## Work Breakdown

1. `upstream/main` とフォーク側の差分を把握する。
2. `git merge upstream/main` を実行する。
3. conflict があれば、上流変更を取り込みつつフォーク独自機能を残す方針で解消する。
4. instruction 生成物が必要なら `bash scripts/build_instructions.sh` を実行する。
5. 関連テストを実行する。
6. `docs/REQS.md`, `docs/WORKLOG.md`, この ExecPlan を更新する。

## Progress

- [x] 2026-05-06 19:51 JST: `git fetch upstream --prune` 完了。上流最新 `4ee1377` / tag `v4.6.0` を確認。
- [x] 2026-05-06 19:51 JST: `codex/upstream-v4.6.0-sync` を作成。
- [x] 2026-05-06 19:55 JST: `git merge --no-ff upstream/main` を実行し、conflict を確認。
- [x] 2026-05-06 20:03 JST: conflict を解消。上流の `session_start_hook`, dashboard viewer, `switch_cli`, `inbox_write` 厳格化、Claude permission mode オプションを取り込み、Shogunate 側の multi-CLI / runtime / route policy を保持。
- [x] 2026-05-06 20:08 JST: 関連検証を実行し、PASS を確認。

## Surprises & Discoveries

- Observation: 表層 `D:\Git_WorkSpace\multi-agent-shognate` ではなく、内側 `multi-agent-shognate/` が実Gitリポジトリだった。
  Evidence: `git -C multi-agent-shognate rev-parse --show-toplevel --git-dir --abbrev-ref HEAD` が `<workspace>/multi-agent-shognate`, `.git`, `codex/upstream-sync-2026-03-29` を返した。
- Observation: 上流は v4.4.2, v4.5.0, v4.6.0 の tag を追加していた。
  Evidence: `git fetch upstream --prune` の出力。
- Observation: この fork の shell テストは、実環境の `NVM_BIN` / `PNPM_HOME` にある CLI を拾うと「未インストール」系ケースが不安定になる。
  Evidence: `bats tests/unit/test_cli_adapter.bats` 初回実行で、実機の `/home/muro/.nvm/.../codex`, `gemini`, `kilo` などを検出して失敗。`setup()` で該当 env を unset し、環境変数を command substitution 内へ渡す形へ修正後 PASS。

## Decision Log

- Decision: 同期は既存ブランチへ直mergeせず、新規 `codex/upstream-v4.6.0-sync` ブランチで行う。
  Rationale: 上流同期は衝突可能性があり、既存ブランチを保護するため。
  Date/Author: 2026-05-06 Codex
- Decision: conflict 解消では、上流の新規修正を取り込みつつ、フォーク独自 runtime / multi-CLI / Android / installer 機能を優先して保持する。
  Rationale: ユーザー要求が「フォーク元の最新コード反映後、このリポジトリ独自機能を反映」だから。
  Date/Author: 2026-05-06 Codex

## Outcomes & Retrospective

- 上流 `upstream/main` (`4ee1377`, tag `v4.6.0`) の merge conflict は解消済み。
- 主な取り込み:
  - `scripts/session_start_hook.sh` と `.claude/settings.json` の SessionStart hook。
  - `scripts/dashboard-viewer.py`。
  - `scripts/switch_cli.sh` の未登録 agent block 追加修正。
  - `scripts/inbox_write.sh` の `type/from` 必須化、self-send guard、`od` ベース message id。
  - `scripts/inbox_watcher.sh` の `/clear` / Codex `/new` 後 startup prompt 再送。
  - `shutsujin_departure.sh` / `lib/cli_adapter.sh` の Claude `--permission-mode` 指定導線。
- 保持した Shogunate 独自機能:
  - Codex / Gemini / OpenCode / Kilo / Copilot / Kimi / localapi を含む multi-CLI routing。
  - tmux runtime topology、Android 互換 layer、watcher / bridge / runtime recovery。
  - multi-karo owner routing、足軽 greenfield 分担、installer / updater / Android release 導線。
- 検証:
  - `python3 -m json.tool .claude/settings.json` → PASS
  - `bash -n scripts/inbox_write.sh scripts/inbox_watcher.sh lib/cli_adapter.sh shutsujin_departure.sh scripts/session_start_hook.sh scripts/switch_cli.sh` → PASS
  - `python3 -m py_compile scripts/dashboard-viewer.py` → PASS
  - `git diff --check` → PASS
  - `bats tests/test_inbox_write.bats tests/unit/test_cli_adapter.bats` → PASS (`132` tests)
  - `bats tests/unit/test_switch_cli.bats tests/unit/test_stop_hook.bats tests/agent_selfwatch.bats` → PASS (`45` tests)
- 残リスク:
  - live tmux runtime 起動、Android build、installer smoke は今回未実行。
  - 上流と fork の差分は依然として大きく、README / role instruction の一部は fork 側を優先して保持している。
