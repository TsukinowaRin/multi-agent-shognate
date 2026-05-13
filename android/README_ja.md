# Shogun Android コンパニオン

[multi-agent-shogun](https://github.com/yohey-w/multi-agent-shogun) のコンパニオンアプリ — スマホからAIエージェント軍団を監視・操作。

このフォークでは、元の UI/UX を維持しつつ、このリポジトリ向けの tmux / Android 接続導線だけを調整しています。

<p align="center">
  <img src="screenshots/01_shogun_terminal.png" alt="将軍ターミナル" width="230">
  <img src="screenshots/02_agents_grid.png" alt="エージェント一覧" width="230">
  <img src="screenshots/03_dashboard.png" alt="ダッシュボード" width="230">
</p>

## 機能

### 4タブ構成

| タブ | 機能 |
|------|------|
| **将軍** | 将軍を既定送信先にした遠隔司令ターミナル。送信先チップで家老・軍師・足軽へ切替。テキスト/音声でコマンド送信。ANSI256色対応、特殊キーバー（Enter, C-c, C-b, 矢印, Tab, ESC等） |
| **エージェント** | 9ペイン一覧表示（家老 + 足軽7 + 軍師）。タップで全画面展開。個別エージェントへのコマンド送信 |
| **ダッシュボード** | `dashboard.md` をHTML描画。表のテキスト選択・コピー対応 |
| **設定** | SSH接続設定（ホスト、ポート、ユーザー、鍵/パスワード）、プロジェクトパス、tmuxセッション名 |

### 主要機能

- **音声入力** — 日本語音声認識（連続リスニングモード）。ハンズフリーでコマンド入力
- **任意エージェント送信** — 将軍タブから `@agent_id` ベースで将軍・家老・軍師・足軽へ送信先を切替
- **接続プロファイル取込** — host 側 script が出力する Tailscale / USB 用リンクまたは JSON を設定画面から反映
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

このリポジトリの **GitHub Releases** から `multi-agent-shognate-android-*.apk` をダウンロードしてサイドロード。

またはソースからビルド:

```bash
./gradlew assembleDebug
# APK: app/build/outputs/apk/debug/app-debug.apk
# Release APK: app/build/outputs/apk/release/app-release.apk
```

このフォークでは upstream の `multi-agent-shogun.apk` ではなく、fork 版 APK を正規配布物として扱う。

## セットアップ

1. アプリを起動 → **設定** タブ
2. **かんたん接続** で `Tailscale` または `USB` を選ぶ
3. SSH ユーザー名、パスワード、プロジェクトパスを入れる
4. **保存** → **将軍** タブに切替 → 自動接続

### 接続プロファイルでのセットアップ

host 側で次のどちらかを実行すると、Android 設定を自動投入できる `shogunate://connect?...` リンクと JSON が出力されます。`qrencode` が入っていれば QR も出ます。パスワード・秘密鍵・token は含まれません。

```bash
# Tailscale 経由
scripts/android_pairing_profile.sh --mode tailscale --ssh-port 22

# USB 経由（adb reverse を作成。端末側は host=127.0.0.1, port=2222）
scripts/android_pairing_profile.sh --mode usb --ssh-port 22 --android-port 2222
```

QR が出たらスマホのカメラで読みます。QR が使えない場合は、表示された host / port / user / projectPath を設定画面へ手入力します。クリップボード共有は必須ではありません。

### 入力例

- **SSHホスト**: Tailscale なら `100.x.x.x`、USB なら `127.0.0.1`
- **SSHポート**: Tailscale なら通常 `22`、USB なら `2222`
- **将軍セッション名**: `shogun`
- **エージェントセッション名**: `multiagent`
- **プロジェクトパス**: `/path/to/multi-agent-shognate`

接続系の初期値は空欄です。個人情報や環境依存の値はプリセットしません。

### 認証の挙動

- **鍵パスが空欄**なら、`password` / `keyboard-interactive` で接続します。
- **鍵パスが入っている**場合は、まず鍵認証を試します。
- このフォーク版では、鍵認証に失敗してもパスワードが入っていれば自動でパスワード認証に再試行します。

### 前提条件

- ホストマシンでSSHサーバーが稼働中
- `shutsujin_departure.sh` でtmuxセッション起動済み
- スマホからサーバーへ SSH 到達できるネットワーク経路

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
                                            │  android_agent_bridge.sh │
                                            │  @agent_id resolve       │
                                            │  capture-pane/send-keys  │
                                            └──────────────┘
```

## ライセンス

MIT — 親プロジェクトと同じ。
