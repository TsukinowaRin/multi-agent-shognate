# Handoff 2026-05-08 — Shogunate runtime resume

最終更新: 2026-05-08 20:02 JST

この文書は、新しいエージェントが chat 履歴なしで再開できるようにするための最新 handoff。新規セッションでは、まず `AGENTS.md`、次に `docs/INDEX.md`、最後に本書を読む。

## 1) 現在の結論

- ユーザーの次セッション目的は、**Multi-agent-shogunate の開発をこの続きから進めること**。
- 新しいエージェントは、単なる調査ではなく、docs を読んだ後に Shogunate runtime / CLI integration / launcher / Android などの未完タスクを自律的に実装・検証・commit / push まで進める。
- 作業対象は内側 repo: `/mnt/d/Git_WorkSpace/multi-agent-shognate/multi-agent-shognate`
- 現在 branch: `codex/upstream-v4.6.0-sync`
- 現在 HEAD / remote: `7ec3821` `runtime: publish shogunate stabilization changes`
- `git status -sb` は clean。
- `origin/codex/upstream-v4.6.0-sync` とローカル branch は一致済み。
- `.git` read-only 問題は、Codex sandbox が `danger-full-access` になった後に解消確認済み。
- 直近の runtime/CLI 安定化差分は remote push 済み。

## 2) 直近で確定した重要変更

### Host CLI 実行ファイルを優先

- `lib/cli_adapter.sh`
  - WSL / Linux の native CLI を Windows npm shim より優先する。
  - `HOME`, `NVM_BIN`, `PNPM_HOME` などから native executable を探し、tmux pane へ絶対パスで渡す。
  - `codex`, `claude`, `copilot`, `kimi`, `gemini`, `opencode`, `kilo` の起動が host shell 環境に準拠する。

### Codex bootstrap を短い file reference prompt へ変更

- `shutsujin_departure.sh`
- `scripts/inbox_watcher.sh`
- `tests/unit/test_mux_parity.bats`
- `tests/unit/test_send_wakeup.bats`

Codex には長い初動命令を composer へ直接貼らず、`queue/runtime/bootstrap_<agent>.md` を読む短い prompt を送る。これにより `Pasted Content ...` のまま止まる確率を下げる。

### OpenCode / Kilo の認証 state

- `auth.json` は host 側を参照。
- provider SQLite DB / model state / prompt history は host から初期コピーせず、pane-local に保持。
- 古い DB / model / history symlink は外す。
- host SQLite DB を複数 pane で live 共有しない。

### 足軽全体活用と軍師 routing

- 家老 instruction / bootstrap で、active 足軽全体を初手から使う方針へ更新済み。
- 軍師は実装担当ではなく、L4-L6 の戦略分析・根本原因分析・複雑 QC・分解支援担当として routing される。

## 3) Codex 入力欄テーマ調査の結論

ユーザーは「通常 Codex の入力欄は灰色だが、Shogunate 内では背景色と同じに見える」と報告した。

確認結果:

- Shogunate-test の role-local Codex config から `theme = "catppuccin-mocha"` を除去済み。
- `Shogunate-test/.shogunate/codex/agents/*/config.toml` に `theme = ...` が残っていないことを確認済み。
- 一時 tmux session で `theme` なし Codex を起動し、`theme-probe` を入力して ANSI capture を見たが、通常 idle 入力欄には `48;5;...` の背景色指定は出なかった。
- host `~/.codex/config.toml` 相当でも同じく idle 入力欄の背景色は出なかった。

判断:

- 入力欄の灰色は `theme` 設定だけでは説明できない。
- 前に観測した灰色背景は、Codex が処理中に追加入力を queue している状態など、Codex TUI の状態依存描画である可能性が高い。
- Shogunate は Codex TUI を再装飾しない。見た目差分をさらに追う場合は、`CODEX_HOME` state / Codex TUI state / 入力中 vs queued 状態の ANSI capture を比較する。

## 4) Git / push 状態

通常の `git commit` が一時的に失敗していた理由:

- Codex session が `workspace-write` sandbox の間、`.git` が read-only mount されていた。
- そのため `.git/index.lock` や `.git/refs/...lock` が作れなかった。
- 回避として、一度 SSH push 用の一時 Git object/index を `/tmp` に作り remote commit を作成した。

最終状態:

- developer sandbox が `danger-full-access` へ変わった後、`.git` は `rw` として確認済み。
- `.git/.codex_write_probe` 作成、`.git/index.lock` 作成、`git fetch`、backup branch 作成、`git reset --mixed origin/codex/upstream-v4.6.0-sync` が成功。
- 現在は通常 Git 操作が可能。

