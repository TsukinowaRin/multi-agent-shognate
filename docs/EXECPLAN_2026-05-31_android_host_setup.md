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

### USB 鍵ペアリング

1. Android 端末で USB デバッグを許可し、debug / prerelease APK をインストールしておく。
2. `bash android/tools/setup_android_ssh.sh --pair-usb` を実行する。
3. スクリプトが同意 prompt を出し、同意後に Android app の pairing provider から app 内生成 SSH 鍵の公開鍵と app 内秘密鍵 path を取得する。
4. 公開鍵を `~/.ssh/authorized_keys` へ重複なく追加する。秘密鍵は Android app の private storage に残し、PCへ取り出さない。
5. USB reverse と `shogunate://setup` intent を送信し、Android app は `127.0.0.1:2222` と app 内秘密鍵 path を保存する。
6. 古い debug APK で pairing provider が使えない場合だけ、fallback として `.shogunate/android-ssh/` にPC生成鍵を作り、`run-as` で app 専用領域へ転送する。

### 無線 鍵ペアリング

1. Android 端末で USB デバッグを許可する。USB は初回設定を送るためだけに使う。
2. Android とホストを同じ LAN または Tailscale に入れる。
3. `bash android/tools/setup_android_ssh.sh --pair-wireless` を実行する。
4. スクリプトが Android app の pairing provider から公開鍵を取得し、ホストの `authorized_keys` へ登録する。
5. `tailscale ip -4` / LAN / default route から候補 IP を出し、USB 接続中の Android 端末の現在の IPv4 に近い候補を優先して app へ鍵認証つき setup intent として送る。
6. 自動選択を変えたい場合は `bash android/tools/setup_android_ssh.sh --pair-wireless --host <dns-url-or-ip>` または `SHOGUNATE_PAIR_HOST=<dns-url-or-ip> ...` を使う。DNS 名、SSH/HTTPS URL、Tailscale IP、LAN IP を受け付け、URL path / query は無視する。
7. setup URI candidates には app 内秘密鍵 path も含めるため、手動で URI 取込しても鍵認証設定を維持できる。

### 無線

1. Android とホストを同じ LAN または Tailscale に入れる。
2. `bash android/tools/setup_android_ssh.sh --wireless` を実行する。
3. 表示された Tailscale / LAN IP のいずれかを Android app の SSH ホストに入れる。
4. Android app の SSH ポートには、スクリプトが表示した host SSH port を入れる。通常は `22` だが、WSL 側で競合回避用に `2223` などへ変更している場合はその値を使う。
5. スクリプトは候補 IP ごとの完成済み `shogunate://setup` URI を表示する。Android app では URI を貼り付けるだけで host/port/user/project/tmux target を取り込める。
6. `qrencode` が利用可能な環境では、最初の候補 URI をターミナル QR として表示する。無い場合は URI テキスト表示にフォールバックする。

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
- 実機で将軍 / エージェント / 戦況 / 設定タブを開き、スクリーンショットまたは UI dump で主要操作を確認する。
- 設定画面ではワンタッチ接続、接続先入力、USB/無線/接続ボタン、マニュアルモード、通知設定の表示を確認する。

## 結果

