# Requirements (Normalized)

最終更新: 2026-05-22
出典: ユーザー要求「最新の本家リポジトリをベースに Shogunate 独自機能を実装し直す」

## 追補（2026-05-22: upstream latest base rebuild）

### 要求

1. 最新の本家 `yohey-w/multi-agent-shogun` を取得し、その `upstream/main` をベースにした新しい作業ブランチで Shogunate を再構築する。
2. 既存 Shogunate 独自機能は、可能な限り本家構造に合わせて再実装し、単なる過去差分の無差別コピーにしない。
3. 機能を後で本家へ PR しやすいように、独立性の高い単位へ整理する。
4. AGY 対応だけでなく、package distribution、CLI state isolation、runtime launcher、multi-Karo topology、cross-platform watcher など現行 Shogunate の必要機能を維持する。
5. 実機または実 runtime に近い環境で、Shogunate runtime が起動し、少なくとも Codex / OpenCode / Antigravity の代表構成で破綻しないことを確認する。
6. 完了時に、何を本家ベースから変更したか、何を最適化したか、どの機能が本家 PR 候補かを説明する。

### 制約

1. `main` / `master` へ直接 push しない。
2. secrets、認証 token、秘密鍵の内容は読まない・出力しない。
3. 既存の `codex/upstream-v4.6.0-sync` は参照元として保持し、破壊しない。
4. 大きな移植は機能群ごとに検証し、失敗時に戻せる単位で commit する。
5. 本家に既に入っている OpenCode support は尊重し、Shogunate 側の上書きで退行させない。

### 受け入れ条件（観測可能）

1. コマンド: `git log -1 --oneline upstream/main`
   - 期待結果: 作業開始時点の upstream base commit が確認できる。
2. コマンド: `git merge-base --is-ancestor upstream/main HEAD`
   - 期待結果: 新しい Shogunate 作業ブランチが最新 upstream を祖先に持つ。
3. コマンド: `bash -n` 対象 shell scripts。
   - 期待結果: runtime / CLI adapter / launcher / watcher / update scripts に syntax error がない。
4. コマンド: 関連 Bats / Python tests。
   - 期待結果: 移植した機能群の回帰テストが PASS する。
5. 実機確認: test folder または隔離 runtime で `Shogunate-Runtime.sh` を起動。
   - 期待結果: tmux runtime が起動し、代表 agent に初動命令を配信できる。
6. コマンド: `git diff --check`
   - 期待結果: whitespace error がない。

### 今回の初期再構築では外すもの

- CoDD gate は統合しない。runtime / CLI / package が安定した後に必要性を再評価する。
- Android app / APK 対応は統合しない。Android remote control は後段の独立 PR 候補として扱う。
