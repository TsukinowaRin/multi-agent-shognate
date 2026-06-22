# ExecPlan: Shogunate App

最終更新: 2026-06-22

## 目的

現行Androidアプリを、Windows / Linux / macOS / Android で使える `Shogunate App` 構想へ発展させる。Codex App のようなチャット・実行状況・成果物確認体験を、Shogunate の role / agent abstraction を通じて任意の対応AI CLIで使えるようにする。

## 前提

- Shogunate runtime は `cd <project> && shogunate` の project runtime を正とする。
- 現行Android app は SSH / Pair / tmux / dashboard.md を直接操作している。
- 初期フェーズでは、既存Android導線を壊さず、共通化できる境界を決める。
- secrets、SSH秘密鍵、token の内容は読まない・出力しない。

## 現行Androidの主要機能

- `shogunate pair` との初回 pairing。
- app 内 SSH key 生成、公開鍵だけをPCへ登録。
- SSH 接続と tmux command 実行。
- `agent:shogun` 仮想 target と agent pane 検出。
- 将軍タブから tmux pane へ入力送信。
- dashboard.md の WebView 表示。
- agents view、rate limit check、接続診断、target project 表示。
- ntfy 通知設定、foreground SSH service、自動再接続。

## 現行Androidの構造メモ

- UI: Kotlin / Jetpack Compose / Material3。
- SSH: `SshManager.kt` が JSch で接続し、各 ViewModel が remote command を実行。
- Pair: `WirelessPairingClient.kt` が `shogunate pair` の `/pair` へHTTP request。
- Dashboard: `DashboardViewModel` / `DashboardScreen` が `dashboard.md` を読み、WebView/Markdown描画。
- Shogun操作: `ShogunViewModel` が tmux capture/send-keys を直接実行。
- Settings: `SettingsViewModel` が Pair 後の host/user/key/project/targets を保存し、tmux target と dashboard を診断。

### 現行構造の限界

- UI が tmux command 文字列を直接知っているため、desktop/mobile で重複しやすい。
- agent状態、command状態、成果物一覧、dashboard の取得方法が SSH command に散っている。
- Codex/OpenCode/Claude/Agy 等の違いを app 側が直接理解し始めると破綻しやすい。
- desktop と Android を別々に増やすと、Pair/connection/profile/session model が分裂する。

## 初期アーキテクチャ案

### 方針

- desktop は Web UI + local companion backend を第一候補にする。
- Android は既存Kotlin/Composeを短期維持し、共通APIへ段階移行する。
- runtime 側に `Shogunate App API` を追加し、UI は tmux 直接操作ではなく API 経由へ寄せる。
- transport は段階的に `SSH command` 互換を残しつつ、将来 `shogunate app-server` で HTTP/WebSocket を提供する。
- App は「AI CLIを選ぶ」のではなく、「Shogunateのproject/session/role/agentへ指示を出す」UIにする。

### レイヤ

1. Runtime API
   - session一覧、agent一覧、agent状態、dashboard、inbox write、command submit、artifacts一覧、logs tail。
   - role abstraction: `shogun`, `karo`, `gunkan`, `gunshi`, `ashigaruN`。
   - CLI abstraction: runtime metadata の `agent_cli.tsv` を表示するが、操作APIはCLI非依存。
2. Transport
   - desktop local: localhost HTTP/WebSocket。
   - Android remote: Pair 後の SSH tunnel または Tailscale/LAN HTTPS/HTTP。
   - 互換: 現行SSH/tmux command。
3. UI Shell
   - desktop: Windows / Linux / macOS 共通。
   - mobile: Android。
4. Shared App Model
   - connection profile、project runtime、agent target、message stream、artifact references。

## 推奨する実装段階

### Phase 1: API境界を作る

- `shogunate app-server` を追加し、現行Androidが必要な操作をHTTP/JSONで提供する。
- 最初はローカルhost/SSH tunnel前提でよい。
- Androidは既存SSH/tmux実装を残しつつ、API clientを追加して段階移行する。

### Phase 2: Desktop App

- Windows / Linux / macOS は同じUIコードを使う。
- 第一候補は Tauri + Web UI。理由は軽量、desktop配布しやすい、local companion/backendと相性がよい。
- Electron は実装速度は高いが配布サイズが重い。Flutter はAndroid共通化には強いが、既存Android/SSH/tmuxコード移行コストが高い。

### Phase 3: Android新UI

- 既存Kotlin/Composeをそのまま育てるか、desktop UIと揃えるかをユーザー判断にする。
- Androidは background service / key storage / USB/Tailscale pairing が重要なので、完全共通UIより native 維持が安全。

### Phase 4: Codex App風の機能

- Project selector。
- Agent selector / role tabs。
- Chat composer。
- Runtime timeline。
- Dashboard / artifacts / logs。
- Human approval queue。
- Pairing / connection profiles。
- Agent status and busy/blocker notices。

## 検証計画

1. 現行Android app の unit/build check。
2. Pair server unit tests。
3. package check で Android source sync / package contract を確認。
4. 必要な小修正後、結果と未確認範囲を記録。

## 進捗

- [x] 現行Android app の主要機能を棚卸し。
- [x] Windows / Linux / macOS / Android 対応の初期アーキテクチャを整理。
- [x] 現行Android app の unit/build check を実行。
- [x] Pair server unit tests を実行。
- [x] Android package contract tests を実行。

## 検証結果

- PASS: `make android-check`
  - `testDebugUnitTest`
  - `assembleDebug`
- PASS: `PYTHONDONTWRITEBYTECODE=1 python3 -m unittest tests.unit.test_shogunate_pair_server`
- PASS: Android関連 package contract:
  - `test_android_rate_limit_check_prefers_mod_canonical_status_script`
  - `test_android_readmes_use_mod_runtime_entrypoint`
  - `test_package_archive_excludes_android_app`
  - `test_android_source_has_mod_canonical_copy`

## 今回の修正

- 実装コードの修正は不要。現行Androidの build/unit と Pair/packaging contract は通った。
- docs に Shogunate App 構想、現行Androidの構造、推奨段階を追加。

## 設計上の未決事項

- desktop 技術選定: Tauri / Electron / Flutter / Kotlin Multiplatform。
- Android を同一UIコードベースへ寄せるか、既存Kotlin/Composeを継続するか。
- App から直接 tmux を触るか、runtime API を必須化するか。
- ローカル専用から始めるか、Tailscale/LAN 複数PC管理まで初期版に入れるか。
