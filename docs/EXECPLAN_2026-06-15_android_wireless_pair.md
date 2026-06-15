# ExecPlan: Android 初回 Shogunate Pair

## 目的

Android app で USB/Tailscale/LAN 接続先を入力して接続を押した時、PC 側で `shogunate pair` を起動していれば、SSH 鍵登録、接続設定保存、Shogunate runtime 起動、以後の鍵認証接続まで完了できるようにする。

## 進捗

- [x] 要求を `docs/REQS.md` に正規化。
- [x] PC 側 pairing server を追加。
- [x] `shogunate pair` command を package shim / npm wrapper に追加。
- [x] Android app の接続失敗時 pairing flow を追加。
- [x] USB setup を Shogunate Pair flow へ統一。
- [ ] README / Android docs を同期。
- [ ] 検証。

## 方針

- PC 側は Python 標準ライブラリだけで HTTP pairing server を実装する。
- 既定 pairing port は `8765`。`SHOGUNATE_PAIR_PORT` または `--port` で変更可能にする。
- Android app は既存 `AndroidSshKeyManager.ensurePairingProfile()` で app 内秘密鍵と公開鍵を用意する。
- Android app は `http://<host>:8765/pair` に `public_key`, `key_path`, `device_label` を POST する。
- PC 側は端末名、接続元、接続先、公開鍵 fingerprint を terminal に表示し、Pair Password prompt に入力された時だけ `~/.ssh/authorized_keys` に追記する。
- response は `shogunate://setup` と同じ設定要素を JSON で返す。
- `shogunate pair` は USB reverse を自動試行しながら Tailscale/LAN でも待ち受ける。USB request には Android 側 SSH port `2222`、無線 request には PC 側 SSH port を返す。
- `shogunate pair --usb` は廃止し、package command は `shogunate pair` に統一する。source checkout helper の `--pair-usb` は互換 alias として統合 Pair を起動する。
- pairing 承認後、PC 側は best-effort で `Shogunate-Runtime.sh --resume --no-attach` を起動する。
- SSH password は扱わない。秘密鍵本文も PC 側へ送らない。

## 実装手順

1. `scripts/shogunate_pair_server.py` を追加する。
2. `scripts/shogunate_package_bootstrap.sh` の生成 shim に `shogunate pair` を追加する。
3. `bin/shogunate.js` に npm wrapper の `pair` command を追加する。
4. Android に `PairingClient` を追加し、`SettingsViewModel.testConnection()` の SSH 失敗時に pairing を試す。
5. `SettingsScreen` の接続状態 message に pairing 中の案内を出す。
6. `android/tools/setup_android_ssh.sh --pair-usb/--pair-wireless` を `shogunate pair` flow に寄せる。
7. `shogunate pair` を USB/無線両待受にし、`shogunate pair --usb` を廃止し、承認操作を code から Password prompt に変更する。
8. README / README_ja / android README を更新する。
9. unit/smoke/build を実行する。

## 検証

- `python3 -m unittest tests.unit.test_shogunate_pair_server`
- `bash -n scripts/shogunate_package_bootstrap.sh android/tools/setup_android_ssh.sh`
- `python3 -m unittest tests.unit.test_package_distribution`
- `cd android && ./gradlew --no-daemon testDebugUnitTest assembleDebug`
- `git diff --check`

## 復旧

- pairing で追加された公開鍵は `~/.ssh/authorized_keys` の通常行として残る。削除が必要な場合は fingerprint/comment を見て手動削除する。
- pairing server は `Ctrl-C` で停止する。daemon 化は今回の初期実装では行わない。
