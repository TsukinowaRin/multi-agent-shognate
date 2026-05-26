# Requirements (Normalized)

最終更新: 2026-05-25
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

## 追補（2026-05-25: Shutsujin.bat を本家風の手動 view 起動に戻す）

### 要求

1. `Shutsujin.bat` は `shutsujin_departure.sh` を通常起動し、起動直後から自動で Goza View に attach しない。
2. Windows / WSL から `Shutsujin.bat` を開いた後、ユーザーが同じ端末で `cgo` / `CGO` を入力すると Goza View、`csa` / `CSA` を入力すると足軽 View に切り替えられる状態にする。
3. `Shogunate-Runtime.bat` は従来どおり一発起動で Goza View を自動表示する。
4. 本家由来の `csst` / `css` / `csm` 系の使い勝手を壊さない。特に `csm` は本家どおり multiagent view として扱う。
5. Shogunate 独自の御座の間ショートカットとして `cgo` / `csa` / `csg` / `csk` / `ckr` / `cma` を用意する。
6. `Shutsujin.bat` は数字付きの手順表示や成功時 pause を出さず、選択したら即起動する。

### 制約

1. 既存 tmux session を不用意に kill しない。
2. Windows 側 launcher は WSL Ubuntu 前提のまま扱う。
3. `Runtime.bat` の自動 attach 仕様は変更しない。

### 受け入れ条件（観測可能）

1. `Shutsujin.bat` 実行後、端末は WSL shell に残り、`cgo` / `CGO` / `csa` / `CSA` が入力可能。
2. `cgo` / `CGO` は `bash scripts/goza_no_ma.sh` 相当として Goza View に attach / switch する。
3. `csa` / `CSA` は `bash scripts/goza_no_ma.sh -t ashigaru` 相当として足軽 View に attach / switch する。
4. `css` / `CSS` は将軍、`csm` / `CSM` は multiagent、`csk` / `CSK` または `ckr` / `CKR` は家老に attach / switch する。
5. `Shutsujin.bat` に `[1/3]` / `[2/3]` / `[3/3]` の進行表示が残っていない。
6. `cmd.exe /c Shutsujin.bat --no-attach` または shell syntax check 相当で launcher の基本動作が確認できる。

## 追補（2026-05-26: Shutsujin.bat の Codex TUI 表示安定化）

### 要求

1. `Shutsujin.bat` で起動した Codex の入力欄が黒くなる問題を避ける。
2. `Shutsujin.bat` は Goza に attach してから agent CLI を起動する。
3. 数字メニューは復活させない。
4. 旧来の alias shell workflow は `--no-attach` で残す。

### 受け入れ条件（観測可能）

1. `Shutsujin.sh` は `MAS_WAIT_FOR_GOZA_CLIENT_BEFORE_CLI=1` と `MAS_LAUNCHER_RUN_ID` を使い、`goza-no-ma` 作成後に `tmux attach-session -t goza-no-ma` する。
2. `Shutsujin.bat` は `Shogunate-Runtime.sh` ではなく `Shutsujin.sh` を呼び続ける。
3. `Shutsujin.bat` に数字選択メニューが残っていない。
4. `Shutsujin.sh --no-attach` は起動後に `scripts/shell_aliases.sh` を読む manual fallback を維持する。

## 追補（2026-05-26: Windows debug launcher の clean / resume 分離）

### 要求

1. 通常配布は cURL / package command で起動する前提に寄せる。
2. Windows ローカルデバッグ用に clean start と resume を明示した bat を分ける。
3. debug bat は既存の `Shutsujin.bat` を再利用し、通常 launcher の処理を重複させない。

### 受け入れ条件（観測可能）

1. `Shutsujin-Clean.bat` は `Shutsujin.bat -c` を呼ぶ。
2. `Shutsujin-Resume.bat` は `Shutsujin.bat` をそのまま呼ぶ。
3. どちらも `Shogunate-Runtime.bat` / `Shogunate-Runtime.sh` を経由しない。
