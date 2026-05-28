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
- [ ] checkpoint commit を作成。
- [ ] merge conflict を解消。
- [ ] 検証を実行。

## Recovery

checkpoint commit 作成後に merge するため、問題があれば merge commit 前なら `git merge --abort`、merge 後なら新しい修正 commit で戻す。`git reset --hard` は使わない。
