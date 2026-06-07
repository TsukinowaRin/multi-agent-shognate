# Shogun Android コンパニオン

[multi-agent-shogun](https://github.com/yohey-w/multi-agent-shogun) のコンパニオンアプリ — スマホからAIエージェント軍団を監視・操作。

<p align="center">
  <img src="screenshots/01_shogun_terminal.png" alt="将軍ターミナル" width="230">
  <img src="screenshots/02_agents_grid.png" alt="エージェント一覧" width="230">
  <img src="screenshots/03_dashboard.png" alt="ダッシュボード" width="230">
</p>

## 機能

### 4タブ構成

| タブ | 機能 |
|------|------|
| **将軍** | 将軍ペインへのSSHターミナル。テキスト/音声でコマンド送信。ANSI256色対応、特殊キーバー（Enter, C-c, C-b, 矢印, Tab, ESC等） |
| **エージェント** | 9ペイン一覧表示（家老 + 足軽7 + 軍師）。タップで全画面展開。個別エージェントへのコマンド送信 |
| **ダッシュボード** | `dashboard.md` をHTML描画。表のテキスト選択・コピー対応 |
| **設定** | USB/Tailscale/LAN のワンタッチ接続設定。従来の SSH 詳細入力はマニュアルモードに格納 |

### 主要機能

- **音声入力** — 日本語音声認識（連続リスニングモード）。ハンズフリーでコマンド入力
- **BGM** — 戦国テーマBGM 3曲内蔵（shogun / shogun-reiwa / shogun-ashigirls）。タップで曲切替。音声入力中は自動ダッキング
- **レートリミットモニター** — エージェントタブのFABボタンからClaude Max使用量を確認（5h/7dウィンドウ、Sonnet/Opus内訳、セッション/メッセージ数）
- **スクリーンショット共有** — 他アプリの共有メニューからShogunへ直接送信。SFTP転送
- **ANSI カラー対応** — 256色ANSIエスケープコード解析によるターミナル出力描画
- **特殊キーバー** — Enter, C-c, C-b, 矢印, Tab, ESC, C-o, C-d へのクイックアクセス
- **自動リフレッシュ** — 将軍ペイン（3秒）、エージェント一覧（5秒）。SSH一括取得で効率化
- **テキスト選択** — 全画面で長押しによるテキスト選択・コピー対応

<p align="center">
  <img src="screenshots/04_settings.png" alt="設定" width="230">
  <img src="screenshots/05_ratelimit.png" alt="レートリミット" width="230">
</p>

## 技術スタック

- **言語**: Kotlin
- **UI**: Jetpack Compose + Material 3
- **SSH**: JSch (mwiede fork) 0.2.21
- **Markdown→HTML**: commonmark-java (GFM tables) → WebView
- **音声**: Android SpeechRecognizer API (ja-JP)
- **Min SDK**: 26 (Android 8.0) / Target: 34

## インストール

[`release/multi-agent-shogun.apk`](release/multi-agent-shogun.apk) からビルド済みAPKをダウンロードしてサイドロード。

またはソースからビルド:

```bash
./gradlew assembleDebug
# APK: app/build/outputs/apk/debug/app-debug.apk
```

## バージョン

Android APK は Shogunate 本体のリリースバージョンに fork/app 側の改訂番号を足します。例: Shogunate `5.1.0` に対する Android 側の最初の改訂は `5.1.0.1` です。

## セットアップ

1. アプリを起動 → **設定** タブ
2. ホスト側で以下のどれかを実行:
   - 初回USBワンタッチ: `bash android/tools/setup_android_ssh.sh --pair` または `--pair-usb`
   - 初回無線ワンタッチ: `bash android/tools/setup_android_ssh.sh --pair-wireless`
   - 接続先を指定して無線ワンタッチ: `bash android/tools/setup_android_ssh.sh --pair-wireless --host <DNSまたはURLまたはIP>`
   - USB手動値送信: `bash android/tools/setup_android_ssh.sh --usb`
   - 無線候補表示: `bash android/tools/setup_android_ssh.sh --wireless`
   - Windows/WSL: `android/tools/setup_android_ssh.bat` をダブルクリック、または WSL から `.sh` を実行
3. ワンタッチ接続では、Android app が app 内に専用 SSH 鍵を生成し、PC 側スクリプトは公開鍵だけを取得して `authorized_keys` に登録します。秘密鍵はスマホの app private storage から出しません。
4. `--pair-usb` は `adb reverse` を設定し、Android app を `127.0.0.1:2222` に自動設定します。`--pair-wireless` は初回設定だけ USB デバッグを使い、以後は Tailscale / LAN へ直接 SSH 接続します。無線候補はスマホの現在の IPv4 に近いものを優先します。接続先を固定したい場合は `--host <DNSまたはURLまたはIP>` または `SHOGUNATE_PAIR_HOST=<DNSまたはURLまたはIP>` を付けます。
5. 接続設定リンク（`shogunate://setup...`）がある場合は設定画面の **貼付** → **設定取込** で host/port/user/project/tmux target/key path を取り込めます。
6. リモート接続先を手入力する場合は、通常画面の **接続先** に DNS 名、URL、Tailscale IP、LAN IP のいずれかを入力し、**接続先を反映** または **接続診断** を押します。URL の path/query は無視され、host と port だけが SSH 接続に使われます。
7. 手動で細かく設定したい場合だけ **マニュアルモード** を開きます:
   - **ホスト**: USB は `127.0.0.1`、無線は Tailscale / LAN IP
   - **ポート**: USB は `2222`、無線は `setup_android_ssh.sh --wireless` が表示した SSH ポート（通常は `22`、WSL で変更している場合は `2223` など）
   - **ユーザー**: SSHユーザー名
   - **鍵パス** または **パスワード**: 認証方式
   - **プロジェクトパス**: サーバー側のmulti-agent-shogunパス（例: `/mnt/c/tools/multi-agent-shogun`）
   - **将軍 target**: 標準は `agent:shogun`。`@agent_id=shogun` の pane を自動検出します。
   - **エージェント target**: 標準は `shogunate:goza`
8. **接続診断** を押すと、設定保存後に SSH、`tmux`、project path、将軍 target、エージェント target、`dashboard.md` を確認できます。
9. 診断が通ったら **将軍** タブに切替 → 将軍 pane のみに自動接続

### 前提条件

- ホストマシンでSSHサーバーが稼働中
- `shutsujin_departure.sh` でtmuxセッション起動済み
- スマホとサーバー間の接続（USBデバッグ + `adb reverse`、LAN、Tailscale等）
- USB 接続を使う場合は `adb`
- ワンタッチ鍵ペアリングは release APK でも使える app 内鍵生成 provider を優先します。古い debug APK で provider がない場合だけ `run-as` fallback を使います。

## アーキテクチャ

```
Android App
    │
    ├── ShogunScreen ──── ShogunViewModel ──┐
    ├── AgentsScreen ──── AgentsViewModel ──┤── SshManager (singleton)
    ├── DashboardScreen ─ DashboardViewModel┤      │
    └── SettingsScreen                      │   JSch SSH
                                            │      │
                                            └──────┤
                                                   ▼
                                            tmux (WSL2/Linux)
                                                   │
                                            ┌──────┴──────┐
                                            │  capture-pane │ (read)
                                            │  send-keys    │ (write)
                                            └──────────────┘
```

## ライセンス

MIT — 親プロジェクトと同じ。
