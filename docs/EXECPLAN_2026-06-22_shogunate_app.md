# ExecPlan: Shogunate App

最終更新: 2026-06-24

## 目的

現行Androidアプリを、Windows / Linux / macOS / Android で使える `Shogunate App` 構想へ発展させる。Codex App のようなチャット・実行状況・成果物確認体験を、Shogunate の role / agent abstraction を通じて任意の対応AI CLIで使えるようにする。

## 前提

- Shogunate runtime は `cd <project> && shogunate` の project runtime を正とする。
- 現行Android app は SSH / Pair / tmux / dashboard.md を直接操作している。
- 初期フェーズでは、既存Android導線を壊さず、共通化できる境界を決める。
- Android は複数の cwd-first Shogunate runtime を「陣営」として扱い、接続設定と project 固有 tmux target を切り替えられる必要がある。
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
- Camp profiles: `ShogunateCampProfileStore` が複数陣営を SharedPreferences に保存し、既存単一接続設定を初回移行する。

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
   - Android の短期実装では connection profile を「陣営」と呼び、host / port / user / key / project / targets を保存する。

## Android 複数陣営の短期実装

- 設定画面に `陣営` section を追加し、陣営名入力と保存済み陣営一覧を表示する。
- 陣営選択時は既存の host / port / user / key / project / shogun target / agents target 欄へ反映する。
- `接続` または `保存` 時に現在の設定を陣営プロファイルへ upsert する。
- `shogunate pair` 成功時は Pair response の project / target を陣営として保存し、再接続時も project 固有 target を使う。
- root Android source と `shogunate_mod/mobile/android` は同内容に保ち、package contract で差分を検出する。

## Android 戦場タブの短期実装

- 下タブを `将軍 / 戦場 / エージェント / 戦況 / 設定` の5タブへ拡張する。
- `戦場` は remote project path の入力、`開く`、`起動`、過去に開いた project 履歴を持つ。
- `開く` は保存済み SSH 設定で自動接続し、remote directory の存在確認後に履歴へ保存する。
- `起動` は保存済み SSH 設定で自動接続し、remote project で Shogunate を `resume --no-attach` 起動する。
- 起動時は非ログイン SSH の PATH 差分を吸収するため、`~/.local/bin`、`~/bin`、nvm の node bin を PATH に追加する。
- 起動成功後は project を陣営プロファイルにも反映し、将軍/エージェント/戦況タブが同じ project を使えるようにする。
- host 側 `shogunate projects` が使える場合は、`開く` と `起動` の project を Shogunate 本体 registry にも best-effort で同期する。

## Shogunate 本体 project registry

- MOD 正本は `shogunate_mod/projects/registry.py`。
- 既定保存先は `~/.shogunate/projects.json`。テストでは `SHOGUNATE_PROJECT_REGISTRY` で差し替える。
- package command は `shogunate projects add DIR --name NAME --select`、`shogunate projects`、`shogunate projects current`、`shogunate projects remove NAME` を提供する。
- 起動導線は `shogunate --project @NAME resume` と `shogunate open NAME` を提供し、cwd-first 導線と並存する。
- Android 戦場タブは app 内履歴を持ちつつ、host 側が対応済みなら同じ registry に同期する。

## Shogunate App向け本体API

- MOD 正本は `shogunate_mod/battlefield/api.py`。
- アプリの階層は `Host -> Battlefield(project runtime) -> App Session -> Role Chat` とする。
- `shogunate app capabilities --json` で host と対応機能を返す。
- `shogunate battlefield list/status/start/stop/roles/sessions/session-create/transcript/send` を提供する。
- `start --resume` は既存runtime継続、`start --new` は clean runtime と新規app session 作成を意味する。
- `send` は対象runtimeの `shogunate_mod/inbox/write.sh` を使って role inbox へ `user_message` を送り、同時に `queue/app/sessions/<id>/messages.jsonl` へ user transcript を残す。

## Android 司令台の現行実装

- app 起動直後の入口は `司令台` タブ。下タブは `司令台 / 将軍 / エージェント / 戦況 / 設定`。
- `BattlefieldViewModel` は SSH 越しに `shogunate app capabilities --json` と `shogunate battlefield ... --json` を呼び、tmux pane 名の推測や direct tmux 操作を避ける。
- 司令台は接続先PC、登録済みproject、runtime status、会話session、role、transcript を1画面で扱う。
- 司令台から remote project 登録、続きから起動、新規起動、終了、session作成、role選択、roleへの送信を行う。
- 複数PCがある場合、司令台は保存済み陣営をPC一覧として表示し、SSH生存チェックでオンライン/オフラインとproject数を表示する。
- 戦場一覧は選択中PCのprojectだけを表示し、start / stop / send / transcript は対象projectが属するPCへ接続してから実行する。
- 既存の将軍/エージェント/戦況/設定タブは残し、段階移行中の互換導線として扱う。

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
- [x] Android 複数陣営プロファイルの保存・選択 UI と保存ロジックを追加。
- [x] root Android source と MOD canonical copy を同期。
- [x] Android `戦場` タブを追加し、remote project 履歴と Shogunate 起動導線を実装。
- [x] OnePlus USB実機で 5タブ表示、戦場タブ表示、remote Shogunate 起動を確認。
- [x] Shogunate 本体に登録済み project registry と `shogunate projects` / `shogunate open` 導線を追加。
- [x] Shogunate 本体に App向け battlefield API を追加し、Host / Project / Session / Role Chat の階層を提供。
- [x] Android app の入口を `司令台` に変更し、本体 App API で複数project / session / role chat を扱うUIへ作り直し。
- [x] Android app の司令台に複数PCのオンライン状態、SSH生存チェック、PC別project表示を追加。

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
- PASS: `cd android && ./gradlew --no-daemon -Dkotlin.compiler.execution.strategy=in-process -Pkotlin.compiler.execution.strategy=in-process testDebugUnitTest assembleDebug`
  - 2026-06-23: 39 tests / debug APK build PASS。