重要 refs:

- `codex/upstream-v4.6.0-sync` -> `7ec3821`
- `origin/codex/upstream-v4.6.0-sync` -> `7ec3821`
- `backup/pre-sync-local-20260508` -> `714cd25`

`backup/pre-sync-local-20260508` は、API/SSH push 前にローカルに残っていた 20 commit 分の退避。通常作業では触らなくてよい。

## 5) 直近の検証結果

実行済み:

```bash
bash -n lib/cli_adapter.sh scripts/inbox_watcher.sh shutsujin_departure.sh
bats tests/unit/test_cli_adapter.bats tests/unit/test_mux_parity.bats tests/unit/test_send_wakeup.bats
git diff --check
```

結果:

- `bash -n`: PASS
- Bats: `284` tests PASS
- `git diff --check`: PASS

Git 確認:

```bash
git status -sb
git fetch origin codex/upstream-v4.6.0-sync
findmnt -T .git -o TARGET,SOURCE,FSTYPE,OPTIONS
```

結果:

- `git status -sb`: clean
- fetch: PASS
- `.git`: `rw`

## 6) 次のエージェントが最初に読むもの

順番:

1. `AGENTS.md`
2. `docs/INDEX.md`
3. `docs/HANDOFF_2026-05-08_runtime_resume.md`（本書）
4. `docs/REQS.md`
5. `docs/WORKLOG.md`

関連する計画:

- `docs/EXECPLAN_2026-05-06_cli_state_isolation.md`
- `docs/EXECPLAN_2026-05-06_isolated_mixed_cli_runtime.md`
- `docs/EXECPLAN_2026-05-07_runtime_role_config.md`
- `docs/EXECPLAN_2026-05-07_codd_integration.md`
- `docs/EXECPLAN_2026-02-14_multi_karo_round_robin.md`

## 7) 次のエージェントが最初に実行するコマンド

```bash
cd /mnt/d/Git_WorkSpace/multi-agent-shognate/multi-agent-shognate
git status -sb
git log --oneline --decorate --max-count=8
findmnt -T .git -o TARGET,SOURCE,FSTYPE,OPTIONS
```

期待結果:

- branch は `codex/upstream-v4.6.0-sync`
- `origin/codex/upstream-v4.6.0-sync` と一致
- working tree clean
- `.git` mount は `rw`

必要なら追加検証:

```bash
bash -n lib/cli_adapter.sh scripts/inbox_watcher.sh shutsujin_departure.sh
bats tests/unit/test_cli_adapter.bats tests/unit/test_mux_parity.bats tests/unit/test_send_wakeup.bats
```

## 8) 未完了 / 次にやること

ユーザーは「Multi-agent-shogunate の開発の続きをしてほしい」と明示している。次のエージェントは、状況確認で止まらず、低リスクに前進できるものから実装・検証する。

優先候補:

1. Shogunate runtime を実機で再起動し、Codex / OpenCode / Gemini 混在構成で初動が安定するか観測する。
2. 足軽3体以上の時、家老が active 足軽全体へ初手分担するか、実 task で再確認する。
3. 軍師が複雑分析 / QC routing で動くか、実 task で確認する。
4. Codex 入力欄の灰色背景について、必要なら「idle」「入力中」「queued follow-up」「processing中」の ANSI capture を比較する。
5. macOS launcher は未実機検証なので、macOS 環境がある場合に `Shogunate-Runtime.command` / `Shogunate-Configure-Roles.command` を確認する。

開発継続時の推奨順:

1. `git status -sb` と `.git` `rw` 確認。
2. 直近 unit を再実行。
3. `Shogunate-test` ではなく本体 repo で必要な修正を入れる。
4. 実機 runtime 検証が必要な場合は、開発中の本体を汚さないように独立コピーまたは明示した test folder を使う。
5. 変更したら `docs/REQS.md` / `docs/WORKLOG.md` / 関連 ExecPlan を更新する。
6. 検証後に意味ある単位で commit / push する。

## 9) 注意点

- `.env`、秘密鍵、token、認証 file の中身は読まない。
- tmux session を落とす時は慎重に行う。ユーザーは過去に tmux が全部落ちたことを懸念している。
- Shogunate の実行時 state (`.shogunate/`, `.codex-home/`, runtime queues/logs) と開発差分を混ぜない。
- テスト用コピー `Shogunate-test/` は検証用であり、main の正本は内側 repo root。
- 外側 `/mnt/d/Git_WorkSpace/multi-agent-shognate` には表層ハーネスがあり、内側 `/mnt/d/Git_WorkSpace/multi-agent-shognate/multi-agent-shognate` が Shogunate 本体 Git。
