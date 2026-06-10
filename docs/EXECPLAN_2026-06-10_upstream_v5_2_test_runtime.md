# ExecPlan: 本家 v5.2.0 反映と Shogunate-test 再起動

## 目的

本家 `upstream/main` の最新変更を Shogunate に取り込み、開発用 runtime を停止したまま、テスト用 `Shogunate-test` へ同期して clean start できる状態にする。

## 制約

- 開発用リポジトリで runtime を動かし続けない。
- Shogunate 独自の軍監、Android app、launcher、role 設定 CUI、tmux view alias は消さない。
- `.git`、認証情報、CLI home、端末固有の runtime state は test 同期でコピーしない。
- 破壊的な `git reset --hard` / `git clean -fd` は使わない。

## 現状

- `upstream/main` は `v5.2.0` を含む最新まで fetch 済み。
- 開発 branch は `codex/upstream-main-rebuild-shogunate`。
- 作業前差分は `.shogunate/backups/upstream-v5.2-sync-20260610_222006/` に保存済み。
- 開発側の `shogunate` / `goza-runtime` tmux session は停止済み。

## 手順

1. 現在の未コミット差分を保全し、merge 前の復旧点を作る。
2. 本家 `upstream/main` の変更を取り込み、衝突時は Shogunate 独自拡張を残して解決する。
3. instruction / watcher / CLI adapter / launcher まわりを確認し、必要な生成や構文チェックを行う。
4. `Shogunate-test` に rsync で同期する。`.git`、認証情報、build cache、runtime logs は除外する。
5. `Shogunate-test` で clean start し、tmux session / pane / agent 起動ログを確認する。

## 検証

- `bash -n` 対象 shell script。
- `python3 -m py_compile` 対象 Python script。
- `bash scripts/build_instructions.sh`。
- 可能なら Bats の関連 subset。
- `Shogunate-test` clean start smoke。

## 復旧

- merge 前の差分は `.shogunate/backups/upstream-v5.2-sync-20260610_222006/tracked.diff` から戻せる。
- test 同期は `.git` を除外するため、test repo の履歴は変更しない。
