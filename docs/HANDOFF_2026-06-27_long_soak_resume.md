# Handoff: Long Soak Resume

最終更新: 2026-06-27 00:32 JST

## 目的

PC再起動後、MacAir とこのPCの修正後 Shogunate 構成を30分以上soak監視する作業を再開する。

## 最初に読む

1. `docs/REQS.md`
2. `docs/EXECPLAN_2026-06-26_dual_machine_stability_probe.md`
3. `docs/WORKLOG.md` の `2026-06-27 00:27 (JST)` 節

## 再開コマンド

```bash
cd /mnt/d/Git_WorkSpace/multi-agent-shognate/multi-agent-shognate
git status --short
PATH="$HOME/.local/bin:$PATH" shogunate battlefield status dual-probe --json
ssh macair 'PATH="$HOME/.local/bin:/opt/homebrew/bin:/usr/local/bin:$PATH" shogunate battlefield status test --json'
```

## このPCのruntimeが落ちていた場合

再起動後は WSL / tmux session が消えている可能性が高い。その場合は以下で復帰する。

```bash
cd /mnt/d/Git_WorkSpace/multi-agent-shognate/multi-agent-shognate
PATH="$HOME/.local/bin:$PATH" shogunate battlefield start dual-probe --resume --json
PATH="$HOME/.local/bin:$PATH" shogunate battlefield status dual-probe --json
```

## MacAirの確認

MacAir 側はリモートで起動中の可能性がある。落ちていた場合は、MacAir 側で `test` を resume する。

```bash
ssh macair 'PATH="$HOME/.local/bin:/opt/homebrew/bin:/usr/local/bin:$PATH" shogunate battlefield status test --json'
ssh macair 'PATH="$HOME/.local/bin:/opt/homebrew/bin:/usr/local/bin:$PATH" shogunate battlefield start test --resume --json'
```

## soakで見るもの

- 両方の `runtime.status` が `running`
- 両方の role count が `8`
- 両方の全roleが `cli=codex` かつ `current_command=codex`
- daemon window count が `14`
- `sessions.pending_messages` が増え続けない
- inbox unread が溜まり続けない
- queue command が `review` / `done` など説明可能な状態で止まっている

## 既知状態

- このPC / `dual-probe`
  - 再起動前の最終確認: `running`, `8 roles`, `current_command=['codex']`, pending `0`
  - Gunkan report は `failed`。短いprobeで要求した report file が未作成だった既知状態で、runtime停止ではない。
- MacAir / `test`
  - 再起動前の最終確認: `running`, `8 roles`, `current_command=['codex']`, pending `0`
  - Gunkan report は `passed`

## 完了条件

30分以上の同時soakを完走し、結果を `docs/EXECPLAN_2026-06-26_dual_machine_stability_probe.md` と `docs/WORKLOG.md` に追記する。
