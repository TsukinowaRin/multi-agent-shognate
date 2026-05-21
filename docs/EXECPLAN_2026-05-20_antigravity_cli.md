# ExecPlan: Antigravity CLI Migration

作成日: 2026-05-20

## 目的

Gemini CLI 対応を廃止し、Google Antigravity CLI (`agy`) を Shogunate の選択可能 CLI として追加する。既存 `gemini` 設定は新規 UI には出さず、runtime では `antigravity` へ互換移行する。

## 前提

- 公式 docs では Antigravity CLI の実行コマンドは `agy`。
- CLI settings は `~/.gemini/antigravity-cli/settings.json`。
- CLI flags として `--dangerously-skip-permissions` が使える。
- core settings / auth は Antigravity 2.0 と共有されるが、Shogunate では role-local `HOME` / XDG を使い、host の認証ファイルだけを symlink する方針を維持する。

## 方針

- 新しい CLI type は `antigravity` とする。
- `gemini` は設定ファイルに残っていても runtime 上は `antigravity` として扱う互換 alias にする。
- `cli.commands.antigravity` の既定は `agy --dangerously-skip-permissions`。
- role-local state は `.shogunate/cli-state/antigravity/agents/<role>/home`。
- host auth / account state は `~/.gemini/antigravity-cli/` 配下と、`agy` が参照する host `~/.gemini/oauth_creds.json` / `~/.gemini/google_accounts.json` を symlink し、settings / keybindings / plugin / cache は role-local に残す。
- `cli.commands.gemini` は Antigravity 起動 command として流用しない。
- Gemini thinking alias 生成は廃止し、Antigravity は `/model` や settings の pane-local state に任せる。
- instruction generator は `antigravity-*` を生成し、`gemini-*` の新規生成を止める。

## 手順

1. `lib/cli_adapter.sh` の allowed CLI / command builder / state isolation / availability / display / instruction path を更新する。
2. `scripts/configure_runtime_roles.py` と `scripts/configure_agents.sh` の選択肢を `antigravity` へ更新し、Gemini thinking 設定を削除または無効化する。
3. `scripts/inbox_watcher.sh` / `scripts/switch_cli.sh` / runtime preference sync の `gemini` 分岐を `antigravity` に置き換える。
4. `scripts/build_instructions.sh` と `instructions/cli_specific/` を Antigravity 用に更新し、generated instruction を再生成する。
5. README / README_ja / docs index を更新する。
6. Bats / Python tests を Antigravity expectations へ更新して検証する。

## 検証

- `bash -n lib/cli_adapter.sh scripts/inbox_watcher.sh scripts/switch_cli.sh scripts/configure_agents.sh scripts/build_instructions.sh`
- `bats tests/unit/test_cli_adapter.bats tests/unit/test_configure_runtime_roles.bats tests/unit/test_switch_cli.bats tests/unit/test_build_system.bats`
- `python3 scripts/configure_runtime_roles.py --default antigravity --ashigaru-count 1 --shogun antigravity --karo codex --gunshi codex --ashigaru1 antigravity --dry-run`
- `bash scripts/build_instructions.sh`
- `git diff --check`

## 進捗

- [x] 2026-05-20: 要件と計画を作成。
- [x] 2026-05-20: Adapter / runtime scripts を更新。
- [x] 2026-05-20: Configure scripts / tests を更新。
- [x] 2026-05-20: Instructions / docs を更新。
- [x] 2026-05-20: 検証完了。commit / push は作業終了時に実施。

## 実施結果

- `gemini` は新規設定 UI / README / generated instruction から外した。
- 既存 config に `type: gemini` が残っている場合は runtime で `antigravity` に正規化する。
- Antigravity は `agy --dangerously-skip-permissions` を既定コマンドにし、role-local `HOME` / XDG state を使う。
- host auth は `.gemini/antigravity-cli/` 配下の既知ファイルに加え、`agy` が使う host `.gemini/oauth_creds.json` / `.gemini/google_accounts.json` も symlink し、settings / model / cache / history は role-local に残す。
- 2026-05-20 追補: host auth は Gemini CLI 時代と同じく共有するが、`cli.commands.gemini` の fallback は使わない。
- `scripts/sync_gemini_settings.py` と Gemini generated instructions / tests は廃止した。

## 検証結果

