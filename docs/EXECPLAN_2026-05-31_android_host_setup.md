# ExecPlan: Android app USB/無線 SSH セットアップ

作成日: 2026-05-31

## 目的

Android app からホストPC上の Shogunate へ、USB または無線で迷わず SSH 接続できる状態にする。アプリの将軍タブは既定で御座の間全体ではなく、将軍 pane のみを表示する。

## 対象 OS

- Windows: WSL から `android/tools/setup_android_ssh.sh` を実行する。ダブルクリック用に `android/tools/setup_android_ssh.bat` も用意する。
- macOS: Apple Terminal で `bash android/tools/setup_android_ssh.sh` を実行する。無線候補 IP は `tailscale ip -4`、`ipconfig getifaddr`、`ifconfig` から出す。
- Linux: Terminal で `bash android/tools/setup_android_ssh.sh` を実行する。無線候補 IP は `tailscale ip -4`、`hostname -I`、`ip route` から出す。

## 接続方式

### USB

1. Android 端末で USB デバッグを許可する。
2. ホストで SSH server を起動しておく。
3. `bash android/tools/setup_android_ssh.sh --usb` を実行する。
4. スクリプトが host SSH port を自動検出し、`adb reverse tcp:2222 tcp:<detected>` を設定する。
5. APK がインストール済みなら、スクリプトが `shogunate://setup` intent を送り、Android app に `SSHホスト=127.0.0.1`, `SSHポート=2222` などを保存する。
6. 自動送信できない場合は、Android app で同じ値を手入力する。

### 無線

1. Android とホストを同じ LAN または Tailscale に入れる。
2. `bash android/tools/setup_android_ssh.sh --wireless` を実行する。
3. 表示された Tailscale / LAN IP のいずれかを Android app の SSH ホストに入れる。
4. Android app の SSH ポートには、スクリプトが表示した host SSH port を入れる。通常は `22` だが、WSL 側で競合回避用に `2223` などへ変更している場合はその値を使う。
5. スクリプトは `shogunate://setup` URI も表示する。将来 QR 化する場合はこの URI をそのまま使える。

## tmux target

- 将軍タブ既定: `agent:shogun`
- `agent:shogun` は tmux target 文字列ではなく、`tmux list-panes -a -F '#{pane_id} #{@agent_id}'` から `@agent_id=shogun` の pane を探す仮想 target。
- エージェント一覧既定: `shogunate:goza`
- 明示 target の `shogunate:goza`、`shogun:main`、旧 session 名だけの `shogun` / `multiagent` は互換維持する。

## 検証

- `cd android && ./gradlew testDebugUnitTest assembleDebug`
- `bash -n android/tools/setup_android_ssh.sh`
- `bash android/tools/setup_android_ssh.sh --wireless`
- `git diff --check`
- 可能なら adb 実機 install / launch で設定画面を確認する。

## 結果

- `cd android && ./gradlew testDebugUnitTest assembleDebug`: PASS
- `bash -n android/tools/setup_android_ssh.sh`: PASS
- `bash android/tools/setup_android_ssh.sh --wireless`: PASS。WSL/Linux 環境で Tailscale/LAN/default route 候補を表示。
- `adb install -r android/app/build/outputs/apk/debug/app-debug.apk`: PASS
- `bash android/tools/setup_android_ssh.sh --usb`: PASS。host SSH port を自動検出して `adb reverse tcp:2222 tcp:<detected>` を設定し、`shogunate://setup` intent で app prefs に `127.0.0.1:2222`, `agent:shogun`, `shogunate:goza` を保存。
- 実機設定画面: USB/無線ボタン、保存済み host/port/user、接続診断表示を確認。
- 2026-06-05 時点の WSL 実機では、`/etc/ssh/sshd_config.d/99-shogun-android.conf` により SSH server が `2223` で待受中。USB は Android 側 `127.0.0.1:2222` から host `127.0.0.1:2223` へ reverse するため、Android app 側の USB ポートは `2222` のままでよい。接続診断には SSH 認証設定が別途必要。

## 復旧

Android app 側で明示的に `shogunate:goza` を将軍 target に戻せば、従来通り御座の間全体を将軍タブに表示できる。USB reverse は `adb reverse --remove tcp:2222` で解除できる。
