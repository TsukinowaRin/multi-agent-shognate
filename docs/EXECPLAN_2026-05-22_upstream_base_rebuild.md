# ExecPlan: upstream latest base rebuild

作成日: 2026-05-22

## 目的

最新の本家 `upstream/main` を土台にして、Shogunate 独自機能を再実装・整理する。目的は単に fork 差分を戻すことではなく、必要な機能と本家へ分離 PR できる機能を見極めながら、実運用できる Shogunate branch を作ること。

## 現在の base

- upstream: `yohey-w/multi-agent-shogun`
- base commit: `84c8e82 fix: keep OpenCode runtime variants out of tracked output`
- base describe: `v5.0.0-6-g84c8e82`
- 作業ブランチ: `codex/upstream-main-rebuild-shogunate`
- 参照元 Shogunate branch: `codex/upstream-v4.6.0-sync`

## 移植方針

1. 本家に既にある OpenCode support は upstream 実装を正とする。
2. Shogunate 独自機能は次の PR 分離候補に分ける。
   - package distribution / npm wrapper
   - cross-platform runtime launchers
   - CLI state isolation / host auth sharing
   - Antigravity / Kilo / LocalAPI support
   - dynamic topology / multi-Karo
   - event-driven runtime hardening
   - docs / handoff / ExecPlan workflow
3. まず低衝突の package / docs / launcher を移植し、その後 runtime core を移植する。
4. CoDD gate と Android app / APK 対応は今回の初期再構築では外す。後段の独立 PR 候補として再評価する。
5. 移植時は current Shogunate branch から必要箇所を参照するが、upstream の最新ファイル構造を優先して統合する。

## 進捗

- [x] Goal を作成した。
- [x] `upstream/main` を取得し、最新 base commit を確認した。
- [x] `codex/upstream-main-rebuild-shogunate` を `upstream/main` から作成した。
- [x] 要求を `docs/REQS.md` に正規化した。
- [x] この ExecPlan を作成した。
- [x] Shogunate 独自機能を file / feature map として棚卸しする。
- [x] package distribution / npm wrapper を upstream base に移植する。
- [x] launcher / role config / shell aliases を移植する。
- [x] CLI state isolation と AGY / Kilo / LocalAPI を移植する。
- [ ] dynamic topology / multi-Karo / event-driven hardening を移植する。
- [x] Android remote control / pairing profile はユーザー指示により初期再構築スコープ外へ移した。
- [x] CoDD gate はユーザー指示により初期再構築スコープ外へ移した。
- [ ] build / unit / integration /実機 runtime 検証を実行する。
- [ ] PR 分離候補と最終差分をまとめる。

## 具体手順

1. `git diff --name-status upstream/main..codex/upstream-v4.6.0-sync` を機能群に分類する。
2. 低衝突ファイルを移植して最初の checkpoint commit を作る。
3. runtime core を小さく移植し、shell syntax と Bats を通す。
4. CLI adapter と watcher を移植し、Codex / OpenCode / Antigravity / Kilo / LocalAPI の代表起動 command をテストする。
5. 隔離 test folder に作業ブランチを反映し、実 tmux runtime を起動する。

## 棚卸し結果

2026-05-22 時点の大分類:

- `package_distribution`: npm / npx wrapper、release package、bootstrap、release workflow。
- `launchers_setup`: `Shogunate-Runtime.*`、role configure launcher、shell alias、初期設定。
- `cli_state_and_extra_cli`: host auth sharing、role-local settings、Antigravity / Kilo / LocalAPI。
- `runtime_core`: `goza-no-ma`、watcher、bridge daemon、multi-Karo topology、runtime recovery。
- `android_remote`: 今回は統合しない。後段で必要性を再評価する。
- `codd_gate`: 今回は統合しない。後段で必要性を再評価する。
- `docs_instructions_agents`: generated instructions、role docs、handoff / ExecPlan docs。
- `tests`: runtime / CLI / package regression tests。

移植順は、低衝突の `package_distribution` / `launchers_setup` から始め、その後 `cli_state_and_extra_cli` と `runtime_core` を統合する。

## 検証

- `bash -n ...`
- `bash scripts/build_instructions.sh`
- `bats tests/unit/...`
- `python3 -m unittest ...`
- `npm pack --dry-run`
- 隔離 runtime で `./Shogunate-Runtime.sh`
- `git diff --check`

## 検証ログ

2026-05-22 package distribution:

- `bash -n scripts/shogunate_package_bootstrap.sh scripts/prepublish_check.sh` passed.
- `python3 -m unittest tests.unit.test_package_distribution` passed: 4 tests.
- `node bin/shogunate.js --help` passed.
- `npm pack --dry-run` passed and package output included npm wrapper/bootstrap, while excluding Android release and CoDD files.

2026-05-22 launchers / role config:

- `bash -n lib/topology_adapter.sh Shogunate-Runtime.sh Shogunate-Configure-Roles.sh scripts/configure_agents.sh scripts/ensure_generated_instructions.sh scripts/install_shell_aliases.sh scripts/shell_aliases.sh` passed.
- `python3 -m py_compile scripts/configure_runtime_roles.py` passed.
- `bats tests/unit/test_configure_runtime_roles.bats tests/unit/test_configure_agents.bats tests/unit/test_configure_role_launchers.bats tests/unit/test_runtime_launchers.bats tests/unit/test_shell_aliases.bats tests/unit/test_interactive_agent_runner.bats` passed: 13 tests.

2026-05-22 CLI state / extra CLI / instructions:

- `bash -n lib/cli_adapter.sh scripts/ensure_antigravity_keyring.sh scripts/ratelimit_check.sh scripts/runtime_cli_pref_daemon.sh` passed.
- `python3 -m py_compile scripts/localapi_repl.py scripts/sync_opencode_config.py scripts/sync_runtime_cli_preferences.py` passed.
- `bats tests/unit/test_cli_adapter.bats tests/unit/test_sync_opencode_config.bats tests/unit/test_sync_runtime_cli_preferences.bats tests/unit/test_runtime_cli_pref_daemon.bats tests/unit/test_ratelimit_check.bats` passed: 146 tests.
- `bash scripts/build_instructions.sh` passed.
- `bats tests/unit/test_build_system.bats` passed: 57 tests.
- CoDD references were intentionally absent from generated instructions and OpenCode agents.

## 復旧

- 失敗した機能群は、その機能群 commit だけを revert する。
- `codex/upstream-v4.6.0-sync` は参照元として維持し、直接変更しない。
- upstream base branch が破綻した場合は、`git switch codex/upstream-v4.6.0-sync` で現行安定 branch に戻れる。