- `bash -n lib/cli_adapter.sh scripts/inbox_watcher.sh scripts/switch_cli.sh scripts/configure_agents.sh scripts/build_instructions.sh scripts/ratelimit_check.sh shutsujin_departure.sh first_setup.sh` → PASS
- `python3 scripts/configure_runtime_roles.py --default antigravity --ashigaru-count 1 --shogun antigravity --karo codex --gunshi codex --ashigaru1 antigravity --dry-run` → PASS
- `bats tests/unit/test_cli_adapter.bats tests/unit/test_configure_runtime_roles.bats tests/unit/test_switch_cli.bats tests/unit/test_build_system.bats tests/unit/test_send_wakeup.bats tests/unit/test_configure_agents.bats tests/unit/test_sync_runtime_cli_preferences.bats tests/unit/test_ratelimit_check.bats tests/unit/test_idle_flag.bats tests/unit/test_mux_parity.bats` → PASS (`392` tests)
- `python3 -m unittest tests.unit.test_package_distribution tests.unit.test_update_manager` → PASS (`17` tests)
- `bats tests/unit/test_build_system.bats tests/unit/test_mux_parity.bats` → PASS (`118` tests)
- `rg -n "Gemini CLI|type: gemini|cli\\.default.*gemini|gemini --yolo" README.md README_ja.md scripts lib tests instructions/cli_specific` → PASS (no matches)
- `git diff --check` → PASS

## 復旧

- Antigravity CLI が実機に無い環境では、`resolve_cli_type_for_agent` が Codex など利用可能 CLI へ fallback する。
- 既存 `gemini` 設定は当面 `antigravity` alias として読むため、古い config で即時起動不能にならない。

## 2026-05-21 追補: runtime keyring 起動

### 背景

- 実機 WSL では `agy` の OAuth token がファイルではなく Secret Service / GNOME keyring に保存された。
- `secret-tool` / `gnome-keyring-daemon` が無い、または default collection が locked の場合、ログイン成功後も保存できず、次回また OAuth URL が出た。
- 空パスワード keyring に切り替えた後、`agy` は `ChainedAuth: authenticated via keyring` / `Print mode: silent auth succeeded` まで進み、再ログインなしで応答した。

### 方針

- Shogunate runtime は Antigravity 起動直前に `scripts/ensure_antigravity_keyring.sh` を呼ぶ。
- helper は Linux 上でだけ Secret Service の疎通を確認し、必要なら `gnome-keyring-daemon --start --components=secrets` を試す。
- helper は既存 keyring を削除・退避・再作成しない。空パスワード keyring への切り替えは user 明示操作だけで行う。
- host の `.gemini/antigravity-cli/cache/onboarding.json` は、role-local file が未作成のときだけ初期コピーし、Terms / onboarding 画面の繰り返しを避ける。`settings.json` 全体や conversation/cache/history は共有しない。
- 2026-05-21 追補: Antigravity の `settings.json` は symlink 共有せず、host settings を role-local 初期値として読み込み、Shogunate workspace trust と `toolPermission=always-proceed` / `allowNonWorkspaceAccess=true` を補完する。これにより host のモデル初期値を使いつつ、以後の role-local 変更は独立して保持する。
- 2026-05-21 追補: OpenCode の `model.json` は role-local に独立保存するが、role 側が空の初期状態（recent / favorite が空）の場合は host の現在値で再シードする。role 側でモデルを選択済みの場合は上書きしない。
- Agy 実機テストは制限を避けるため1体だけにし、残りの役職は Codex にする。

### 追加検証

- `bash -n lib/cli_adapter.sh scripts/ensure_antigravity_keyring.sh shutsujin_departure.sh`
- `bats tests/unit/test_cli_adapter.bats`
- `Shogunate-test` に最新コードを反映し、`shogun/karo/gunshi/ashigaru2+` は Codex、`ashigaru1` だけ Antigravity にして runtime smoke を行う。

### 実施結果

- `scripts/ensure_antigravity_keyring.sh` を追加し、Antigravity 起動 command の先頭で実行するようにした。
- `build_cli_command_with_type ashigaru1 antigravity` は、role-local HOME へ入る前に keyring helper を呼び、host auth symlink と onboarding state seed を行う。
- `Shogunate-test` へ最新コードを反映し、`shogun/karo/gunshi/ashigaru2` は Codex、`ashigaru1` は Antigravity で `bash shutsujin_departure.sh -c -S` を実行した。
- Runtime は 5/5 agents の ready 判定、初動命令配信、watcher / bridge / runtime CLI preference daemon 起動まで完了した。
- Antigravity role-local log で `ChainedAuth: authenticated via keyring (effective: keyring)` を確認した。
- Agy pane は Terms / login prompt ではなく通常 prompt まで進み、直接 `Reply exactly: ready:ashigaru1` を送って `ready:ashigaru1` 応答を確認した。

### 追加検証結果

- `bash -n lib/cli_adapter.sh scripts/ensure_antigravity_keyring.sh shutsujin_departure.sh first_setup.sh` → PASS
- `bats tests/unit/test_cli_adapter.bats` → PASS (`126` tests; `secret-tool` 導入済み環境の keyring-missing test は skip)
- `scripts/ensure_antigravity_keyring.sh` → PASS (`status=0`)
- `git diff --check` → PASS

### 残リスク

- Agy の Terms / onboarding state は `onboarding.json` を未作成時に初期コピーする。host 側で未同意の場合は、ユーザーが host `agy` で一度 onboarding を完了する必要がある。
- Agy は制限が厳しいため、実機 smoke では1体だけに限定した。複数 Agy 同時運用は未検証。
