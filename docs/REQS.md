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

## 追補（2026-05-22: upstream AGY PR / local model smoke）

### 要求

1. 本家 `yohey-w/multi-agent-shogun` に対して、Shogunate 全体ではなく AGY / Antigravity CLI 対応だけを最小単位で PR できるか検証し、可能なら PR を作成する。
2. 本家向け PR は、本家構造を保ったまま `antigravity` / legacy `gemini` alias / `agy --dangerously-skip-permissions` / role instruction generation / basic runtime ready handling を追加する程度に抑える。
3. Shogunate 側では LocalAPI / LM Studio / Ollama の OpenAI-compatible endpoint 接続を確認する。
4. ROCm 環境で可能なら Ollama の `qwen3.6:27b` 等を一時的にロードし、LocalAPI wrapper から実応答を確認する。

### 制約

1. 本家向け PR ブランチは `upstream/main` から分岐し、Shogunate の package distribution / multi-Karo / runtime hardening などを混ぜない。
2. `main` / `master` へ直接 push しない。
3. secrets、token、API key、OAuth token の内容は読まない・出力しない。
4. Ollama / LM Studio / ROCm の導入や大容量モデル download が必要な場合は、既存環境を破壊しない範囲で行い、できない場合は理由を記録する。
5. 27B model は容量が大きいため、インストール済み runtime / server が無い場合は mock OpenAI-compatible server と endpoint availability check を先に行う。

### 受け入れ条件（観測可能）

1. `upstream/main` ベースの AGY-only branch が作成され、差分に AGY 以外の Shogunate 独自機能が混入していない。
2. AGY branch で `bash -n` と関連 Bats が PASS する。
3. AGY CLI が存在する環境では、少なくとも command construction / availability check が PASS する。
4. LocalAPI wrapper は mock OpenAI-compatible endpoint で chat completion を取得できる。
5. Ollama / LM Studio endpoint が起動していない場合は、その事実と必要手順を明記する。
6. 実機 local model test が通る場合のみ、本家 AGY PR を作成する。local model test が環境不足で止まる場合は、AGY PR を draft として作るか保留理由を明記する。
