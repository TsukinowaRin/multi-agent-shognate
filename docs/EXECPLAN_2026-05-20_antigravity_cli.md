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
- host auth / account state は `~/.gemini/antigravity-cli/` 配下の必要最小限を symlink し、settings / keybindings / plugin / cache は role-local に残す。
- 旧 Gemini CLI root auth (`~/.gemini/oauth_creds.json` / `~/.gemini/google_accounts.json`) と `cli.commands.gemini` は Antigravity に流用しない。
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
- host auth は `.gemini/antigravity-cli/` 配下の既知ファイルだけ symlink し、settings / model / cache / history は role-local に残す。
- 2026-05-20 追補: Antigravity auth は Gemini CLI root auth とは別物として扱い、`.gemini/oauth_creds.json` / `.gemini/google_accounts.json` と `cli.commands.gemini` の fallback は使わない。
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
