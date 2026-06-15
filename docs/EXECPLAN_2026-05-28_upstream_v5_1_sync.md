# ExecPlan: upstream/main v5.1.0 sync

## Purpose

最新の本家 `upstream/main` (`v5.1.0`, traffic-control roles) を Shogunate 作業ブランチへ取り込み、Shogunate 独自 runtime / CLI / 軍監拡張を残したまま更新する。

## Constraints

- 既存の未コミット変更を巻き戻さない。
- `main` / `master` へ直接 push しない。
- 本家側で削除されている Shogunate 専用ファイルは、実運用に必要なら保持する。
- 既存 tmux session は不用意に kill しない。

## Plan

1. `upstream/main` を fetch し、差分範囲と削除候補を確認する。
2. 現在の未コミット変更を安全な checkpoint commit にまとめる。
3. `upstream/main` を merge し、conflict を解消する。
4. Shogunate 独自ファイルの消失がないか確認する。
5. instruction を再生成し、関連テストを実行する。
6. docs/WORKLOG に結果と残リスクを記録する。

## Progress

- [x] `upstream/main` を fetch。最新は `bb19915 release: v5.1.0 traffic-control roles`。
- [x] `HEAD..upstream/main` の name-status / stat を確認。本家側では Shogunate launcher/runtime/package 系の削除が多い。
- [x] checkpoint commit `d073788` を作成。
- [x] `upstream/main` を merge。conflict は `instructions/roles/karo_role.md`, `instructions/roles/gunshi_role.md`, generated instruction, OpenCode agent 定義。
- [x] Shogunate 側の role を土台に、本家 v5.1.0 の traffic-control / QC routing を統合。
- [x] `bash scripts/build_instructions.sh` で生成物を再生成。
- [x] 検証を実行。

## Verification

- `bash scripts/build_instructions.sh` -> PASS
- `bash -n shutsujin_departure.sh Shutsujin.sh Shogunate-Runtime.sh scripts/goza_no_ma.sh scripts/focus_agent_pane.sh scripts/watcher_supervisor.sh scripts/inbox_watcher.sh scripts/inbox_write.sh scripts/shell_aliases.sh scripts/install_shell_aliases.sh scripts/codd_check.sh` -> PASS
- `python3 -m py_compile scripts/configure_runtime_roles.py scripts/gunkan_light_watch.py scripts/gunkan_codd_audit.py scripts/gunkan_event_log.py scripts/sync_runtime_cli_preferences.py scripts/shogun_to_karo_bridge.py scripts/karo_done_to_shogun_bridge.py scripts/runtime_blocker_notice.py` -> PASS
- `bats tests/unit/test_build_system.bats tests/unit/test_mux_parity.bats tests/unit/test_watcher_supervisor.bats tests/unit/test_gunkan_audit.bats` -> PASS (`148` tests)
- `bats tests/unit/test_cli_adapter.bats tests/unit/test_dynamic_model_routing.bats tests/unit/test_send_wakeup.bats` -> PASS (`331` tests)
- `git diff --check` -> PASS

## Result

`upstream/main` (`bb19915`, `v5.1.0`) を取り込み済み。Shogunate runtime/launcher/軍監/CoDDオンデマンド監査/追加CLI対応は保持した。

## Recovery

checkpoint commit 作成後に merge するため、問題があれば merge commit 前なら `git merge --abort`、merge 後なら新しい修正 commit で戻す。`git reset --hard` は使わない。