- `cd android && ./gradlew testDebugUnitTest assembleDebug`: PASS
- `bash -n android/tools/setup_android_ssh.sh`: PASS
- `bash android/tools/setup_android_ssh.sh --wireless`: PASS。WSL/Linux 環境で Tailscale/LAN/default route 候補を表示。
- `adb install -r android/app/build/outputs/apk/debug/app-debug.apk`: PASS
- `bash android/tools/setup_android_ssh.sh --usb`: PASS。host SSH port を自動検出して `adb reverse tcp:2222 tcp:<detected>` を設定し、`shogunate://setup` intent で app prefs に `127.0.0.1:2222`, `agent:shogun`, `shogunate:goza` を保存。
- 実機設定画面: USB/無線ボタン、保存済み host/port/user、接続結果表示を確認。
- 2026-06-05 時点の WSL 実機では、`/etc/ssh/sshd_config.d/99-shogun-android.conf` により SSH server が `2223` で待受中。USB は Android 側 `127.0.0.1:2222` から host `127.0.0.1:2223` へ reverse するため、Android app 側の USB ポートは `2222` のままでよい。接続には SSH 認証設定が別途必要。
- 2026-06-05 追補: Android app 設定画面に setup URI 貼り付け取り込みを追加し、`--wireless` は候補 IP ごとの完成済み setup URI と optional QR を表示する。
- `SHOGUNATE_QR=0 bash android/tools/setup_android_ssh.sh --wireless`: PASS。`100.71.16.5` と `192.168.1.5` の完成済み setup URI を表示。
- `bash android/tools/setup_android_ssh.sh --pair-usb --yes`: PASS。初期実装では OnePlus LE2121 (`661ecd40`) でPC生成鍵 fallback を使い、公開鍵登録、秘密鍵転送、`adb reverse tcp:2222 tcp:2223`、setup intent、host 側 SSH publickey 認証を確認。
- 2026-06-05 追補: Android app 内で RSA 4096 key を生成し、`content://com.shogun.android.pairing/profile` から公開鍵だけをホストへ渡す方式へ更新。OnePlus LE2121 で provider query、`--pair-usb --yes`、`--pair-wireless --yes` を確認。
- `--pair-usb --yes`: PASS。provider 経由の app 内生成鍵を使い、`ssh_key_path=/data/user/0/com.shogun.android/files/ssh_keys/shogunate_mobile_rsa.pem` を保存。Android app UI dump で `接続中 — 将軍セッション` を確認。
- `--pair-wireless --yes`: PASS。Tailscale 候補 `100.71.16.5`、LAN 候補 `192.168.1.5` を検出し、端末の Wi-Fi IPv4 `192.168.1.7` に近い LAN 側 `192.168.1.5` を自動設定。Android app UI dump で `接続中 — 将軍セッション` を確認。必要なら `SHOGUNATE_PAIR_HOST` で選択を固定できる。
- Android app 設定画面: 通常表示を `ワンタッチ接続` に寄せ、SSH詳細入力は `マニュアルモード` 配下へ移動。
- 2026-06-05 追補: Android app 設定画面に `接続先（DNS / URL / Tailscale IP / LAN IP）` 欄を追加。入力値は SSH 用 host/port に正規化し、URL の path/query/fragment は無視する。
- `bash android/tools/setup_android_ssh.sh --pair-wireless --host 'https://192.168.1.5:2223/shogunate' --yes`: PASS。URL を `192.168.1.5:2223` に正規化し、Android app へ鍵認証つき setup intent を送信。
- 実機 URL setup URI 取り込み: PASS。`shogunate://setup?host=https%3A%2F%2F192.168.1.5%3A2223%2Fremote&port=22...` は Android prefs に `ssh_host=192.168.1.5`, `ssh_port=2223` を保存し、UI dump で `接続中 — 将軍セッション` を確認。
- 2026-06-05 追補: OnePlus LE2121 で4タブ、接続先入力、接続設定リンク取込、マニュアルモード、主要アクションを実機操作。Shogunate runtime 未起動時もSSH接続だけ成立する状態で、将軍 pane 未検出とエージェント view 未検出の表示を確認。
- 2026-06-09 追補: 設定画面の通常導線を `接続先`、`USB`、`無線`、`接続` に整理し、`接続設定リンク`、`設定取込`、`接続診断`、`接続先を反映`、`標準に戻す` を通常画面から削除。入力中の接続先は常時 host/port 正規化し、`接続` 押下で保存と SSH 接続試行を行う。
- 実機UI修正: 将軍タブは target 未検出時に `SSH接続中 — pane未検出` と折り返しエラーを表示。エージェントタブは空白ではなく `エージェント未表示` カードと `再読込` を表示。戦況タブの表はスマホ幅で折り返す。使用量チェックは取得不可時の説明表示へフォールバックする。
- 実機操作: BGM ボタンのラベル更新、音声入力の録音権限ダイアログ、使用量ダイアログ、マニュアルモード開閉、SSH詳細表示を確認。送信操作は runtime pane 未起動のため実ジョブ送信までは行わず、UIが壊れない範囲で確認。

## 復旧

Android app 側で明示的に `shogunate:goza` を将軍 target に戻せば、従来通り御座の間全体を将軍タブに表示できる。USB reverse は `adb reverse --remove tcp:2222` で解除できる。