- PASS: `PYTHONDONTWRITEBYTECODE=1 python3 -m unittest tests.unit.test_package_distribution.PackageDistributionContractTests.test_android_source_has_mod_canonical_copy`
- PASS: `cd android && ./gradlew --no-daemon -Dkotlin.compiler.execution.strategy=in-process -Pkotlin.compiler.execution.strategy=in-process testDebugUnitTest assembleDebug`
  - 2026-06-24: 司令台UI / App API ViewModel 変更後に debug unit test と debug APK build PASS。
- PASS: `cd android && ./gradlew --no-daemon -Dkotlin.compiler.execution.strategy=in-process -Pkotlin.compiler.execution.strategy=in-process testDebugUnitTest assembleDebug`
  - 2026-06-26: 複数PCオンライン表示 / 生存チェック / PC別project表示 / SSH接続先切替修正後に debug unit test と debug APK build PASS。
- PASS: `PYTHONDONTWRITEBYTECODE=1 python3 -m unittest tests.unit.test_package_distribution.PackageDistributionContractTests.test_android_source_has_mod_canonical_copy`
  - 2026-06-26: root Android source と MOD canonical copy の同期を確認。
- PASS: OnePlus 9 Pro USB実機
  - 2026-06-24: `adb -s 661ecd40 install -r android/app/build/outputs/apk/debug/app-debug.apk` 成功。
  - 起動直後に `司令台` が表示され、下タブ `司令台 / 将軍 / エージェント / 戦況 / 設定` を UI dump で確認。
  - SSH未接続時の案内が Java 例外ではなく、設定タブで USB/無線接続を促す短い文言で表示されることを確認。
- PASS: OnePlus 9 Pro USB実機
  - debug APK install 成功。
  - 下タブ `将軍 / 戦場 / エージェント / 戦況 / 設定` 表示。
  - `戦場` タブで project path、`開く`、`起動`、履歴一覧表示。
  - `起動` 押下後、remote project の Shogunate 起動ログ生成と `tmux ls` 上の `shogunate` session 作成を確認。

## 今回の修正

- Android app に `ShogunateCampProfile` / `ShogunateCampProfileStore` を追加し、複数陣営の保存・選択を実装。
- Settings 画面に陣営 section を追加し、保存済み陣営の切替を既存 SSH / Pair 導線へ接続。
- Pair 成功時と通常接続時に現在の project 固有 target を陣営として保存する。
- Android app に `BattlefieldScreen` / `BattlefieldViewModel` / `BattlefieldProjectStore` を追加し、戦場タブで remote project を開く・起動する導線を実装。
- Shogunate 本体に `shogunate_mod/projects/registry.py` を追加し、package command / npm wrapper / Android 戦場タブから登録済み project を扱えるようにした。
- Shogunate 本体に `shogunate_mod/battlefield/api.py` を追加し、Appが登録済みprojectの起動状況、起動/終了、app session、役職送信を扱えるAPIを用意した。
- Android app の `BattlefieldScreen` / `BattlefieldViewModel` を、単体project起動UIから `司令台` UIへ置き換えた。
- `司令台` は Shogunate App API 経由で project list、role list、session list、transcript を取得し、start / stop / send / session-create を実行する。
- `send` は `shogunate battlefield send <project> <message> --role <role> --json` の引数順で呼ぶ。
- 下タブの初期表示を `司令台` にした。
- `SshManager.connect()` は host / port / user が変わった場合、既存SSHセッションを使い回さず新しいPCへ接続し直す。
- 司令台に `PC` 一覧と `生存チェック` を追加し、オンラインPCの登録済みprojectだけを `戦場` 一覧へ表示する。
- root Android source と MOD canonical copy を同期。

## 設計上の未決事項

- desktop 技術選定: Tauri / Electron / Flutter / Kotlin Multiplatform。
- Android を同一UIコードベースへ寄せるか、既存Kotlin/Composeを継続するか。
- App から直接 tmux を触るか、runtime API を必須化するか。
- Android 陣営 UI を「PC別」「project別」「runtime別」のどの粒度で見せるか。
- 複数陣営の削除・並び替え・状態表示を初期版に入れるか。
- 2026-06-24時点の司令台UIは Android build/unit と OnePlus実機インストール/起動/UI dump まで確認済み。Shogunate App API を使った実SSH操作は次の実機確認対象。
