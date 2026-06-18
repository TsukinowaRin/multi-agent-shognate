# ExecPlan: upstream core + Shogunate MOD split

最終更新: 2026-06-18

## 目的

Shogunate repo を「本家 Shogun core + Shogunate MOD」の構成へ移行する。既存体験を維持しつつ、本家更新時に衝突しやすい Shogunate-only 機能を `shogunate_mod/` 側へ集約する。

## 進捗

- [x] 本家 `upstream/main` を fetch し、最新 `431b86a` を確認。
- [x] 差分規模を確認。現 branch は upstream に対して 228 files / 約 66k insertions の大きな fork。
- [x] `shogunate_mod/` を追加。
- [x] package bootstrap / Android Pair server / shell aliases を MOD canonical source へ移動。
- [x] Gunkan auditor helpers を MOD canonical source へ移動。
- [x] 旧 `scripts/` path は互換 wrapper として維持。
- [x] `shogunate_mod/manifest.yaml` に core touchpoints と移行方針を記録。
- [x] npm package `files` に `shogunate_mod/` の正本ファイルを追加。
- [x] branch policy helpers を `shogunate_mod/git/branch_policy.sh` へ移動し、旧 `lib/branch_policy.sh` を source 互換入口化。
- [x] branch deploy/maintenance commands を `shogunate_mod/git/` へ移動し、旧 `scripts/pre_deploy_verify.sh` / `scripts/branch_drift_check.sh` / `scripts/auto_merge_short_lived.sh` を exec 互換入口化。
- [x] branch policy cron setup を `shogunate_mod/git/setup_cron.sh` へ移動し、旧 `scripts/setup_cron.sh` を exec 互換入口化。
- [x] `shogunate_mod/runtime/env.sh` を追加し、project/session helper を root runtime entrypoint から参照。
- [x] runtime core の project/session helper を adapter 化する。
- [x] `shogunate_mod/runtime/daemon.sh` を追加し、watcher / bridge / runtime-pref / Gunkan watch daemon orchestration を MOD 側へ移動。
- [x] `shogunate_mod/runtime/blocker.sh` を追加し、runtime-blocked dashboard notice / shogun relay / lord relay を MOD 側へ移動。
- [x] runtime blocker notice helper を `shogunate_mod/runtime/blocker_notice.py` へ移動し、旧 `scripts/runtime_blocker_notice.py` を import/exec 互換入口化。
- [x] runtime bridge scripts / daemons と live CLI preference daemon を `shogunate_mod/runtime/` へ移動し、旧 `scripts/*_bridge.py` / `scripts/*_daemon.sh` を exec 互換入口化。
- [x] runtime live CLI preference sync を `shogunate_mod/runtime/sync_cli_preferences.py` へ移動し、旧 `scripts/sync_runtime_cli_preferences.py` を import/exec 互換入口化。
- [x] `shogunate_mod/runtime/prompts.sh` を追加し、Codex / Antigravity / OpenCode prompt handling を MOD 側へ移動。
- [x] `shogunate_mod/runtime/android_compat.sh` を追加し、Android 互換 tmux session orchestration を MOD 側へ移動。
- [x] `shogunate_mod/runtime/bootstrap.sh` を追加し、startup bootstrap file generation / delivery / ready wait を MOD 側へ移動。
- [x] `shogunate_mod/runtime/directives.sh` を追加し、role linkage / event-driven / reporting / prompt label helpers を MOD 側へ移動。
- [x] `shogunate_mod/runtime/goza.sh` を追加し、Goza layout / pane grid / pane resolve helpers を MOD 側へ移動。
- [x] `shogunate_mod/runtime/launch.sh` を追加し、tmux send / CLI launch script / startup-window helpers を MOD 側へ移動。
- [x] `shogunate_mod/runtime/startup.sh` を追加し、startup lock / update check / logging / generated instruction ensure helpers を MOD 側へ移動。
- [x] `shogunate_mod/runtime/banner.sh` と `agent_cli.sh` を追加し、startup banner / runtime CLI metadata helpers を MOD 側へ移動。
- [x] `shogunate_mod/runtime/load.sh` を追加し、root entrypoint の MOD source 群を loader 1 本へ集約。
- [x] project/session/settings/Python preflight initialization を既存 MOD runtime helper へ移動。
- [x] `shogunate_mod/runtime/state.sh` を追加し、cleanup / queue reset / dashboard init / runtime coordination state を MOD 側へ移動。
- [x] Goza tmux session construction を `shogunate_mod/runtime/goza.sh` へ移動。
- [x] Agent CLI launch flow を `shogunate_mod/runtime/launch.sh` へ移動。
- [x] Watcher / bridge startup orchestration を `shogunate_mod/runtime/daemon.sh` へ移動。
- [x] Completion summary / Windows Terminal tab rendering を `shogunate_mod/runtime/summary.sh` へ移動。
- [x] Runtime lifecycle setup を `shogunate_mod/runtime/lifecycle.sh` へ移動。
- [x] Startup bootstrap delivery flow を `shogunate_mod/runtime/bootstrap.sh` へ移動。
- [x] Startup-time ASCII banner rendering を `shogunate_mod/runtime/banner.sh` へ移動。
- [x] Runtime options/help parsing を `shogunate_mod/runtime/options.sh` へ移動。
- [x] Runtime topology resolution を `shogunate_mod/runtime/topology.sh` へ移動。
- [x] Runtime departure entrypoint orchestration を `shogunate_mod/runtime/departure.sh` へ移動し、root `shutsujin_departure.sh` を薄い互換入口化。
- [x] Runtime launcher shared setup を `shogunate_mod/runtime/launcher.sh` へ移動し、root `Shogunate-Runtime.sh` / `Shutsujin.sh` を薄い互換入口へさらに寄せた。
- [x] Runtime shell launchers を `shogunate_mod/runtime/runtime_launcher.sh` / `shutsujin_launcher.sh` へ移動し、root `Shogunate-Runtime.sh` / `Shutsujin.sh` を exec 互換入口化。
- [x] root `shutsujin_departure.sh` が薄い MOD runtime entrypoint になっていることを manifest 上の互換 wrapper として整理した。
- [x] manifest の `current_core_touchpoints` を実態に合わせ、runtime wrapper ではなく、まだ root 側に残る instructions / OpenCode agent definitions / Android / workflow / package config overlay 群を追跡する形に更新した。
- [x] npm package CLI implementation を `shogunate_mod/package/npm_cli.js` へ移動し、root `bin/shogunate.js` を薄い互換入口化。
- [x] package first setup を `shogunate_mod/package/first_setup.sh` へ移動し、root `first_setup.sh` を exec 互換入口化。
- [x] package prepublish check を `shogunate_mod/package/prepublish_check.sh` へ移動し、旧 `scripts/prepublish_check.sh` を exec 互換入口化。
- [x] role configurator OS launchers を `shogunate_mod/configure/role_launcher.sh` へ集約し、root `Shogunate-Configure-Roles.*` を互換入口化。
- [x] Windows runtime launchers を `shogunate_mod/windows/` へ移動し、root `Shogunate-Runtime.bat` / `Shutsujin.bat` を互換入口化。
- [x] macOS runtime launcher を `shogunate_mod/macos/runtime_launcher.command` へ移動し、root `Shogunate-Runtime.command` を互換入口化。
- [x] Windows debug launchers を `shogunate_mod/windows/` へ移動し、root `Shutsujin-Clean.bat` / `Shutsujin-Resume.bat` を互換入口化。
- [x] 旧 `setup.sh` の互換処理を `shogunate_mod/runtime/setup_compat.sh` へ移動し、root `setup.sh` を exec 互換入口化した。
- [x] inbox writer policy を `shogunate_mod/inbox/write.sh` へ移動し、旧 `scripts/inbox_write.sh` を薄い互換入口化。
- [x] watcher supervisor を `shogunate_mod/watcher/supervisor.sh` へ移動し、旧 `scripts/watcher_supervisor.sh` を薄い互換入口化。
- [x] inbox watcher を `shogunate_mod/watcher/inbox_watcher.sh` へ移動し、旧 `scripts/inbox_watcher.sh` を source/exec 互換入口化。
- [x] CLI adapter を `shogunate_mod/cli/adapter.sh` へ移動し、旧 `lib/cli_adapter.sh` を source 互換入口化。
- [x] inbox path normalization を `shogunate_mod/inbox/path.sh` へ移動し、旧 `lib/inbox_path.sh` を source 互換入口化。
- [x] ntfy auth helpers を `shogunate_mod/notify/ntfy_auth.sh` へ移動し、旧 `lib/ntfy_auth.sh` を source 互換入口化。
- [x] ntfy send / listener scripts を `shogunate_mod/notify/` へ移動し、旧 `scripts/ntfy.sh` / `scripts/ntfy_listener.sh` を exec 互換入口化。
- [x] file-watch helpers を `shogunate_mod/watcher/file_watch.sh` へ移動し、旧 `lib/file_watch.sh` を source 互換入口化。
- [x] agent status helpers を `shogunate_mod/status/agent_status.sh` へ移動し、旧 `lib/agent_status.sh` を source 互換入口化。
- [x] agent status command を `shogunate_mod/status/command.sh` へ移動し、旧 `scripts/agent_status.sh` を exec 互換入口化。
- [x] rate-limit status command を `shogunate_mod/status/ratelimit_check.sh` へ移動し、旧 `scripts/ratelimit_check.sh` を exec 互換入口化。
- [x] agent registry を `shogunate_mod/topology/agent_registry.sh` へ移動し、旧 `lib/agent_registry.sh` を source 互換入口化。
- [x] topology adapter を `shogunate_mod/topology/adapter.sh` へ移動し、旧 `lib/topology_adapter.sh` を source 互換入口化。
- [x] Goza view attach/focus/autosave helpers を `shogunate_mod/view/` へ移動し、旧 `scripts/goza_no_ma.sh` / `scripts/focus_agent_pane.sh` / `scripts/goza_layout_autosave.sh` を exec 互換入口化。
- [x] Dashboard viewer を `shogunate_mod/view/dashboard_viewer.py` へ移動し、旧 `scripts/dashboard-viewer.py` を exec 互換入口化。
- [x] Antigravity keyring preflight を `shogunate_mod/cli/antigravity_keyring.sh` へ移動し、旧 `scripts/ensure_antigravity_keyring.sh` を exec 互換入口化。
- [x] CoDD check command を `shogunate_mod/gunkan/codd_check.sh` へ移動し、旧 `scripts/codd_check.sh` を exec 互換入口化。
- [x] interactive agent configurator を `shogunate_mod/configure/agents.sh` へ移動し、旧 `scripts/configure_agents.sh` を exec 互換入口化。
- [x] runtime role configurator を `shogunate_mod/configure/runtime_roles.py` へ移動し、旧 `scripts/configure_runtime_roles.py` を exec 互換入口化。
- [x] OpenCode/Kilo project config sync を `shogunate_mod/configure/sync_opencode_config.py` へ移動し、旧 `scripts/sync_opencode_config.py` を exec 互換入口化。
- [x] LocalAPI REPL を `shogunate_mod/localapi/repl.py` へ移動し、旧 `scripts/localapi_repl.py` を exec 互換入口化。
- [x] live CLI switch command を `shogunate_mod/configure/switch_cli.sh` へ移動し、旧 `scripts/switch_cli.sh` を exec 互換入口化。
- [x] generated instruction build / freshness guard を `shogunate_mod/instructions/` へ移動し、旧 `scripts/build_instructions.sh` / `scripts/ensure_generated_instructions.sh` を exec 互換入口化。
- [x] queue YAML slimming を `shogunate_mod/queue/` へ移動し、旧 `scripts/slim_yaml.py` / `scripts/slim_yaml.sh` を exec/import 互換入口化。
- [x] queue history book generation を `shogunate_mod/queue/history_book.sh` へ移動し、旧 `scripts/history_book.sh` を exec 互換入口化。
- [x] Claude Code SessionStart persona injection を `shogunate_mod/hooks/session_start_hook.sh` へ移動し、旧 `scripts/session_start_hook.sh` を exec 互換入口化。
- [x] Claude Code Stop hook inbox delivery / idle flag publication を `shogunate_mod/hooks/stop_hook_inbox.sh` へ移動し、旧 `scripts/stop_hook_inbox.sh` を exec 互換入口化。
- [x] shell rc alias installer を `shogunate_mod/shell/install_aliases.sh` へ移動し、旧 `scripts/install_shell_aliases.sh` を exec 互換入口化。
- [x] runtime MCP health check を `shogunate_mod/runtime/mcp_health_check.sh` へ移動し、旧 `scripts/mcp_health_check.sh` を exec 互換入口化。
- [x] runtime mux parity smoke を `shogunate_mod/runtime/mux_parity_smoke.sh` へ移動し、旧 `scripts/mux_parity_smoke.sh` を exec 互換入口化。
- [x] update manager を `shogunate_mod/update/manager.py` へ移動し、旧 `scripts/update_manager.py` を exec 互換入口化。
- [x] update shell commands を `shogunate_mod/update/` へ移動し、旧 `scripts/upstream_sync.sh` / `scripts/stop_and_apply_update.sh` を exec 互換入口化。
- [x] `.gitignore` whitelist に `shogunate_mod/` 正本群を追加し、MOD canonical source が Git 管理対象として見える状態にした。
- [x] npm package `files` に Python 生成物除外を追加し、`shogunate_mod/` ディレクトリ収録時も `__pycache__` / `.pyc` を混ぜない。
- [x] full validation を再実行する。
- [x] CoDD graph config を `shogunate_mod/gunkan/codd.yaml` へ MOD 正本として追加し、root `.codd/codd.yaml` は CoDD tooling 互換配置として同期テストで固定した。
- [x] OpenCode permission matrix を `shogunate_mod/configure/opencode-permissions.yaml` へ MOD 正本として追加し、root `config/opencode-permissions.yaml` は生成済み OpenCode agent / docs 向け互換配置として維持した。
- [x] OpenCode TUI keybinding config を `shogunate_mod/configure/opencode-tui.json` へ MOD 正本として追加し、CLI adapter は MOD 正本を `OPENCODE_TUI_CONFIG` に渡すよう変更した。
- [x] ntfy auth sample config を `shogunate_mod/notify/ntfy_auth.env.sample` へ MOD 正本として追加し、root `config/ntfy_auth.env.sample` はユーザー向け互換 sample として同期テストで固定した。
- [x] 初回セットアップ用 default config template を `shogunate_mod/configure/settings.yaml.sample` / `projects.yaml.sample` へ MOD 正本として追加し、root `config/*.yaml` はユーザー設定として維持する方針にした。
- [x] role/common/CLI instruction source を `shogunate_mod/instructions/source/` へ MOD 正本として追加し、builder / freshness guard は MOD source を優先、root `instructions/` 非生成 source は互換コピーとして同期テストで固定した。
- [x] Claude auto-load source を `shogunate_mod/instructions/autoload/CLAUDE.md` へ MOD 正本として追加し、builder / freshness guard は MOD autoload source を優先、root `CLAUDE.md` は Claude Code 用互換コピーとして同期テストで固定した。
- [x] GitHub Actions workflow source を `shogunate_mod/package/workflows/` へ MOD 正本として追加し、root `.github/workflows/` は GitHub Actions 用互換配置として同期テストで固定した。
- [x] Android app source を `shogunate_mod/mobile/android/` へ MOD 正本として追加し、root `android/` は Android Studio / Gradle 用互換 working tree として同期テストで固定した。Android build/cache/local APK artifacts は runtime package から除外する方針を維持した。
- [x] npm package metadata を `shogunate_mod/package/package.json` / `package-lock.json` へ MOD 正本として追加し、root `package*.json` は npm-required 互換コピーとして同期テストで固定した。
- [x] package prepublish check で root `package*.json` と MOD 正本の同期を検査するようにした。
- [x] generated instruction freshness guard の target に root `AGENTS.md`、`.github/copilot-instructions.md`、Kimi auto-load、OpenCode agent definitions を追加し、MOD source / MOD OpenCode permission matrix 変更時に root 生成物の古さを検出できるようにした。
- [x] `agents/default/` を Kimi K2 auto-load root 生成先として manifest の current core touchpoint に追加した。
- [x] package prepublish check で root 互換コピー（`CLAUDE.md`, `.codd/codd.yaml`, `config/opencode-*.json|yaml`, `config/ntfy_auth.env.sample`, root `instructions/` 非生成 source）と MOD 正本の同期も検査するようにした。
- [x] package prepublish check で `shogunate_mod/instructions/ensure_generated.sh` を実行し、古い root 生成物が release 前に dirty gate で止まるようにした。release workflow には PyYAML venv setup を追加し、npm package には `requirements.txt` を含めた。
- [x] PyYAML dependency file を `shogunate_mod/package/requirements.txt` へ MOD 正本として追加し、root `requirements.txt` は Python tooling / package compatibility copy として同期テストと prepublish gate で固定した。first setup と release workflow は MOD 正本を優先して使う。
- [x] Claude Code / Cursor skill sources を `shogunate_mod/skills/claude/` / `shogunate_mod/skills/cursor/` へ MOD 正本として追加し、root `skills/` / `.cursor/skills/` は CLI 互換コピーとして同期テストと prepublish gate で固定した。npm package には root 互換 skills と MOD skills の両方を含めた。
- [x] 初回セットアップ用 runtime state template を `shogunate_mod/package/templates/` へ MOD 正本として追加し、root `memory/MEMORY.md.sample` / `saytask/streaks.yaml.sample` は互換コピーとして同期テストと prepublish gate で固定した。first setup は MOD template から `memory/MEMORY.md`, `memory/global_context.md`, `saytask/streaks.yaml` を初回生成する。
- [x] root `images/` と `reports/` を runtime package surface から外す方針を `.gitattributes` / package contract test / manifest に記録した。npm package は既に含めておらず、release archive でも `export-ignore` で除外する。
- [x] Karo integration/context templates を `shogunate_mod/templates/` へ MOD 正本として追加し、root `templates/` は generated instruction が参照する互換コピーとして同期テストと prepublish gate で固定した。npm package には root 互換 templates と MOD templates の両方を含めた。
- [x] Claude Code hook/spinner settings を `shogunate_mod/hooks/claude_settings.json` へ MOD 正本として追加し、root `.claude/settings.json` は Claude Code が読む互換コピーとして同期テストと prepublish gate で固定した。npm package には root 互換 settings と MOD settings の両方を含めた。
- [x] context directory guide を `shogunate_mod/context/README.md` へ MOD 正本として追加し、root `context/README.md` は `context/{project}.md` の隣に置く互換コピーとして同期テストと prepublish gate で固定した。project-specific context files は user/runtime state として root `context/` に残す。
- [x] OpenCode inbox state update tool を `shogunate_mod/opencode/tools/mark-as-read.ts` へ MOD 正本として追加し、root `.opencode/tools/mark-as-read.ts` は OpenCode が読む互換コピーとして同期テストと prepublish gate で固定した。npm package には root 互換 OpenCode tool と MOD tool の両方を含めた。
- [x] Secret scanning config を `shogunate_mod/security/gitleaks.toml` へ MOD 正本として追加し、root `.gitleaks.toml` は gitleaks が読む互換コピーとして同期テストと prepublish gate で固定した。npm package には root 互換 config と MOD config の両方を含めた。
- [x] Development command surface を `shogunate_mod/development/Makefile` へ MOD 正本として追加し、root `Makefile` は `make` が読む互換コピーとして同期テストと prepublish gate で固定した。npm package には root 互換 Makefile と MOD Makefile の両方を含めた。
- [x] Release archive attribute rules を `shogunate_mod/package/gitattributes` へ MOD 正本として追加し、root `.gitattributes` は git archive が読む互換コピーとして同期テストと prepublish gate で固定した。
- [x] Public README source を `shogunate_mod/docs/README.md` / `README_ja.md` へ MOD 正本として追加し、root `README.md` / `README_ja.md` は GitHub/npm 表示用の互換コピーとして同期テストと prepublish gate で固定した。npm package には root 互換 README と MOD README の両方を含めた。
- [x] Public community docs を `shogunate_mod/docs/CHANGELOG.md` / `CONTRIBUTING.md` / `SECURITY.md` へ MOD 正本として追加し、root community docs は GitHub/npm 表示用の互換コピーとして同期テストと prepublish gate で固定した。npm package には root 互換 community docs と MOD community docs の両方を含めた。
- [x] Shogunate philosophy doc を `shogunate_mod/docs/philosophy.md` へ MOD 正本として追加し、root `docs/philosophy.md` は互換コピーとして prepublish gate で同期固定した。runtime npm package は MOD 正本だけを含め、root docs の broad package 収録は避ける。
- [x] GitHub funding metadata と development submodule metadata を `shogunate_mod/github/FUNDING.yml` / `shogunate_mod/development/gitmodules` へ MOD 正本として追加し、root `.github/FUNDING.yml` / `.gitmodules` は GitHub/Git が読む互換コピーとして同期テストと prepublish gate で固定した。npm package には MOD 正本 metadata を含めた。
- [x] Gunkan/CoDD design docs を `shogunate_mod/gunkan/docs/` へ MOD 正本として追加し、root `docs/codd/` は reader / CoDD graph tooling 用の互換コピーとして同期テストと prepublish gate で固定した。npm package には root 互換 docs と MOD docs の両方を含めた。
- [x] Shogunate test tree を `shogunate_mod/tests/` へ MOD 正本として追加し、root `tests/` は既存 test runner が読む互換コピーとして同期テストと prepublish gate で固定した。runtime npm package からは `shogunate_mod/tests/` を除外する方針を維持した。
- [x] manifest の test touchpoint を `tests/` へ集約し、`tests/unit/` / `tests/e2e/` の重複 touchpoint を削除した。unit/E2E の詳細は canonical_paths と同期 contract で追跡する。
- [x] Shogunate test support files を `shogunate_mod/tests/specs/` / `fixtures/` / `helpers/` へ MOD 正本として追加し、root `tests/specs/` / `tests/fixtures/` / `tests/helpers/` は既存 test suite が読む互換コピーとして同期テストと prepublish gate で固定した。runtime npm package からは `shogunate_mod/tests/` を除外する方針を維持した。
- [x] Shogunate unit test cases を `shogunate_mod/tests/unit/` へ MOD 正本として追加し、root `tests/unit/` は既存 unit runner が読む互換コピーとして同期テストと prepublish gate で固定した。runtime npm package からは `shogunate_mod/tests/` を除外する方針を維持した。
- [x] Shogunate E2E support files を `shogunate_mod/tests/e2e/` へ MOD 正本として追加し、root `tests/e2e/fixtures/` / `helpers/` / `mock_behaviors/` / `mock_cli.sh` は既存 E2E suite が読む互換コピーとして同期テストと prepublish gate で固定した。runtime npm package からは `shogunate_mod/tests/` を除外する方針を維持した。
- [x] Shogunate E2E test cases を `shogunate_mod/tests/e2e/*.bats` へ MOD 正本として追加し、root `tests/e2e/*.bats` は既存 E2E suite が読む互換コピーとして同期テストと prepublish gate で固定した。runtime npm package からは `shogunate_mod/tests/` を除外する方針を維持した。
- [x] `shogunate_mod/manifest.yaml` の `canonical_paths` と `compatibility_wrappers` が実在パスだけを指すことを package distribution contract で固定した。
- [x] `shogunate_mod/manifest.yaml` の `canonical_paths` key/value、`compatibility_wrappers`、`current_core_touchpoints` が重複 entry を持たないことを package distribution contract で固定した。
- [x] `shogunate_mod/manifest.yaml` の path 宣言が正規化された相対 path であり、directory は末尾 `/`、file は末尾 `/` なしで表すことを package distribution contract で固定した。
- [x] npm package `files` と MOD manifest `canonical_paths` の境界を contract test で固定し、runtime package に含めるべき MOD 正本と除外する `shogunate_mod/mobile/android/` / `shogunate_mod/tests/` を機械的に確認した。
- [x] `current_core_touchpoints` の root 互換 / generated / runtime-state surface が実在することを package distribution contract で固定した。
- [x] manifest の全 `compatibility_wrappers` が `shogunate_mod` へ委譲し、npm package `files` に収録されることを package distribution contract で固定した。
- [x] MOD 境界説明の `shogunate_mod/README.md` を manifest canonical path に追加し、package 収録と `.gitignore` whitelist を contract test で固定した。
- [x] `shogunate_mod/manifest.yaml` 自身を canonical path に追加し、`shogunate_mod/` 配下の正本ファイルがすべて manifest `canonical_paths` で覆われることを package distribution contract で固定した。
- [x] manifest `canonical_paths` が root 互換コピーではなく `shogunate_mod/` 配下の MOD 正本だけを指すことを package distribution contract で固定した。
- [x] manifest `current_core_touchpoints` が MOD 正本ではなく root/core 互換面だけを指すことを package distribution contract で固定した。
- [x] `shogunate_mod/README.md` が正本ファイルを持つ top-level MOD ディレクトリをすべて境界説明していることを package distribution contract で固定した。
- [x] `shogunate_mod/README.md` の `Boundaries` で ownership を宣言した MOD path が manifest `canonical_paths` に覆われ、manifest の canonical directory も README boundary で説明されることを package distribution contract で固定した。
- [x] manifest `current_core_touchpoints` のうち prepublish 同期対象ではない root 接点が、生成物・root public metadata・release archive 除外のいずれかとして明示分類されることを package distribution contract で固定した。
- [x] package distribution contract test を `shogunate_mod/package/prepublish_check.sh` から実行し、manifest/package 境界の退行を release 前 gate で検出できるようにした。
- [x] package distribution contract test が generated instruction freshness guard と dirty-worktree gate より前に実行されることを contract test で固定した。
- [x] manifest の `current_core_touchpoints` が reason / next_step を持ち、`compatibility_wrappers` と重複しないことを package distribution contract で固定した。
- [x] Windows role configurator launcher の実体を `shogunate_mod/windows/configure_roles.bat` へ移し、root `Shogunate-Configure-Roles.bat` を薄い互換 wrapper にした。
- [x] manifest の `compatibility_wrappers` が薄い入口に留まることを package distribution contract で固定した。Python wrapper は `runpy` / `importlib` 経由の MOD 委譲、非 Python wrapper は cURL bootstrap remote fallback を除いて短い入口に制限した。
- [x] root `.gitignore` を `shogunate_mod/package/gitignore` の互換コピーとして同期し、package boundary / MOD source whitelist の正本を MOD 側へ寄せた。manifest / prepublish gate / package distribution contract で同期を固定した。
- [x] npm bin entrypoint `bin/shogunate.js` を manifest の `compatibility_wrappers` に追加し、root の package command 入口も MOD 側 `shogunate_mod/package/npm_cli.js` へ委譲する薄い wrapper として package distribution contract で監査対象にした。
- [x] root の主要 launcher / `bin/` / `lib/` / `scripts/` 配下で `shogunate_mod` へ委譲するファイルが、manifest の `compatibility_wrappers` から漏れた場合に package distribution contract が失敗するようにした。生成物の `__pycache__` / `.pyc` は対象外にした。
- [x] Git 管理下の root wrapper surface（top-level launchers と `bin/` / `lib/` / `scripts/`）が manifest `compatibility_wrappers` と完全一致することを package distribution contract で固定し、package/release 指定の前段で root 実装混入を検出できるようにした。
- [x] package prepublish の root/MOD 同期対象が manifest でも追跡されることを package distribution contract で固定した。root 側は `current_core_touchpoints` または `compatibility_wrappers`、MOD 側は `canonical_paths` で覆われていることを検査する。
- [x] package prepublish の同期 pair が root 互換コピーから `shogunate_mod/` MOD 正本へ向くことを package distribution contract で固定し、同期方向の逆転や root-to-root 同期を検出できるようにした。
- [x] package prepublish の MOD 同期正本が、runtime package から意図的に外す `shogunate_mod/tests/` 以外では npm package `files` に収録されることを package distribution contract で固定した。
- [x] root `compatibility_wrappers` 内で参照される `shogunate_mod/...` 委譲先が、manifest の `canonical_paths` に覆われていることを package distribution contract で固定した。shell / bat の直書き path と Python の `Path(...) / "shogunate_mod" / ...` 形式を検出する。
- [x] root `compatibility_wrappers` が単に `shogunate_mod` 文字列を含むだけでなく、検出可能な明示的 MOD 委譲先 path を持つことを package distribution contract で固定した。
- [x] GitHub Actions workflow の root 互換コピー `.github/workflows/package-release.yml` / `test.yml` と MOD 正本 `shogunate_mod/package/workflows/` の同期を package prepublish gate でも検査するようにした。
- [x] GitHub Actions test workflow に Ubuntu `mod-check` job を追加し、CI 上でも package prepublish gate / detached source runtime smoke / Android Gradle check の代表検証を実行できるようにした。
- [x] Android app の root 互換 working tree `android/` と MOD 正本 `shogunate_mod/mobile/android/` の source 同期を package prepublish gate でも検査するようにした。Android SDK/cache/build/local/apk 生成物は除外し、runtime package から Android app を除外する方針は維持した。
- [x] generated root touchpoints の `.github/copilot-instructions.md`、`.opencode/agents/`、`agents/default/` を npm package `files` に追加し、package install 後も Copilot / OpenCode / Kimi auto-load surface が欠けないようにした。
- [x] cURL release archive に入る generated root touchpoints（`AGENTS.md`, `.github/copilot-instructions.md`, `agents/default/*`, `.opencode/agents/*`）も `shogunate_mod/instructions/ensure_generated.sh` の freshness target と一致することを package distribution contract に追加した。
- [x] manifest `canonical_paths` 配下の MOD 正本ファイルが `.gitignore` で隠れないことを package distribution contract に追加した。Android の build/cache/local settings と Python 生成物だけは意図的な ignored artifact として除外する。
- [x] manifest `current_core_touchpoints` の `next_step` で `synchronized` と宣言した root 互換面が、`shogunate_mod/package/prepublish_check.sh` の同期 gate に紐づいていることを package distribution contract に追加した。
- [x] root auto-load / tool compatibility surface の `CLAUDE.md` と `.codd/codd.yaml` を npm package `files` に追加し、package install 後も root 互換パスが欠けないようにした。
- [x] package distribution contract で実際の `npm pack --dry-run --json` を読み、root 互換面と MOD 正本が tarball に入ること、Android / tests / images / reports / local config / Python 生成物が混入しないことを固定した。
- [x] MOD manifest `canonical_paths` の runtime package 収録確認を `package.json` の `files` 配列ベースから実際の `npm pack --dry-run --json` ベースへ切り替えた。
- [x] manifest `compatibility_wrappers` と package prepublish の MOD 同期正本の収録確認も、`package.json` の `files` 配列ベースから実際の `npm pack --dry-run --json` ベースへ切り替えた。
- [x] package distribution contract から未使用になった `package.json` `files` 専用 helper を削除し、runtime package 収録判定を実際の `npm pack --dry-run --json` helper に一本化した。
- [x] public community docs と integration templates の収録確認も実際の `npm pack --dry-run --json` 結果へ切り替え、`package.json` の `files` 直接検査は package metadata 同期の確認に限定した。
- [x] npm package `files` の positive entry が実際の `npm pack --dry-run --json` 結果に少なくとも1つ対応することを package distribution contract に追加し、package metadata の死んだ収録指定を検出できるようにした。
- [x] runtime npm package の root `docs/` 収録を `docs/codd/` に絞り、ExecPlan / REQS / WORKLOG / upstream sync handover docs が tarball に混入しないことを実際の `npm pack --dry-run --json` 境界 contract で固定した。
- [x] runtime npm package の root `context/` 収録を `context/README.md` のみに絞り、project-specific context files が将来 tracked されても tarball に混入しないことを実際の `npm pack --dry-run --json` 境界 contract で固定した。
- [x] `package.json` の `files` 自体が root runtime / working-state directory（`context/`, `docs/`, `config/`, `memory/`, `saytask/`, `tests/` など）を広く指定しないことを package distribution contract に追加した。
- [x] runtime npm package の root `scripts/*.py` / `scripts/*.sh` glob を廃止し、manifest の `compatibility_wrappers` に宣言された root script wrapper だけを明示収録するようにした。実際の `npm pack --dry-run --json` 上の `scripts/` と manifest wrapper が完全一致することも contract で固定した。
- [x] runtime npm package の root `lib/` ディレクトリ指定を廃止し、manifest の `compatibility_wrappers` に宣言された root lib wrapper だけを明示収録するようにした。実際の `npm pack --dry-run --json` 上の `lib/` と manifest wrapper が完全一致することも contract で固定した。
- [x] runtime npm package の root `bin/` ディレクトリ指定を廃止し、manifest の `compatibility_wrappers` に宣言された `bin/shogunate.js` だけを明示収録するようにした。実際の `npm pack --dry-run --json` 上の `bin/` と manifest wrapper が完全一致することも contract で固定した。
- [x] runtime npm package に入る top-level launcher wrappers（`first_setup.sh`, `setup.sh`, `Shogunate-*`, `Shutsujin*`, `shutsujin_departure.sh`）も manifest `compatibility_wrappers` と一致することを package distribution contract で固定した。
- [x] cURL release archive でも root `bin/` / `lib/` / `scripts/` の実収録ファイルが manifest `compatibility_wrappers` と完全一致することを package distribution contract で固定した。これにより cURL archive 側へ root 実装が混入した場合も検出できる。
- [x] cURL release archive に入る top-level launcher wrappers（`first_setup.sh`, `setup.sh`, `Shogunate-*`, `Shutsujin*`, `shutsujin_departure.sh`）も manifest `compatibility_wrappers` と一致することを package distribution contract で固定した。
- [x] npm package / cURL release archive の top-level launcher wrapper contract を実収録ファイル一覧起点へ強化し、将来 `Shogunate-*` / `Shutsujin*` などの root launcher が増えた場合も manifest 未分類なら検出できるようにした。
- [x] runtime npm package に入る root `instructions/` が、MOD source の互換コピーまたは generated freshness guard 対象のどちらかで説明されることを package distribution contract に追加した。これにより漏れていた `instructions/generated/cursor-*.md` を `shogunate_mod/instructions/ensure_generated.sh` の targets に追加した。
- [x] cURL release archive に入る root `instructions/` も、MOD source の互換コピーまたは generated freshness guard 対象のどちらかで説明されることを package distribution contract に追加した。これにより npm package と cURL archive の両方で root prompt surface が MOD 正本由来であることを固定した。
- [x] generated OpenCode agent definitions の `Source:` コメントが root `instructions/` ではなく `shogunate_mod/instructions/source/` を指すことを package distribution contract に追加し、root generated surface が MOD 正本由来であることを固定した。
- [x] runtime npm package の generated root directory 指定（`.opencode/agents/` と `agents/default/`）を廃止し、`ensure_generated.sh` の freshness targets に宣言された generated root files だけを明示収録するようにした。実際の `npm pack --dry-run --json` 上の generated root files と freshness targets が一致することも contract で固定した。
- [x] runtime npm package の root OpenCode tool directory 指定（`.opencode/tools/`）を廃止し、MOD 正本と同期された `.opencode/tools/mark-as-read.ts` だけを明示収録するようにした。
- [x] runtime npm package の root `instructions/` ディレクトリ指定を廃止し、MOD source 互換コピーまたは generated freshness target として説明できる 67 instruction files だけを明示収録するようにした。
- [x] runtime npm package の root `skills/` / `.cursor/skills/` / `templates/` ディレクトリ指定を廃止し、MOD 正本と同期された root skills 11 files と root templates 6 files だけを明示収録するようにした。これにより root `skills/.system/` 用の除外指定も不要にした。
- [x] runtime npm package の root `docs/codd/` ディレクトリ指定を廃止し、MOD 正本 `shogunate_mod/gunkan/docs/` と同期された root CoDD docs 4 files だけを明示収録するようにした。
- [x] package `files` に残る positive broad entries が `shogunate_mod/` 配下だけであり、その entry で実際に `npm pack` へ入る全ファイルが manifest `canonical_paths` に覆われることを package distribution contract で固定した。
- [x] npm package / cURL release archive の top-level runtime file surface を実収録 contract で固定し、public files と manifest `compatibility_wrappers` の launcher 以外が root 直下に混入しないようにした。
- [x] `LICENSE` を root public metadata touchpoint として manifest に追加し、配布対象の top-level runtime file surface が manifest の `current_core_touchpoints` / `compatibility_wrappers` から導けることを package distribution contract で固定した。
- [x] manifest `current_core_touchpoints` のうち runtime package / cURL release archive の top-level file surface から意図的に外れる root file touchpoints が `.gitattributes`, `.gitignore`, `.gitmodules`, `package-lock.json` だけであることを package distribution contract で固定した。
- [x] npm package / cURL release archive の root directory surface を実収録 contract で固定し、新しい root directory が配布 surface に入った場合に明示分類を要求するようにした。
- [x] 配布対象の root directory surface が manifest の `current_core_touchpoints` / `compatibility_wrappers` / `canonical_paths` から導けることを package distribution contract で固定した。
- [x] manifest `current_core_touchpoints` の directory / nested path roots のうち runtime package / cURL release archive surface から意図的に外れる root touchpoints が `android/`, `images/`, `reports/`, `tests/` だけであることを package distribution contract で固定した。
- [x] npm package の root `config/` surface は公開 sample の `config/ntfy_auth.env.sample` だけ、cURL release archive の root `config/` surface は runtime defaults の `config/ntfy_auth.env.sample`, `config/opencode-permissions.yaml`, `config/opencode-tui.json` だけであることを実収録 contract で固定した。
- [x] npm package / cURL release archive の root dot-directory compatibility surface（`.claude/settings.json`, `.codd/codd.yaml`, `.github/copilot-instructions.md`, `.opencode/agents/*`, `.opencode/tools/mark-as-read.ts`, `agents/default/*`）を実収録 contract で固定した。
- [x] release archive の `export-ignore` 境界を文字列確認だけでなく `git check-attr export-ignore -- ...` の実効確認でも package distribution contract に固定した。Android app / images / reports は archive から外し、README など通常ファイルは archive 対象のままにする。
- [x] `git archive --worktree-attributes --format=tar HEAD` の実ファイルリストを package distribution contract で直接検査し、cURL release archive に runtime 必須 entrypoint / MOD runtime source / OpenCode guard config が入り、Android / tests / runtime state / internal docs / CI metadata / MOD metadata が実際に混入しないことを固定した。
- [x] cURL release archive にも `shogunate_mod/manifest.yaml` と `shogunate_mod/README.md` が残り、package install 後だけでなく release archive 展開後も MOD 境界情報を確認できることを package distribution contract で固定した。
- [x] release workflow で `bash scripts/prepublish_check.sh` が tag validation / `git archive` による tar.gz・zip 作成より前に実行されることを package distribution contract で固定した。
- [x] `memory/global_context.md` は root runtime state として package へ入れず、MOD 正本 template `shogunate_mod/package/templates/memory/global_context.md.sample` だけを package へ含め、first setup がそこから初期生成する境界を package distribution contract で固定した。
- [x] runtime/local state の `config/projects.yaml`, `config/settings.yaml`, `dashboard.md`, `memory/MEMORY.md`, `memory/global_context.md`, `saytask/streaks.yaml`, `queue/`, `runtime_sandboxes/` が npm package に混入しないことを package distribution contract で固定した。
- [x] cURL 用 release archive でも test tree、runtime/local state、作業計画 docs を `.gitattributes export-ignore` で除外し、`git check-attr export-ignore` の実効確認を package distribution contract に追加した。
- [x] 内部作業 docs index `docs/INDEX.md` も cURL release archive から除外し、公開 package / release に内部進行メモが混ざらない境界を `git check-attr export-ignore` contract で固定した。`docs/philosophy.md` と `docs/codd/` はユーザー向け/設計資料として archive に残す。
- [x] tracked `docs/` 全体について、cURL release archive に残せる公開 docs を `docs/philosophy.md` と `docs/codd/` だけに限定する動的 package distribution contract を追加した。新しい内部 docs が増えた場合も、`export-ignore` が無ければ test で検出する。
- [x] 過去の VPS PR #118 検証記録 `docs/vps_pr118_verification_plan.md` を cURL release archive から除外し、`git check-attr export-ignore` の実効確認を package distribution contract に追加した。
- [x] cURL 用 release archive から GitHub Actions workflow / Funding metadata / Git metadata / package lock / MOD package workflow metadata を `.gitattributes export-ignore` で除外し、runtime に必要な `package.json`, README, generated Copilot instructions, MOD runtime templates は残ることを contract で固定した。
- [x] cURL 用 release archive から MOD 側の GitHub funding metadata `shogunate_mod/github/FUNDING.yml` と development submodule metadata `shogunate_mod/development/gitmodules` も除外し、runtime archive と npm package の境界を分けた。npm package には MOD 正本 metadata を残す。
- [x] cURL 用 release archive で `first_setup.sh`, MOD first setup / requirements, Pair server, npm CLI, runtime launchers, departure entrypoint など install/runtime に必要な entrypoint が `export-ignore` されていないことを package distribution contract で固定した。
- [x] manifest の `config/` touchpoint を、tracked root config defaults は MOD 正本の同期互換コピー、`config/settings.yaml` / `config/projects.yaml` は local runtime state、という区別へ更新した。同期対象は package distribution contract の synchronized touchpoint gate でも固定した。
- [x] cURL release archive では root `config/opencode-permissions.yaml` / `config/opencode-tui.json` を残すことを package distribution contract に追加した。これらは generated OpenCode agent definitions の deny-list / compatibility guard path として存在が必要で、実行時 CLI adapter は MOD 正本 `shogunate_mod/configure/opencode-tui.json` を参照する。
- [x] `config/projects.yaml` を `config/settings.yaml` と同じ local runtime state として `.gitignore` / MOD gitignore / prepublish forbidden tracked path gate / `git check-ignore` gate へ明示追加した。
- [x] release 前の `prepublish_check.sh` に `require_manifest_mod_sources_in_head` gate を追加し、manifest `canonical_paths` 配下の MOD 正本ファイルが checked `HEAD` に存在しない場合に release を止めるようにした。これにより `git archive HEAD` が未コミット MOD 正本を落とす事故を防ぐ。
- [x] package release workflow の archive 対象を tag 名から checked-out `HEAD` へ変更し、archive 作成前に `TAG_COMMIT` と `HEAD_COMMIT` の一致を検証するようにした。これにより prepublish 済み tree と cURL release archive tree のズレを防ぐ。
- [x] package release workflow の upload artifact と GitHub Release `files` が、通常名/バージョン付きの package tar.gz/zip 4 assets だけを公開することを package distribution contract で固定した。
- [x] package release workflow の GitHub Release `target_commitish` を `github.sha` ではなく検証済み release tag output に固定し、Release 表示対象も archive tree と同じ tag に揃えた。
- [x] `require_manifest_mod_sources_in_head` の失敗時に missing 件数と「release archive 作成前に shogunate_mod sources を commit する」対処を表示するようにした。
- [x] full `prepublish_check.sh` を実測し、root `skills/.system/` が誤って MOD skill 同期対象になっていた問題を修正した。`require_directory_files_synced` は `*/.system/*` を除外し、system-managed skills を Shogunate MOD 正本に混ぜない。
- [x] full `prepublish_check.sh` の Android source sync が root Android build/cache 配下を `rglob` で列挙して遅くなる問題を修正した。`require_android_sources_synced` は `os.walk` で excluded dirs を traversal 前に prune する。
- [x] `require_manifest_mod_sources_in_head` も重複 canonical directory を再走査しないよう `expanded_dirs` で親ディレクトリ優先にした。
- [x] 一時 worktree `runtime_sandboxes/mod-smoke` で `shutsujin_departure.sh -s -c` を検証し、MOD runtime loader 経由の setup-only tmux runtime が一意 session で起動し、role pane metadata と queue 初期化が成立することを確認した。
- [x] USB 接続 Android 端末 `OnePlus9Pro` 上で `connectedDebugAndroidTest` を実行し、MOD 正本と同期された root Android app の connected debug test が通ることを確認した。
- [x] package bootstrap に `SHOGUNATE_PACKAGE_URL` override を追加し、GitHub release channel と同じ archive extraction path をローカル `file://` archive で smoke できるようにした。通常の latest / `--version` cURL 導線は維持する。
- [x] ローカル release archive から package install した `shogunate` command 経由で `shogunate clean --project <project> --no-attach -s` を実行し、package install 後の cwd-first runtime setup-only 起動が MOD runtime / project runtime copy 上で成立することを確認した。
- [x] ローカル release archive から package install した `shogunate` command 経由で `shogunate pair --project <project>` を起動し、sandbox `authorized_keys` への公開鍵登録、Pair response の runtime/target project 情報、成功後の自動停止表示が成立することを確認した。
- [x] tmux の session target が prefix match される問題を避けるため、runtime cleanup の `has-session` / `kill-session` を `=session-name` の exact target へ統一した。これにより legacy `shogun` cleanup が `shogunate-project-*` session を誤って kill する事故を防ぐ。
- [x] ローカル release archive から package install した `shogunate` command 経由で、2つの別 project を同時に `shogunate clean --project <project> --no-attach -s` 起動し、project ごとに独立した tmux session / runtime copy / metadata が並列成立することを確認した。
- [x] package prepublish の root/MOD sync gate は、親 directory sync が同じ subtree を覆う場合に nested sync を重複宣言しない contract で固定した。`tests/` tree は `tests -> shogunate_mod/tests` の1本へ集約した。
- [x] manifest `canonical_paths` の親子重複は `shogunate_mod/tests/` 配下の named test subsection だけに限定する contract を追加した。これにより新しい MOD 正本 directory を親子で曖昧に重複宣言する事故を検出する。
- [x] manifest `current_core_touchpoints` の `next_step` が root/MOD 同期を約束している場合、その root path が prepublish の sync pair または専用 sync function で実際に覆われることを動的 contract で固定した。
- [x] generated instruction freshness targets は、実ファイルとして存在し、manifest `current_core_touchpoints` の generated/root surface に分類されていることを contract で固定した。
- [x] cURL release archive には manifest `compatibility_wrappers` の全 root wrapper が実際に収録されることを package distribution contract で固定した。
- [x] cURL release archive では root runtime state の `queue/` は除外したまま、MOD 正本 `shogunate_mod/queue/` は収録対象へ戻した。manifest canonical files は属性だけでなく実 archive に存在することも contract で固定した。
- [x] root compatibility wrapper が参照する MOD delegate target は、manifest canonical path として分類され、cURL release archive にも実収録されることを contract で固定した。file canonical path が `file/extra` を誤って覆わないよう manifest coverage helper も厳密化した。
- [x] npm package でも root compatibility wrapper が参照する MOD delegate target が実収録されることを contract で固定し、npm / cURL の両配布経路で wrapper だけが残る事故を検出できるようにした。
- [x] npm package から意図的に外す MOD canonical paths は Android source と tests tree だけであることを contract で固定した。これにより新しい MOD 正本が npm package に入らない場合は明示分類が必要になる。
- [x] cURL release archive から意図的に外す MOD canonical paths は Android source、tests tree、GitHub/development metadata、package lock/workflow/archive metadata だけであることを contract で固定した。
- [x] Python compatibility wrapper は `shogunate_mod/` 委譲 bootstrap だけに限定し、wrapper 側に関数・クラス実装や追加 import が戻らないことを AST contract で固定した。
- [x] Shell / command / batch compatibility wrapper も薄い委譲入口として固定し、wrapper 側に shell 関数定義や batch label 実装が戻らないことを package distribution contract で固定した。
- [x] JavaScript compatibility wrapper も MOD npm CLI への bootstrap-only 委譲に限定し、root `bin/shogunate.js` へ JS 実装が戻らないことを package distribution contract で固定した。
- [x] Git 管理下の root code-like file は、`shogunate_mod/` 以外すべて manifest の current core touchpoint または compatibility wrapper で分類されることを package distribution contract で固定した。
- [x] 非 wrapper の root code-like touchpoint は、prepublish sync gate または generated instruction freshness guard のどちらかで守られることを package distribution contract で固定した。
- [x] npm package が MOD canonical source を file-level で収録し、Android/tests 以外の MOD 正本ファイルが npm package から欠落しないことを package distribution contract で固定した。
- [x] `shogunate_mod/README.md` の ownership boundary が Git 管理下の MOD top-level source directories と一致することを package distribution contract で固定した。
- [x] `upstream/main` が存在する開発 checkout では、upstream から変更された root code-like file も manifest の current core touchpoint または compatibility wrapper で分類されることを package distribution contract で固定した。
- [x] npm package と cURL release archive が旧 installer surface（`install.bat` / `install.sh` / `install.command` / legacy installer assets）を収録しないことを package distribution contract で固定した。
- [x] `upstream/main` が存在する開発 checkout では、`git merge-base --is-ancestor upstream/main HEAD` が通ることを package distribution contract で固定した。
- [x] package prepublish の directory sync gate を双方向化し、root 互換コピーが MOD 正本へ一致するだけでなく、MOD 正本に追加された instruction / skills / Cursor skills / templates / docs/codd / tests file が root 互換面へ出し忘れられた場合も release 前に止めるようにした。
- [x] Android source sync gate も双方向化し、root `android/` から MOD 正本への一致だけでなく、`shogunate_mod/mobile/android/` に追加された Android source が root Android Studio / Gradle 互換 working tree へ出し忘れられた場合も release 前に止めるようにした。Android SDK/cache/build/local/apk 生成物と `.gitignore` は従来どおり除外する。
- [x] OpenCode permission matrix の root 互換コピーと MOD 正本の同期 gate を強化し、差分として許すのは先頭 comment block だけにした。途中コメントや YAML 本体の drift は release 前に止める。
- [x] cURL release archive に入る `shogunate_mod/` 配下ファイルが manifest `canonical_paths` で説明できることを package distribution contract で固定した。これにより runtime archive へ未分類の MOD file が混入した場合も検出できる。
- [x] npm package に入る `shogunate_mod/` 配下ファイルも manifest `canonical_paths` で説明できることを package distribution contract で固定した。これにより npm runtime package へ未分類の MOD file が混入した場合も検出できる。
- [x] `package.json` / MOD `package.json` の `files` に直接列挙する `shogunate_mod/` file entry も manifest `canonical_paths` で説明できることを package distribution contract で固定した。これにより package metadata へ未分類の MOD file path を足す事故を検出できる。
- [x] `package.json` / MOD `package.json` の `files` に直接列挙する root file entry も manifest `current_core_touchpoints` または `compatibility_wrappers` で説明できることを package distribution contract で固定した。これにより npm package metadata へ未分類の root surface を足す事故を検出できる。
- [x] cURL release archive に入る root code-like file も manifest `current_core_touchpoints` または `compatibility_wrappers` で説明できることを package distribution contract で固定した。これにより release archive へ未分類の root code surface が混入した場合も検出できる。
- [x] npm package に入る root code-like file も manifest `current_core_touchpoints` または `compatibility_wrappers` で説明できることを package distribution contract で固定した。これにより npm package へ未分類の root code surface が混入した場合も検出できる。
- [x] source checkout runtime smoke を `shogunate_mod/runtime/source_smoke.sh` へ MOD 正本として追加し、detached worktree で root entrypoint から MOD runtime loader まで通るかを再現可能にした。
- [x] MOD-owned development command surface に `make source-smoke` を追加し、source checkout runtime smoke を root/MOD 同期済み Makefile から再実行できるようにした。
- [x] MOD-owned development command surface に `make package-check` を追加し、package prepublish gate を root/MOD 同期済み Makefile から再実行できるようにした。
- [x] MOD-owned development command surface に `make mod-check` を追加し、package prepublish gate / detached source runtime smoke / Android Gradle check を一括で再実行できるようにした。
- [x] MOD-owned development command surface に `make android-check` を追加し、root Android Gradle working tree から `testDebugUnitTest assembleDebug` を再実行できるようにした。
- [x] Pair server unit test の import 対象を root wrapper から `shogunate_mod/pair/server.py` へ切り替え、Android Pair の主要挙動を MOD 正本で直接検証するようにした。
- [x] runtime / Pair / update unit tests が root wrapper ではなく MOD 正本を import することを package distribution contract で固定した。
- [x] package prepublish gate に MOD behavior unit tests（Pair server / runtime blocker notice / update manager）を追加し、package surface だけでなく主要 MOD 正本の挙動も release 前に検証するようにした。
- [x] package prepublish gate に tracked shell / command / Python / JavaScript source syntax checks を追加し、MOD 正本と root wrapper の基本構文退行を release 前に検出できるようにした。
- [x] npm package / cURL release archive に入る `shogunate_mod/` top-level directory が `shogunate_mod/README.md` の Boundaries で説明されることを package distribution contract で固定した。これにより配布物へ新しい MOD directory を入れるとき、ownership 説明漏れを検出できる。
- [x] `shogunate_mod/README.md` の Boundaries に書いた MOD path が npm package / cURL release archive に実収録されるか、意図的除外として分類されることを package distribution contract で固定した。これにより README の ownership 説明と配布境界のズレを検出できる。
- [x] npm package と cURL release archive の `shogunate_mod/` top-level directory surface の差分が、npm だけに残す GitHub metadata 用 `github/` だけであることを package distribution contract で固定した。これにより両配布経路の MOD directory 差分が意図なく広がる事故を検出できる。
- [x] npm package と cURL release archive の `shogunate_mod/` file surface の差分が、npm だけに残す GitHub/development/package metadata 7 files だけであることを package distribution contract で固定した。これにより両配布経路の MOD file 差分が意図なく広がる事故を検出できる。
- [x] npm package と cURL release archive の root compatibility surface の差分が、cURL だけに残す runtime default config / public philosophy doc 3 files だけであることを package distribution contract で固定した。これにより root 側互換面の配布差分が意図なく広がる事故を検出できる。
- [x] root に残る Shogunate-specific text surface が manifest で分類されるだけでなく、compatibility wrapper / generated target / prepublish sync / instruction source sync のいずれかの gate で守られることを package distribution contract で固定した。
- [x] root Shogunate-specific text surface の検出対象に公開/設計 docs を追加し、内部作業 docs を除外したうえで `docs/philosophy.md` / `docs/codd/` も MOD 正本同期 gate で守られることを package distribution contract で固定した。
- [x] 現HEADの一時 source checkout worktree で `shutsujin_departure.sh -s -c` を再スモークし、MOD runtime loader 経由の setup-only 起動、5 role pane、queue/runtime、dashboard、tmux project/runtime metadata が成立することを確認した。
- [x] manifest `current_core_touchpoints.next_step` が、同期 / 生成物 / root public metadata / archive 除外 / local runtime state のような操作可能な分類に落ちることを contract で固定した。曖昧な `where possible` 型の移行メモへ戻る場合は package distribution contract が検出する。
- [x] manifest `target_direction` を contract で固定し、本家風 runtime entrypoint は薄く保つ、Shogunate-only 実装は `shogunate_mod/` へ先に置く、歴史的 root path は互換 wrapper として残す、という core/MOD 境界方針が書き換わった場合に検出できるようにした。

## 判断

- `shutsujin_departure.sh` は `shogunate_mod/runtime/load.sh` と `run_shutsujin_departure "$@"` へ委譲する薄い互換入口になった。
- Shogunate-only runtime / Android / Gunkan / CLI 拡張は `shogunate_mod/` 側 canonical source に集約し、既存 cURL や旧 path は wrapper として残す。
- package release archive は prepublish 済みの checked-out `HEAD` から作成する。tag は release version として使うが、archive 作成前に tag commit と `HEAD` の一致を検証する。
- 本家追従の次段階は、root 互換入口を保ちながら `shogunate_mod/` 正本群の検証範囲を広げ、実 runtime / Android 実機確認を重ねること。

## 実装手順

1. `shogunate_mod/` に MOD manifest と README を置く。
2. `scripts/shogunate_package_bootstrap.sh` を互換 wrapper 化し、実装を `shogunate_mod/package/bootstrap.sh` に置く。
3. `scripts/shogunate_pair_server.py` を互換 wrapper 化し、実装を `shogunate_mod/pair/server.py` に置く。
4. `scripts/shell_aliases.sh` を互換 wrapper 化し、実装を `shogunate_mod/shell/aliases.sh` に置く。
5. `shogunate_mod/runtime/env.sh` を追加し、root entrypoint 側は helper 呼び出しへ寄せる。
6. Gunkan auditor helpers を `shogunate_mod/gunkan/` へ移し、旧 `scripts/gunkan_*` は wrapper とする。
7. branch policy helpers を `shogunate_mod/git/branch_policy.sh` へ移す。
8. Runtime daemon orchestration を `shogunate_mod/runtime/daemon.sh` へ移す。
9. Runtime blocked relay を `shogunate_mod/runtime/blocker.sh` へ移す。
10. Runtime blocker notice helper を `shogunate_mod/runtime/blocker_notice.py` へ移す。
11. Runtime prompt handling を `shogunate_mod/runtime/prompts.sh` へ移す。
12. Android compatibility session orchestration を `shogunate_mod/runtime/android_compat.sh` へ移す。
13. Startup bootstrap delivery を `shogunate_mod/runtime/bootstrap.sh` へ移す。
14. Runtime role directives / prompt label helpers を `shogunate_mod/runtime/directives.sh` へ移す。
15. Goza layout / pane resolve helpers を `shogunate_mod/runtime/goza.sh` へ移す。
16. CLI launch / startup-window helpers を `shogunate_mod/runtime/launch.sh` へ移す。
17. Startup lock / update check / logging / generated instruction ensure helpers を `shogunate_mod/runtime/startup.sh` へ移す。
18. Startup banner / runtime CLI metadata helpers を `shogunate_mod/runtime/banner.sh` / `agent_cli.sh` へ移す。
19. Runtime MOD source 群を `shogunate_mod/runtime/load.sh` へまとめる。
20. Project/session/settings/Python preflight initialization を `env.sh` / `daemon.sh` / `startup.sh` へ寄せる。
21. Cleanup / queue reset / dashboard init / runtime coordination state を `shogunate_mod/runtime/state.sh` へ移す。
22. Goza tmux session construction を `shogunate_mod/runtime/goza.sh` へ移す。
23. Agent CLI launch flow を `shogunate_mod/runtime/launch.sh` へ移す。
24. Watcher / bridge startup orchestration を `shogunate_mod/runtime/daemon.sh` へ移す。
25. Completion summary / Windows Terminal tab rendering を `shogunate_mod/runtime/summary.sh` へ移す。
26. Runtime lifecycle setup を `shogunate_mod/runtime/lifecycle.sh` へ移す。
27. Startup bootstrap delivery flow を `shogunate_mod/runtime/bootstrap.sh` へ移す。
28. Startup-time ASCII banner rendering を `shogunate_mod/runtime/banner.sh` へ移す。
29. Runtime options/help parsing を `shogunate_mod/runtime/options.sh` へ移す。
30. Runtime topology resolution を `shogunate_mod/runtime/topology.sh` へ移す。
31. Runtime departure entrypoint orchestration を `shogunate_mod/runtime/departure.sh` へ移す。
32. Runtime launcher shared setup を `shogunate_mod/runtime/launcher.sh` へ移す。
33. Runtime shell launchers を `shogunate_mod/runtime/runtime_launcher.sh` / `shutsujin_launcher.sh` へ移し、root `Shogunate-Runtime.sh` / `Shutsujin.sh` は互換 wrapper にする。
34. root `shutsujin_departure.sh` を互換 wrapper として manifest 上も整理し、残る core touchpoint を空にする。
35. npm package CLI implementation を `shogunate_mod/package/npm_cli.js` へ移し、root `bin/shogunate.js` は manifest 上の互換 wrapper として監査する。
36. inbox writer policy を `shogunate_mod/inbox/write.sh` へ移す。
37. watcher supervisor を `shogunate_mod/watcher/supervisor.sh` へ移す。
38. inbox watcher を `shogunate_mod/watcher/inbox_watcher.sh` へ移す。
39. CLI adapter を `shogunate_mod/cli/adapter.sh` へ移す。
40. inbox path normalization を `shogunate_mod/inbox/path.sh` へ移す。
41. ntfy auth helpers を `shogunate_mod/notify/ntfy_auth.sh` へ移す。
42. file-watch helpers を `shogunate_mod/watcher/file_watch.sh` へ移す。
43. agent status helpers を `shogunate_mod/status/agent_status.sh` へ移す。
44. agent status command を `shogunate_mod/status/command.sh` へ移す。
45. rate-limit status command を `shogunate_mod/status/ratelimit_check.sh` へ移す。
46. agent registry を `shogunate_mod/topology/agent_registry.sh` へ移す。
47. topology adapter を `shogunate_mod/topology/adapter.sh` へ移す。
48. Goza view attach/focus/autosave helpers を `shogunate_mod/view/` へ移し、root `scripts/goza_no_ma.sh` / `scripts/focus_agent_pane.sh` / `scripts/goza_layout_autosave.sh` は互換 wrapper にする。
49. ntfy send / listener scripts を `shogunate_mod/notify/` へ移し、root `scripts/ntfy.sh` / `scripts/ntfy_listener.sh` は互換 wrapper にする。
50. root `.gitignore` を `shogunate_mod/package/gitignore` の互換コピーとして同期し、manifest / prepublish / package distribution contract で固定する。
51. tests を MOD canonical source 前提へ更新する。
52. runtime bridge scripts / daemons と live CLI preference daemon を `shogunate_mod/runtime/` へ移し、root `scripts/*_bridge.py` / `scripts/*_daemon.sh` は互換 wrapper にする。
53. runtime live CLI preference sync を `shogunate_mod/runtime/sync_cli_preferences.py` へ移し、root `scripts/sync_runtime_cli_preferences.py` は互換 wrapper にする。
54. Antigravity keyring preflight を `shogunate_mod/cli/antigravity_keyring.sh` へ移し、root `scripts/ensure_antigravity_keyring.sh` は互換 wrapper にする。
55. CoDD check command を `shogunate_mod/gunkan/codd_check.sh` へ移し、root `scripts/codd_check.sh` は互換 wrapper にする。
56. interactive agent configurator を `shogunate_mod/configure/agents.sh` へ移し、root `scripts/configure_agents.sh` は互換 wrapper にする。
57. runtime role configurator を `shogunate_mod/configure/runtime_roles.py` へ移し、root `scripts/configure_runtime_roles.py` は互換 wrapper にする。
58. OpenCode/Kilo project config sync を `shogunate_mod/configure/sync_opencode_config.py` へ移し、root `scripts/sync_opencode_config.py` は互換 wrapper にする。
59. LocalAPI REPL を `shogunate_mod/localapi/repl.py` へ移し、root `scripts/localapi_repl.py` は互換 wrapper にする。
60. live CLI switch command を `shogunate_mod/configure/switch_cli.sh` へ移し、root `scripts/switch_cli.sh` は互換 wrapper にする。
61. generated instruction build / freshness guard を `shogunate_mod/instructions/` へ移し、root `scripts/build_instructions.sh` / `scripts/ensure_generated_instructions.sh` は互換 wrapper にする。
62. queue YAML slimming を `shogunate_mod/queue/` へ移し、root `scripts/slim_yaml.py` / `scripts/slim_yaml.sh` は互換 wrapper にする。
63. queue history book generation を `shogunate_mod/queue/history_book.sh` へ移し、root `scripts/history_book.sh` は互換 wrapper にする。
64. Claude Code SessionStart persona injection を `shogunate_mod/hooks/session_start_hook.sh` へ移し、root `scripts/session_start_hook.sh` は互換 wrapper にする。
65. Claude Code Stop hook inbox delivery / idle flag publication を `shogunate_mod/hooks/stop_hook_inbox.sh` へ移し、root `scripts/stop_hook_inbox.sh` は互換 wrapper にする。
66. shell rc alias installer を `shogunate_mod/shell/install_aliases.sh` へ移し、root `scripts/install_shell_aliases.sh` は互換 wrapper にする。
67. runtime MCP health check を `shogunate_mod/runtime/mcp_health_check.sh` へ移し、root `scripts/mcp_health_check.sh` は互換 wrapper にする。
68. Dashboard viewer を `shogunate_mod/view/dashboard_viewer.py` へ移し、root `scripts/dashboard-viewer.py` は互換 wrapper にする。
69. Runtime mux parity smoke を `shogunate_mod/runtime/mux_parity_smoke.sh` へ移し、root `scripts/mux_parity_smoke.sh` は互換 wrapper にする。
70. Branch policy cron setup を `shogunate_mod/git/setup_cron.sh` へ移し、root `scripts/setup_cron.sh` は互換 wrapper にする。
71. Update manager を `shogunate_mod/update/manager.py` へ移し、root `scripts/update_manager.py` は互換 wrapper にする。
72. Update shell commands を `shogunate_mod/update/` へ移し、root `scripts/upstream_sync.sh` / `scripts/stop_and_apply_update.sh` は互換 wrapper にする。
73. Branch deploy/maintenance commands を `shogunate_mod/git/` へ移し、root `scripts/pre_deploy_verify.sh` / `scripts/branch_drift_check.sh` / `scripts/auto_merge_short_lived.sh` は互換 wrapper にする。
74. Package prepublish check を `shogunate_mod/package/prepublish_check.sh` へ移し、root `scripts/prepublish_check.sh` は互換 wrapper にする。
75. Package first setup を `shogunate_mod/package/first_setup.sh` へ移し、root `first_setup.sh` は互換 wrapper にする。
76. Role configurator OS launchers を `shogunate_mod/configure/role_launcher.sh` へ集約し、root `Shogunate-Configure-Roles.*` は互換 wrapper にする。
77. Windows runtime launchers を `shogunate_mod/windows/` へ移し、root `Shogunate-Runtime.bat` / `Shutsujin.bat` は互換 wrapper にする。
78. macOS runtime launcher を `shogunate_mod/macos/runtime_launcher.command` へ移し、root `Shogunate-Runtime.command` は互換 wrapper にする。
79. Windows debug launchers を `shogunate_mod/windows/` へ移し、root `Shutsujin-Clean.bat` / `Shutsujin-Resume.bat` は互換 wrapper にする。
80. Legacy `setup.sh` の互換処理を `shogunate_mod/runtime/setup_compat.sh` へ置き、root `setup.sh` を互換 wrapper として manifest / package contract に追加する。
81. CoDD graph config を `shogunate_mod/gunkan/codd.yaml` へ置き、root `.codd/codd.yaml` と同期していることを contract test で固定する。
82. OpenCode permission matrix を `shogunate_mod/configure/opencode-permissions.yaml` へ置き、instruction builder は MOD 正本を既定で読み、root `config/opencode-permissions.yaml` と同期していることを contract test で固定する。
83. OpenCode TUI keybinding config を `shogunate_mod/configure/opencode-tui.json` へ置き、CLI adapter の `OPENCODE_TUI_CONFIG` を MOD 正本へ向け、root `config/opencode-tui.json` と同期していることを contract test で固定する。
84. ntfy auth sample config を `shogunate_mod/notify/ntfy_auth.env.sample` へ置き、root `config/ntfy_auth.env.sample` と同期していることを contract test で固定する。
85. default settings/projects templates を `shogunate_mod/configure/*.yaml.sample` へ置き、first setup は MOD template から root `config/*.yaml` を初回生成する。
86. role/common/CLI instruction source を `shogunate_mod/instructions/source/` へ置き、builder / freshness guard は MOD source を優先し、root `instructions/` 非生成 source と同期していることを contract test で固定する。
87. Claude auto-load source を `shogunate_mod/instructions/autoload/CLAUDE.md` へ置き、builder / freshness guard は MOD autoload source を優先し、root `CLAUDE.md` と同期していることを contract test で固定する。
88. GitHub Actions workflow source を `shogunate_mod/package/workflows/` へ置き、root `.github/workflows/` と同期していることを contract test で固定する。
89. Android app source を `shogunate_mod/mobile/android/` へ置き、root `android/` と同期していることを contract test で固定する。Android build/cache/local APK artifacts は runtime package から除外する。
90. npm package metadata を `shogunate_mod/package/package.json` / `package-lock.json` へ置き、root `package*.json` と同期していることを contract test で固定する。
91. package prepublish check で root `package*.json` と MOD 正本の同期を検査する。
92. generated instruction freshness guard が root `AGENTS.md`、`.github/copilot-instructions.md`、Kimi auto-load、OpenCode agent definitions も古さ検出対象にする。
93. `agents/default/` を Kimi K2 auto-load root 生成先として manifest の current core touchpoint に記録する。
94. package prepublish check で root 互換コピーと MOD 正本の同期を検査する対象を config / CoDD / instruction source / auto-load source に広げる。
95. package prepublish check で generated instruction freshness guard を実行し、release workflow で PyYAML を準備する。
96. PyYAML dependency file を `shogunate_mod/package/requirements.txt` へ置き、root `requirements.txt` と同期していることを contract test / prepublish gate で固定し、first setup と release workflow は MOD 正本を優先する。
97. Claude Code / Cursor skill sources を `shogunate_mod/skills/` へ置き、root `skills/` / `.cursor/skills/` と同期していることを contract test / prepublish gate で固定する。
98. 初回セットアップ用 runtime state template を `shogunate_mod/package/templates/` へ置き、root `memory/MEMORY.md.sample` / `saytask/streaks.yaml.sample` と同期していることを contract test / prepublish gate で固定する。
99. root `images/` と `reports/` を runtime package release archive から除外し、package contract test で固定する。
100. Karo integration/context templates を `shogunate_mod/templates/` へ置き、root `templates/` と同期していることを contract test / prepublish gate で固定する。
101. Claude Code hook/spinner settings を `shogunate_mod/hooks/claude_settings.json` へ置き、root `.claude/settings.json` と同期していることを contract test / prepublish gate で固定する。
102. context directory guide を `shogunate_mod/context/README.md` へ置き、root `context/README.md` と同期していることを contract test / prepublish gate で固定する。
103. OpenCode inbox state update tool を `shogunate_mod/opencode/tools/mark-as-read.ts` へ置き、root `.opencode/tools/mark-as-read.ts` と同期していることを contract test / prepublish gate で固定する。
104. Secret scanning config を `shogunate_mod/security/gitleaks.toml` へ置き、root `.gitleaks.toml` と同期していることを contract test / prepublish gate で固定する。
105. Development command surface を `shogunate_mod/development/Makefile` へ置き、root `Makefile` と同期していることを contract test / prepublish gate で固定する。
106. Release archive attribute rules を `shogunate_mod/package/gitattributes` へ置き、root `.gitattributes` と同期していることを contract test / prepublish gate で固定する。
107. Public README source を `shogunate_mod/docs/README.md` / `README_ja.md` へ置き、root README と同期していることを contract test / prepublish gate で固定する。
108. Public community docs を `shogunate_mod/docs/CHANGELOG.md` / `CONTRIBUTING.md` / `SECURITY.md` へ置き、root community docs と同期していることを contract test / prepublish gate で固定する。
109. GitHub funding metadata と development submodule metadata を `shogunate_mod/github/FUNDING.yml` / `shogunate_mod/development/gitmodules` へ置き、root `.github/FUNDING.yml` / `.gitmodules` と同期していることを contract test / prepublish gate で固定する。
110. Gunkan/CoDD design docs を `shogunate_mod/gunkan/docs/` へ置き、root `docs/codd/` と同期していることを contract test / prepublish gate で固定する。
111. Shogunate test tree を `shogunate_mod/tests/` へ置き、root `tests/` と同期していることを contract test / prepublish gate で固定する。
112. manifest の current_core_touchpoints は root `tests/` だけを示し、unit/E2E の詳細は canonical_paths と同期 contract で追跡する。
113. Shogunate test support files を `shogunate_mod/tests/specs/` / `fixtures/` / `helpers/` へ置き、root test support paths と同期していることを contract test / prepublish gate で固定する。
114. Shogunate unit test cases を `shogunate_mod/tests/unit/` へ置き、root unit test cases と同期していることを contract test / prepublish gate で固定する。
115. Shogunate E2E support files を `shogunate_mod/tests/e2e/` へ置き、root E2E support paths と同期していることを contract test / prepublish gate で固定する。
116. Shogunate E2E test cases を `shogunate_mod/tests/e2e/*.bats` へ置き、root E2E test cases と同期していることを contract test / prepublish gate で固定する。
117. `shogunate_mod/manifest.yaml` の `canonical_paths` と `compatibility_wrappers` が実在パスだけを指すことを contract test で固定する。
118. npm package `files` が MOD manifest `canonical_paths` の runtime package 対象をすべて収録し、`shogunate_mod/mobile/android/` / `shogunate_mod/tests/` を除外していることを contract test で固定する。
119. `current_core_touchpoints` が実在する root 互換 / generated / runtime-state surface だけを指すことを contract test で固定する。
120. manifest の全 `compatibility_wrappers` が MOD 実装へ委譲し、runtime npm package に収録されることを contract test で固定する。
121. `shogunate_mod/README.md` を MOD 境界説明の canonical path として manifest / package contract に追加する。
122. `shogunate_mod/manifest.yaml` 自身を canonical path に追加し、MOD 配下の正本ファイルがすべて manifest `canonical_paths` に覆われることを contract test で固定する。
123. `shogunate_mod/README.md` が正本ファイルを持つ top-level MOD ディレクトリをすべて説明していることを contract test で固定する。
124. package distribution contract test を prepublish gate から実行し、release 前に manifest/package 境界の退行を検出できるようにする。
125. package distribution contract test が generated instruction freshness guard と dirty-worktree gate より前に実行されることを contract test で固定する。
126. manifest の `current_core_touchpoints` が reason / next_step を持ち、`compatibility_wrappers` と重複しないことを contract test で固定する。
127. Windows role configurator launcher の実体を `shogunate_mod/windows/configure_roles.bat` へ移し、root `Shogunate-Configure-Roles.bat` を薄い互換 wrapper にする。
128. manifest の `compatibility_wrappers` が薄い入口に留まることを contract test で固定する。
129. package / Android / runtime checks を実行する。

## 検証

- PASS: `bash -n scripts/gunkan_emergency_stop.sh shogunate_mod/gunkan/emergency_stop.sh scripts/shogunate_package_bootstrap.sh shogunate_mod/package/bootstrap.sh scripts/shell_aliases.sh shogunate_mod/shell/aliases.sh shogunate_mod/runtime/env.sh Shogunate-Runtime.sh Shutsujin.sh shutsujin_departure.sh`
- PASS: `bash -n shutsujin_departure.sh shogunate_mod/runtime/blocker.sh shogunate_mod/runtime/daemon.sh shogunate_mod/runtime/env.sh`
- PASS: `bash -n shutsujin_departure.sh shogunate_mod/runtime/prompts.sh shogunate_mod/runtime/blocker.sh shogunate_mod/runtime/daemon.sh shogunate_mod/runtime/env.sh`
- PASS: `bash -n shutsujin_departure.sh shogunate_mod/runtime/android_compat.sh shogunate_mod/runtime/prompts.sh shogunate_mod/runtime/blocker.sh shogunate_mod/runtime/daemon.sh shogunate_mod/runtime/env.sh`
- PASS: `bash -n shutsujin_departure.sh shogunate_mod/runtime/bootstrap.sh shogunate_mod/runtime/android_compat.sh shogunate_mod/runtime/prompts.sh shogunate_mod/runtime/blocker.sh shogunate_mod/runtime/daemon.sh shogunate_mod/runtime/env.sh`
- PASS: `bash -n shutsujin_departure.sh shogunate_mod/runtime/directives.sh shogunate_mod/runtime/bootstrap.sh shogunate_mod/runtime/android_compat.sh shogunate_mod/runtime/prompts.sh shogunate_mod/runtime/blocker.sh shogunate_mod/runtime/daemon.sh shogunate_mod/runtime/env.sh`
- PASS: `bash -n shutsujin_departure.sh shogunate_mod/runtime/goza.sh shogunate_mod/runtime/directives.sh shogunate_mod/runtime/bootstrap.sh shogunate_mod/runtime/android_compat.sh shogunate_mod/runtime/prompts.sh shogunate_mod/runtime/blocker.sh shogunate_mod/runtime/daemon.sh shogunate_mod/runtime/env.sh`
- PASS: `bash -n shutsujin_departure.sh shogunate_mod/runtime/launch.sh shogunate_mod/runtime/goza.sh shogunate_mod/runtime/directives.sh shogunate_mod/runtime/bootstrap.sh shogunate_mod/runtime/android_compat.sh shogunate_mod/runtime/prompts.sh shogunate_mod/runtime/blocker.sh shogunate_mod/runtime/daemon.sh shogunate_mod/runtime/env.sh`
- PASS: `bash -n shutsujin_departure.sh shogunate_mod/runtime/load.sh shogunate_mod/runtime/banner.sh shogunate_mod/runtime/agent_cli.sh shogunate_mod/runtime/startup.sh shogunate_mod/runtime/launch.sh shogunate_mod/runtime/goza.sh shogunate_mod/runtime/directives.sh shogunate_mod/runtime/bootstrap.sh shogunate_mod/runtime/android_compat.sh shogunate_mod/runtime/prompts.sh shogunate_mod/runtime/blocker.sh shogunate_mod/runtime/daemon.sh shogunate_mod/runtime/env.sh`
- PASS: `bash -n shutsujin_departure.sh shogunate_mod/runtime/load.sh shogunate_mod/runtime/env.sh shogunate_mod/runtime/startup.sh shogunate_mod/runtime/daemon.sh` after moving project/session/settings/Python preflight initialization.
- PASS: `bash -n shutsujin_departure.sh shogunate_mod/runtime/load.sh shogunate_mod/runtime/state.sh shogunate_mod/runtime/env.sh shogunate_mod/runtime/startup.sh shogunate_mod/runtime/daemon.sh` after moving cleanup / queue reset / dashboard init / runtime coordination state.
- PASS: `bash -n shutsujin_departure.sh shogunate_mod/runtime/goza.sh shogunate_mod/runtime/load.sh` after moving Goza tmux session construction.
- PASS: `bash -n shutsujin_departure.sh shogunate_mod/runtime/launch.sh shogunate_mod/runtime/load.sh` after moving agent CLI launch flow.
- PASS: `bash -n shutsujin_departure.sh shogunate_mod/runtime/daemon.sh shogunate_mod/runtime/launch.sh shogunate_mod/runtime/load.sh` after moving watcher / bridge startup orchestration.
- PASS: `bash -n shutsujin_departure.sh shogunate_mod/runtime/summary.sh shogunate_mod/runtime/load.sh` after moving completion summary / Windows Terminal tab rendering.
- PASS: `bash -n shutsujin_departure.sh shogunate_mod/runtime/lifecycle.sh shogunate_mod/runtime/load.sh` after moving runtime lifecycle setup.
- PASS: `bash -n shutsujin_departure.sh shogunate_mod/runtime/banner.sh shogunate_mod/runtime/bootstrap.sh shogunate_mod/runtime/lifecycle.sh shogunate_mod/runtime/load.sh` after moving startup bootstrap delivery flow and startup-time ASCII banner rendering.
- PASS: `bash -n shutsujin_departure.sh shogunate_mod/runtime/options.sh shogunate_mod/runtime/topology.sh shogunate_mod/runtime/load.sh` after moving runtime options/help parsing and topology resolution.
- PASS: `bash -n shutsujin_departure.sh shogunate_mod/runtime/departure.sh shogunate_mod/runtime/load.sh` after moving runtime departure entrypoint orchestration.
- PASS: `bash -n Shogunate-Runtime.sh Shutsujin.sh shogunate_mod/runtime/launcher.sh` after moving runtime launcher shared setup.
- PASS: `node --check bin/shogunate.js && node --check shogunate_mod/package/npm_cli.js` after moving npm package CLI implementation.
- PASS: `node bin/shogunate.js --help` after moving npm package CLI implementation.
- PASS: `bash -n scripts/inbox_write.sh shogunate_mod/inbox/write.sh` after moving inbox writer policy.
- PASS: `bash scripts/inbox_write.sh` and `bash shogunate_mod/inbox/write.sh` both returned the expected usage error without writing an inbox message after moving inbox writer policy.
- PASS: `bash -n scripts/watcher_supervisor.sh shogunate_mod/watcher/supervisor.sh` after moving watcher supervisor.
- PASS: `bash scripts/watcher_supervisor.sh --print-watchers` after moving watcher supervisor.
- PASS: `bash -n scripts/inbox_watcher.sh shogunate_mod/watcher/inbox_watcher.sh scripts/watcher_supervisor.sh shogunate_mod/watcher/supervisor.sh` after moving inbox watcher.
- PASS: `__INBOX_WATCHER_TESTING__=1 bash -c 'source scripts/inbox_watcher.sh; declare -F process_unread_once >/dev/null; declare -F send_wakeup >/dev/null'` verified the compatibility wrapper can still be sourced by tests/tools.
- PASS: `bash -n lib/cli_adapter.sh shogunate_mod/cli/adapter.sh shogunate_mod/watcher/inbox_watcher.sh shogunate_mod/watcher/supervisor.sh` after moving CLI adapter.
- PASS: `bash -c 'source lib/cli_adapter.sh; declare -F build_cli_command >/dev/null; declare -F build_cli_command_with_type >/dev/null'` verified the compatibility wrapper can still be sourced.
- PASS: `bash -n lib/file_watch.sh shogunate_mod/watcher/file_watch.sh lib/inbox_path.sh shogunate_mod/inbox/path.sh shogunate_mod/watcher/inbox_watcher.sh shogunate_mod/watcher/supervisor.sh shogunate_mod/runtime/departure.sh` after moving file-watch and inbox path helpers.
- PASS: `bash -c 'source lib/file_watch.sh; declare -F file_watch_backend >/dev/null; source lib/inbox_path.sh; declare -F ensure_local_inbox_dir >/dev/null'` verified both compatibility wrappers can still be sourced.
- PASS: Python syntax parse for Gunkan wrappers, Gunkan MOD scripts, Pair wrapper, and Pair MOD server.
- PASS: `PYTHONDONTWRITEBYTECODE=1 python3 -m unittest tests.unit.test_package_distribution tests.unit.test_shogunate_pair_server`
- PASS: `PYTHONDONTWRITEBYTECODE=1 python3 -m unittest tests.unit.test_package_distribution tests.unit.test_runtime_blocker_notice`
- PASS: `PYTHONDONTWRITEBYTECODE=1 python3 -m unittest tests.unit.test_package_distribution`
- PASS: `PYTHONDONTWRITEBYTECODE=1 bats tests/unit/test_gunkan_audit.bats tests/unit/test_runtime_launchers.bats tests/unit/test_shell_aliases.bats`
- PASS: `bats tests/unit/test_mux_parity.bats`
- PASS: `bats tests/unit/test_mux_parity.bats tests/unit/test_send_wakeup.bats`
- PASS: `bats tests/unit/test_mux_parity.bats tests/unit/test_runtime_launchers.bats tests/unit/test_shell_aliases.bats tests/unit/test_send_wakeup.bats`
- PASS: `bats tests/unit/test_mux_parity.bats tests/unit/test_runtime_launchers.bats tests/unit/test_shell_aliases.bats tests/unit/test_send_wakeup.bats` after moving runtime directives and Goza helpers.
- PASS: `bats tests/unit/test_mux_parity.bats tests/unit/test_runtime_launchers.bats tests/unit/test_shell_aliases.bats tests/unit/test_send_wakeup.bats` after moving CLI launch helpers.
- PASS: `bats tests/unit/test_mux_parity.bats tests/unit/test_runtime_launchers.bats tests/unit/test_shell_aliases.bats tests/unit/test_send_wakeup.bats` after moving startup/banner/agent-cli helpers and adding runtime MOD loader.
- PASS: `bats tests/unit/test_mux_parity.bats tests/unit/test_runtime_launchers.bats tests/unit/test_shell_aliases.bats tests/unit/test_send_wakeup.bats` after moving cleanup / queue reset / dashboard init / runtime coordination state.
- PASS: `bats tests/unit/test_mux_parity.bats tests/unit/test_runtime_launchers.bats tests/unit/test_shell_aliases.bats tests/unit/test_send_wakeup.bats` after moving Goza tmux session construction.
- PASS: `bats tests/unit/test_mux_parity.bats` after moving agent CLI launch flow.
- PASS: `bats tests/unit/test_mux_parity.bats tests/unit/test_runtime_launchers.bats` after moving watcher / bridge startup orchestration.
- PASS: `bats tests/unit/test_mux_parity.bats tests/unit/test_runtime_launchers.bats tests/unit/test_shell_aliases.bats tests/unit/test_send_wakeup.bats` after moving agent CLI launch flow and watcher / bridge startup orchestration.
- PASS: `bats tests/unit/test_mux_parity.bats tests/unit/test_runtime_launchers.bats` after moving completion summary / Windows Terminal tab rendering.
- PASS: `bats tests/unit/test_mux_parity.bats tests/unit/test_runtime_launchers.bats tests/unit/test_shell_aliases.bats tests/unit/test_send_wakeup.bats` after moving completion summary / Windows Terminal tab rendering.
- PASS: `bats tests/unit/test_mux_parity.bats` after moving runtime lifecycle setup.
- PASS: `bats tests/unit/test_mux_parity.bats tests/unit/test_runtime_launchers.bats tests/unit/test_shell_aliases.bats tests/unit/test_send_wakeup.bats` after moving runtime lifecycle setup.
- PASS: `bats tests/unit/test_mux_parity.bats tests/unit/test_runtime_launchers.bats tests/unit/test_shell_aliases.bats tests/unit/test_send_wakeup.bats` after moving startup bootstrap delivery flow and startup-time ASCII banner rendering.
- PASS: `bats tests/unit/test_mux_parity.bats tests/unit/test_runtime_launchers.bats tests/unit/test_shell_aliases.bats tests/unit/test_send_wakeup.bats` after moving runtime options/help parsing and topology resolution.
- PASS: `bats tests/unit/test_mux_parity.bats tests/unit/test_runtime_launchers.bats tests/unit/test_shell_aliases.bats tests/unit/test_send_wakeup.bats` after moving runtime departure entrypoint orchestration.
- PASS: `bats tests/unit/test_mux_parity.bats tests/unit/test_runtime_launchers.bats tests/unit/test_shell_aliases.bats tests/unit/test_send_wakeup.bats` after fixing the npm runtime launch chain.
- PASS: `bats tests/unit/test_runtime_launchers.bats` after moving runtime launcher shared setup.
- PASS: `bats tests/unit/test_mux_parity.bats tests/unit/test_runtime_launchers.bats tests/unit/test_shell_aliases.bats tests/unit/test_send_wakeup.bats` after moving runtime launcher shared setup.
- PASS: `bats tests/unit/test_runtime_launchers.bats tests/unit/test_shell_aliases.bats` after moving npm package CLI implementation.
- PASS: `bats tests/unit/test_send_wakeup.bats` after moving inbox writer policy.
- PASS: `bats tests/unit/test_mux_parity.bats tests/unit/test_send_wakeup.bats` after moving inbox writer policy.
- PASS: `bats tests/unit/test_watcher_supervisor.bats tests/unit/test_agent_registry.bats` after moving watcher supervisor.
- PASS: `bats tests/unit/test_mux_parity.bats tests/unit/test_send_wakeup.bats` after moving watcher supervisor.
- PASS: `bats tests/unit/test_send_wakeup.bats tests/unit/test_idle_flag.bats tests/agent_selfwatch.bats` after moving inbox watcher.
- PASS: `bats tests/unit/test_mux_parity.bats tests/unit/test_watcher_supervisor.bats tests/unit/test_agent_registry.bats` after moving inbox watcher.
- PASS: `bats tests/unit/test_cli_adapter.bats` after moving CLI adapter.
- PASS: `bats tests/unit/test_switch_cli.bats tests/unit/test_dynamic_model_routing.bats` after moving CLI adapter.
- PASS: `bats tests/unit/test_watcher_supervisor.bats tests/unit/test_mux_parity.bats tests/unit/test_runtime_launchers.bats` after moving CLI adapter.
- PASS: `bats tests/unit/test_file_watch.bats tests/unit/test_watcher_supervisor.bats tests/unit/test_mux_parity.bats` after moving file-watch and inbox path helpers.
- PASS: `bats tests/unit/test_send_wakeup.bats tests/unit/test_idle_flag.bats tests/agent_selfwatch.bats` after moving file-watch and inbox path helpers.
- PASS: `bash -n lib/agent_registry.sh shogunate_mod/topology/agent_registry.sh lib/topology_adapter.sh shogunate_mod/topology/adapter.sh shogunate_mod/watcher/supervisor.sh shogunate_mod/runtime/departure.sh shogunate_mod/runtime/topology.sh` after moving agent registry and topology adapter helpers.
- PASS: `bash -c 'source lib/agent_registry.sh; declare -F agent_registry_agents >/dev/null; source lib/topology_adapter.sh; declare -F topology_resolve_karo_agents >/dev/null'` verified the topology compatibility wrappers can still be sourced.
- PASS: `bats tests/unit/test_agent_registry.bats tests/unit/test_configure_agents.bats tests/unit/test_mux_parity.bats tests/unit/test_watcher_supervisor.bats` after moving agent registry and topology adapter helpers.
- PASS: `bash -n scripts/goza_no_ma.sh scripts/focus_agent_pane.sh scripts/goza_layout_autosave.sh shogunate_mod/view/goza_no_ma.sh shogunate_mod/view/focus_agent_pane.sh shogunate_mod/view/goza_layout_autosave.sh shogunate_mod/runtime/goza.sh shogunate_mod/runtime/state.sh` after moving Goza view attach/focus/autosave helpers.
- PASS: `PYTHONDONTWRITEBYTECODE=1 python3 -m unittest tests.unit.test_package_distribution` after moving Goza view attach/focus/autosave helpers.
- PASS: `bats tests/unit/test_mux_parity.bats tests/unit/test_shell_aliases.bats` after moving Goza view attach/focus/autosave helpers.
- PASS: root and MOD `goza_no_ma.sh --help`, root `focus_agent_pane.sh` usage error, and root `goza_layout_autosave.sh` usage error all preserved expected output after wrapper conversion.
- PASS: `npm pack --dry-run --json` includes root Goza view helper wrappers, `shogunate_mod/view/` canonical helpers, and `shogunate_mod/manifest.yaml`.
- PASS: `bash -n scripts/configure_agents.sh shogunate_mod/configure/agents.sh` after moving the interactive agent configurator.
- PASS: `PYTHONDONTWRITEBYTECODE=1 python3 -m py_compile scripts/configure_runtime_roles.py shogunate_mod/configure/runtime_roles.py` after moving the runtime role configurator.
- PASS: `bats tests/unit/test_configure_agents.bats tests/unit/test_configure_runtime_roles.bats` after moving configure helpers.
- PASS: `PYTHONDONTWRITEBYTECODE=1 python3 -m unittest tests.unit.test_package_distribution` after moving configure helpers.
- PASS: `npm pack --dry-run --json` includes `scripts/configure_agents.sh`, `scripts/configure_runtime_roles.py`, `shogunate_mod/configure/agents.sh`, `shogunate_mod/configure/runtime_roles.py`, and `shogunate_mod/manifest.yaml`.
- PASS: `bats tests/unit/test_mux_parity.bats` after moving configure helpers.
- PASS: `git diff --check` after moving configure helpers.
- PASS: `bash -n scripts/switch_cli.sh shogunate_mod/configure/switch_cli.sh` after moving the live CLI switch command.
- PASS: `bats tests/unit/test_switch_cli.bats tests/unit/test_dynamic_model_routing.bats` after moving the live CLI switch command.
- PASS: `PYTHONDONTWRITEBYTECODE=1 python3 -m unittest tests.unit.test_package_distribution` after moving the live CLI switch command.
- PASS: `npm pack --dry-run --json` includes `scripts/switch_cli.sh`, `shogunate_mod/configure/switch_cli.sh`, and `shogunate_mod/manifest.yaml`.
- PASS: `bats tests/unit/test_mux_parity.bats` after moving the live CLI switch command.
- PASS: `git diff --check` after moving the live CLI switch command.
- PASS: `PYTHONDONTWRITEBYTECODE=1 python3 -m py_compile scripts/sync_opencode_config.py shogunate_mod/configure/sync_opencode_config.py` after moving OpenCode/Kilo config sync.
- PASS: `bats tests/unit/test_sync_opencode_config.bats` after moving OpenCode/Kilo config sync.
- PASS: `PYTHONDONTWRITEBYTECODE=1 python3 -m unittest tests.unit.test_package_distribution` after moving OpenCode/Kilo config sync.
- PASS: `npm pack --dry-run --json` includes all `scripts/configure*`, `scripts/sync_opencode_config.py`, `scripts/switch_cli.sh`, and `shogunate_mod/configure/*`.
- PASS: `bats tests/unit/test_mux_parity.bats` after moving OpenCode/Kilo config sync.
- PASS: `git diff --check` after moving OpenCode/Kilo config sync.
- PASS: `bash -n scripts/build_instructions.sh scripts/ensure_generated_instructions.sh shogunate_mod/instructions/build.sh shogunate_mod/instructions/ensure_generated.sh` after moving generated instruction build helpers.
- PASS: `bash scripts/build_instructions.sh` after moving generated instruction build helpers.
- PASS: `bash shogunate_mod/instructions/ensure_generated.sh` rebuilt once when MOD source mtime was newer, then `bash scripts/ensure_generated_instructions.sh` reported generated instruction files up to date.
- PASS: `bats tests/unit/test_build_system.bats` after moving generated instruction build helpers.
- PASS: `PYTHONDONTWRITEBYTECODE=1 python3 -m unittest tests.unit.test_package_distribution` after moving generated instruction build helpers.
- PASS: `npm pack --dry-run --json` includes `scripts/build_instructions.sh`, `scripts/ensure_generated_instructions.sh`, `shogunate_mod/instructions/build.sh`, `shogunate_mod/instructions/ensure_generated.sh`, and `shogunate_mod/manifest.yaml`.
- PASS: `git diff --check` after moving generated instruction build helpers.
- PASS: `bash -n lib/agent_status.sh shogunate_mod/status/agent_status.sh shogunate_mod/watcher/inbox_watcher.sh shogunate_mod/cli/adapter.sh scripts/agent_status.sh` after moving agent status helpers.
- PASS: `bash -c 'source lib/agent_status.sh; declare -F agent_is_busy_check >/dev/null; declare -F get_pane_state_label >/dev/null'` verified the agent status compatibility wrapper can still be sourced.
- PASS: `bats tests/unit/test_send_wakeup.bats tests/unit/test_idle_flag.bats tests/agent_selfwatch.bats tests/unit/test_cli_adapter.bats tests/unit/test_watcher_supervisor.bats tests/unit/test_mux_parity.bats` after moving agent status helpers.
- PASS: `bash -n scripts/agent_status.sh shogunate_mod/status/command.sh shogunate_mod/status/agent_status.sh shogunate_mod/cli/adapter.sh shogunate_mod/topology/agent_registry.sh` after moving the agent status command.
- PASS: `bash scripts/agent_status.sh --help` and `bash shogunate_mod/status/command.sh --help` after moving the agent status command.
- PASS: `bats tests/unit/test_send_wakeup.bats tests/unit/test_idle_flag.bats tests/unit/test_cli_adapter.bats tests/unit/test_mux_parity.bats` after moving the agent status command.
- PASS: `bash -n lib/ntfy_auth.sh shogunate_mod/notify/ntfy_auth.sh scripts/ntfy.sh scripts/ntfy_listener.sh` after moving ntfy auth helpers.
- PASS: `bash -c 'source lib/ntfy_auth.sh; declare -F ntfy_get_auth_args >/dev/null; declare -F ntfy_validate_topic >/dev/null'` verified the ntfy auth compatibility wrapper can still be sourced.
- PASS: `bats tests/unit/test_ntfy_auth.bats tests/unit/test_ntfy_ack.bats` after moving ntfy auth helpers.
- PASS: `bash -n scripts/ntfy.sh scripts/ntfy_listener.sh shogunate_mod/notify/send.sh shogunate_mod/notify/listener.sh shogunate_mod/runtime/lifecycle.sh` after moving ntfy send/listener scripts.
- PASS: `PYTHONDONTWRITEBYTECODE=1 python3 -m unittest tests.unit.test_package_distribution` after moving ntfy send/listener scripts.
- PASS: `bats tests/unit/test_ntfy_auth.bats tests/unit/test_ntfy_ack.bats tests/unit/test_mux_parity.bats` after moving ntfy send/listener scripts.
- PASS: `npm pack --dry-run --json` includes `scripts/ntfy.sh`, `scripts/ntfy_listener.sh`, `shogunate_mod/notify/send.sh`, `shogunate_mod/notify/listener.sh`, `shogunate_mod/notify/ntfy_auth.sh`, and `shogunate_mod/manifest.yaml`.
- PASS: `bash -n scripts/ratelimit_check.sh shogunate_mod/status/ratelimit_check.sh` after moving the rate-limit status command.
- PASS: `bats tests/unit/test_ratelimit_check.bats` after moving the rate-limit status command.
- PASS: `PYTHONDONTWRITEBYTECODE=1 python3 -m unittest tests.unit.test_package_distribution` after moving the rate-limit status command.
- PASS: `npm pack --dry-run --json` includes `scripts/ratelimit_check.sh`, `shogunate_mod/status/ratelimit_check.sh`, and `shogunate_mod/manifest.yaml`.
- PASS: `bats tests/unit/test_mux_parity.bats` after moving the rate-limit status command.
- PASS: `git diff --check` after moving the rate-limit status command.
- PASS: `bash -n scripts/slim_yaml.sh shogunate_mod/queue/slim_yaml.sh` and `PYTHONDONTWRITEBYTECODE=1 python3 -m py_compile scripts/slim_yaml.py shogunate_mod/queue/slim_yaml.py` after moving queue YAML slimming.
- PASS: `bats tests/unit/test_slim_yaml.bats` after moving queue YAML slimming.
- PASS: `PYTHONDONTWRITEBYTECODE=1 python3 -m unittest tests.unit.test_package_distribution` after moving queue YAML slimming.
- PASS: `npm pack --dry-run --json` includes `scripts/slim_yaml.py`, `scripts/slim_yaml.sh`, `shogunate_mod/queue/slim_yaml.py`, `shogunate_mod/queue/slim_yaml.sh`, and `shogunate_mod/manifest.yaml`.
- PASS: `bats tests/unit/test_mux_parity.bats` after moving queue YAML slimming.
- PASS: `git diff --check` after moving queue YAML slimming.
- PASS: `bash -n scripts/stop_hook_inbox.sh shogunate_mod/hooks/stop_hook_inbox.sh` after moving the Claude Code Stop hook.
- PASS: `bats tests/unit/test_stop_hook.bats tests/unit/test_idle_flag.bats` after moving the Claude Code Stop hook.
- PASS: `PYTHONDONTWRITEBYTECODE=1 python3 -m unittest tests.unit.test_package_distribution` after moving the Claude Code Stop hook.
- PASS: `npm pack --dry-run --json` includes `scripts/stop_hook_inbox.sh`, `shogunate_mod/hooks/stop_hook_inbox.sh`, and `shogunate_mod/manifest.yaml`.
- PASS: `bats tests/unit/test_mux_parity.bats` after moving the Claude Code Stop hook.
- PASS: `git diff --check` after moving the Claude Code Stop hook.
- PASS: `bash -n scripts/session_start_hook.sh shogunate_mod/hooks/session_start_hook.sh scripts/stop_hook_inbox.sh shogunate_mod/hooks/stop_hook_inbox.sh` after moving the Claude Code SessionStart hook.
- PASS: `bats tests/unit/test_session_start_hook.bats tests/unit/test_stop_hook.bats tests/unit/test_idle_flag.bats` after moving the Claude Code SessionStart hook.
- PASS: `PYTHONDONTWRITEBYTECODE=1 python3 -m unittest tests.unit.test_package_distribution` after moving the Claude Code SessionStart hook.
- PASS: `npm pack --dry-run --json` includes `scripts/session_start_hook.sh`, `scripts/stop_hook_inbox.sh`, `shogunate_mod/hooks/session_start_hook.sh`, `shogunate_mod/hooks/stop_hook_inbox.sh`, and `shogunate_mod/manifest.yaml`.
- PASS: `bats tests/unit/test_mux_parity.bats` after moving the Claude Code SessionStart hook.
- PASS: `git diff --check` after moving the Claude Code SessionStart hook.
- PASS: `PYTHONDONTWRITEBYTECODE=1 python3 -m py_compile scripts/localapi_repl.py shogunate_mod/localapi/repl.py` after moving the LocalAPI REPL.
- PASS: `printf ':help\n:exit\n' | python3 scripts/localapi_repl.py` after moving the LocalAPI REPL.
- PASS: `bats tests/unit/test_cli_adapter.bats` after moving the LocalAPI REPL.
- PASS: `PYTHONDONTWRITEBYTECODE=1 python3 -m unittest tests.unit.test_package_distribution` after moving the LocalAPI REPL.
- PASS: `npm pack --dry-run --json` includes `scripts/localapi_repl.py`, `shogunate_mod/localapi/repl.py`, and `shogunate_mod/manifest.yaml`.
- PASS: `bats tests/unit/test_mux_parity.bats` after moving the LocalAPI REPL.
- PASS: `git diff --check` after moving the LocalAPI REPL.
- PASS: `bash -n scripts/history_book.sh scripts/mcp_health_check.sh shogunate_mod/queue/history_book.sh shogunate_mod/runtime/mcp_health_check.sh shogunate_mod/runtime/lifecycle.sh shogunate_mod/inbox/write.sh` after moving history book and MCP health helpers.
- PASS: `bash scripts/history_book.sh` generated `queue/history/rekishi_book.md` after moving history book.
- PASS: `bash scripts/mcp_health_check.sh` safely skipped when the legacy `multiagent` tmux session was absent after moving MCP health.
- PASS: `PYTHONDONTWRITEBYTECODE=1 python3 -m unittest tests.unit.test_package_distribution` after moving history book and MCP health helpers.
- PASS: `npm pack --dry-run --json` includes `scripts/history_book.sh`, `scripts/mcp_health_check.sh`, `shogunate_mod/queue/history_book.sh`, `shogunate_mod/runtime/mcp_health_check.sh`, and `shogunate_mod/manifest.yaml`.
- PASS: `bats tests/unit/test_mux_parity.bats` after moving history book and MCP health helpers.
- PASS: `git diff --check` after moving history book and MCP health helpers.
- PASS: `bash -n scripts/ensure_antigravity_keyring.sh shogunate_mod/cli/antigravity_keyring.sh shogunate_mod/cli/adapter.sh` after moving Antigravity keyring preflight.
- PASS: `SHOGUNATE_ANTIGRAVITY_KEYRING_CHECK=0 bash scripts/ensure_antigravity_keyring.sh` after moving Antigravity keyring preflight.
- PASS: `bats tests/unit/test_cli_adapter.bats` after moving Antigravity keyring preflight while preserving the compatibility wrapper path in generated command text.
- PASS: `PYTHONDONTWRITEBYTECODE=1 python3 -m unittest tests.unit.test_package_distribution` after moving Antigravity keyring preflight.
- PASS: `npm pack --dry-run --json` includes `scripts/ensure_antigravity_keyring.sh`, `shogunate_mod/cli/antigravity_keyring.sh`, and `shogunate_mod/manifest.yaml`.
- PASS: `bats tests/unit/test_mux_parity.bats` after moving Antigravity keyring preflight.
- PASS: `git diff --check` after moving Antigravity keyring preflight.
- PASS: `bash -n scripts/codd_check.sh shogunate_mod/gunkan/codd_check.sh` after moving the CoDD check command.
- PASS: `bash scripts/codd_check.sh help` after moving the CoDD check command.
- PASS: `PYTHONDONTWRITEBYTECODE=1 python3 -m unittest tests.unit.test_package_distribution` after moving the CoDD check command.
- PASS: `bats tests/unit/test_mux_parity.bats` after moving the CoDD check command.
- PASS: `npm pack --dry-run --json` includes `scripts/codd_check.sh`, `shogunate_mod/gunkan/codd_check.sh`, and `shogunate_mod/manifest.yaml`.
- PASS: `git diff --check` after moving the CoDD check command.
- NOT RUN: `bash scripts/codd_check.sh install|scan|validate|gunkan`; these may install packages or run external CoDD scans, so this checkpoint limited validation to syntax/help/package compatibility.
- PASS: `bash -n scripts/install_shell_aliases.sh shogunate_mod/shell/install_aliases.sh` after moving the shell rc alias installer.
- PASS: `bats tests/unit/test_shell_aliases.bats tests/unit/test_mux_parity.bats` after moving the shell rc alias installer.
- PASS: `PYTHONDONTWRITEBYTECODE=1 python3 -m unittest tests.unit.test_package_distribution` after moving the shell rc alias installer.
- PASS: `npm pack --dry-run --json` includes `scripts/install_shell_aliases.sh`, `shogunate_mod/shell/install_aliases.sh`, and `shogunate_mod/manifest.yaml`.
- PASS: `git diff --check` after moving the shell rc alias installer.
- PASS: `bash -n lib/branch_policy.sh shogunate_mod/git/branch_policy.sh scripts/pre_deploy_verify.sh scripts/branch_drift_check.sh scripts/auto_merge_short_lived.sh` after moving branch policy helpers.
- PASS: `bash -c 'source lib/branch_policy.sh; declare -F branch_policy_query >/dev/null; declare -F branch_policy_is_git_repo >/dev/null'` verified the branch policy compatibility wrapper can still be sourced.
- PASS: `bats tests/unit/test_branch_policy_scripts.bats` after moving branch policy helpers.
- PASS: `PYTHONDONTWRITEBYTECODE=1 python3 -m py_compile scripts/runtime_blocker_notice.py shogunate_mod/runtime/blocker_notice.py` after moving the runtime blocker notice helper.
- PASS: `PYTHONDONTWRITEBYTECODE=1 python3 -m unittest tests.unit.test_runtime_blocker_notice tests.unit.test_package_distribution` after moving the runtime blocker notice helper.
- PASS: `bash -n shogunate_mod/runtime/blocker.sh shogunate_mod/watcher/inbox_watcher.sh scripts/runtime_blocker_notice.py` after moving the runtime blocker notice helper.
- PASS: old wrapper and MOD canonical CLI smoke both updated a temporary dashboard and normalized the runtime-blocked notice detail.
- PASS: `bash -n scripts/runtime_cli_pref_daemon.sh shogunate_mod/runtime/cli_pref_daemon.sh scripts/shogun_to_karo_bridge_daemon.sh shogunate_mod/runtime/shogun_to_karo_bridge_daemon.sh scripts/karo_done_to_shogun_bridge_daemon.sh shogunate_mod/runtime/karo_done_to_shogun_bridge_daemon.sh shogunate_mod/runtime/daemon.sh shogunate_mod/runtime/state.sh` after moving runtime bridge daemons and the live CLI preference daemon.
- PASS: `PYTHONDONTWRITEBYTECODE=1 python3 -m unittest tests.unit.test_package_distribution` after moving runtime bridge daemons and the live CLI preference daemon.
- PASS: `bats tests/unit/test_runtime_cli_pref_daemon.bats tests/unit/test_bridge_daemons.bats tests/unit/test_mux_parity.bats` after moving runtime bridge daemons and the live CLI preference daemon.
- PASS: `npm pack --dry-run --json` includes the old daemon wrappers, MOD daemon canonical files, and `shogunate_mod/manifest.yaml`.
- PASS: `PYTHONDONTWRITEBYTECODE=1 python3 -m py_compile scripts/shogun_to_karo_bridge.py shogunate_mod/runtime/shogun_to_karo_bridge.py scripts/karo_done_to_shogun_bridge.py shogunate_mod/runtime/karo_done_to_shogun_bridge.py` after moving the runtime bridge Python scripts.
- PASS: `bats tests/unit/test_shogun_to_karo_bridge.bats tests/unit/test_karo_done_to_shogun_bridge.bats tests/unit/test_bridge_daemons.bats tests/unit/test_mux_parity.bats` after moving the runtime bridge Python scripts.
- PASS: direct MOD smoke for `shogunate_mod/runtime/shogun_to_karo_bridge.py` and `shogunate_mod/runtime/karo_done_to_shogun_bridge.py` sent one temporary inbox message each and updated the matching bridge state files.
- PASS: `npm pack --dry-run --json` includes the old bridge wrappers, MOD bridge canonical files, old daemon wrappers, MOD daemon canonical files, and `shogunate_mod/manifest.yaml`.
- PASS: `PYTHONDONTWRITEBYTECODE=1 python3 -m py_compile scripts/sync_runtime_cli_preferences.py shogunate_mod/runtime/sync_cli_preferences.py` after moving the runtime live CLI preference sync.
- PASS: `bats tests/unit/test_sync_runtime_cli_preferences.bats tests/unit/test_runtime_cli_pref_daemon.bats tests/unit/test_mux_parity.bats` after moving the runtime live CLI preference sync.
- PASS: direct MOD smoke for `shogunate_mod/runtime/sync_cli_preferences.py` updated a temporary settings file from a fake Shogunate tmux pane and wrote `runtime_cli_prefs.tsv`.
- PASS: `npm pack --dry-run --json` includes `scripts/sync_runtime_cli_preferences.py`, `shogunate_mod/runtime/sync_cli_preferences.py`, `scripts/runtime_cli_pref_daemon.sh`, `shogunate_mod/runtime/cli_pref_daemon.sh`, and `shogunate_mod/manifest.yaml`.
- PASS: `bats tests/unit/test_mux_parity.bats tests/unit/test_send_wakeup.bats` after moving the runtime blocker notice helper.
- PASS: `PYTHONDONTWRITEBYTECODE=1 python3 -m unittest tests.unit.test_package_distribution tests.unit.test_shogunate_pair_server tests.unit.test_runtime_blocker_notice`
- PASS: `PYTHONDONTWRITEBYTECODE=1 python3 -m unittest tests.unit.test_package_distribution tests.unit.test_shogunate_pair_server tests.unit.test_runtime_blocker_notice` after moving runtime directives and Goza helpers.
- PASS: `PYTHONDONTWRITEBYTECODE=1 python3 -m unittest tests.unit.test_package_distribution tests.unit.test_shogunate_pair_server tests.unit.test_runtime_blocker_notice` after moving CLI launch helpers.
- PASS: `PYTHONDONTWRITEBYTECODE=1 python3 -m unittest tests.unit.test_package_distribution tests.unit.test_shogunate_pair_server tests.unit.test_runtime_blocker_notice` after moving startup/banner/agent-cli helpers and adding runtime MOD loader.
- PASS: `PYTHONDONTWRITEBYTECODE=1 python3 -m unittest tests.unit.test_package_distribution tests.unit.test_shogunate_pair_server tests.unit.test_runtime_blocker_notice` after moving cleanup / queue reset / dashboard init / runtime coordination state.
- PASS: `PYTHONDONTWRITEBYTECODE=1 python3 -m unittest tests.unit.test_package_distribution tests.unit.test_shogunate_pair_server tests.unit.test_runtime_blocker_notice` after moving Goza tmux session construction.
- PASS: `PYTHONDONTWRITEBYTECODE=1 python3 -m unittest tests.unit.test_package_distribution tests.unit.test_shogunate_pair_server tests.unit.test_runtime_blocker_notice` after moving agent CLI launch flow and watcher / bridge startup orchestration.
- PASS: `PYTHONDONTWRITEBYTECODE=1 python3 -m unittest tests.unit.test_package_distribution tests.unit.test_shogunate_pair_server tests.unit.test_runtime_blocker_notice` after moving completion summary / Windows Terminal tab rendering.
- PASS: `PYTHONDONTWRITEBYTECODE=1 python3 -m unittest tests.unit.test_package_distribution tests.unit.test_shogunate_pair_server tests.unit.test_runtime_blocker_notice` after moving runtime lifecycle setup.
- PASS: `PYTHONDONTWRITEBYTECODE=1 python3 -m unittest tests.unit.test_package_distribution tests.unit.test_shogunate_pair_server tests.unit.test_runtime_blocker_notice` after moving startup bootstrap delivery flow and startup-time ASCII banner rendering.
- PASS: `PYTHONDONTWRITEBYTECODE=1 python3 -m unittest tests.unit.test_package_distribution tests.unit.test_shogunate_pair_server tests.unit.test_runtime_blocker_notice` after moving runtime options/help parsing and topology resolution.
- PASS: `PYTHONDONTWRITEBYTECODE=1 python3 -m unittest tests.unit.test_package_distribution tests.unit.test_shogunate_pair_server tests.unit.test_runtime_blocker_notice` after moving runtime departure entrypoint orchestration.
- PASS: `PYTHONDONTWRITEBYTECODE=1 python3 -m unittest tests.unit.test_package_distribution tests.unit.test_shogunate_pair_server tests.unit.test_runtime_blocker_notice` after fixing the npm runtime launch chain.
- PASS: `PYTHONDONTWRITEBYTECODE=1 python3 -m unittest tests.unit.test_package_distribution` after moving runtime launcher shared setup.
- PASS: `PYTHONDONTWRITEBYTECODE=1 python3 -m unittest tests.unit.test_package_distribution tests.unit.test_shogunate_pair_server tests.unit.test_runtime_blocker_notice` after moving runtime launcher shared setup.
- PASS: `PYTHONDONTWRITEBYTECODE=1 python3 -m unittest tests.unit.test_package_distribution` after moving npm package CLI implementation.
- PASS: `PYTHONDONTWRITEBYTECODE=1 python3 -m unittest tests.unit.test_package_distribution tests.unit.test_shogunate_pair_server tests.unit.test_runtime_blocker_notice` after moving npm package CLI implementation.
- PASS: `PYTHONDONTWRITEBYTECODE=1 python3 -m unittest tests.unit.test_package_distribution` after moving inbox writer policy.
- PASS: `PYTHONDONTWRITEBYTECODE=1 python3 -m unittest tests.unit.test_package_distribution tests.unit.test_shogunate_pair_server tests.unit.test_runtime_blocker_notice` after moving inbox writer policy.
- PASS: `PYTHONDONTWRITEBYTECODE=1 python3 -m unittest tests.unit.test_package_distribution` after moving watcher supervisor.
- PASS: `PYTHONDONTWRITEBYTECODE=1 python3 -m unittest tests.unit.test_package_distribution tests.unit.test_shogunate_pair_server tests.unit.test_runtime_blocker_notice` after moving watcher supervisor.
- PASS: `bash scripts/shogunate_package_bootstrap.sh --help` returned the MOD package installer help through the compatibility wrapper.
- PASS: `npm pack --dry-run --json` includes `shogunate_mod/gunkan/`, `package/`, `pair/server.py`, `runtime/env.sh`, and `shell/aliases.sh`; no `__pycache__` or `.pyc` entries.
- PASS: `npm pack --dry-run --json` includes `shogunate_mod/runtime/blocker.sh`, `daemon.sh`, and `env.sh`; no `__pycache__` or `.pyc` entries.
- PASS: `npm pack --dry-run --json` includes `shogunate_mod/runtime/bootstrap.sh`, `android_compat.sh`, `blocker.sh`, `daemon.sh`, `env.sh`, and `prompts.sh`; no `__pycache__` or `.pyc` entries.
- PASS: `npm pack --dry-run --json` includes `shogunate_mod/runtime/directives.sh`; no `__pycache__` or `.pyc` entries.
- PASS: `npm pack --dry-run --json` includes `shogunate_mod/runtime/goza.sh`; no `__pycache__` or `.pyc` entries.
- PASS: `npm pack --dry-run --json` includes `shogunate_mod/runtime/launch.sh`; no `__pycache__` or `.pyc` entries.
- PASS: `npm pack --dry-run --json` includes `shogunate_mod/runtime/load.sh`, `banner.sh`, `agent_cli.sh`, and `startup.sh`; no `__pycache__` or `.pyc` entries.
- PASS: `npm pack --dry-run --json` includes `shogunate_mod/runtime/state.sh`; no `__pycache__` or `.pyc` entries.
- PASS: `npm pack --dry-run --json` includes `shogunate_mod/runtime/goza.sh`; no `__pycache__` or `.pyc` entries after moving Goza tmux session construction.
- PASS: `npm pack --dry-run --json` includes `shogunate_mod/runtime/launch.sh`, `daemon.sh`, `goza.sh`, and `load.sh`; no `__pycache__` or `.pyc` entries after moving agent CLI launch flow and watcher / bridge startup orchestration.
- PASS: `npm pack --dry-run --json` includes `shogunate_mod/runtime/summary.sh`; no `__pycache__` or `.pyc` entries after moving completion summary / Windows Terminal tab rendering.
- PASS: `npm pack --dry-run --json` includes `shogunate_mod/runtime/lifecycle.sh`; no `__pycache__` or `.pyc` entries after moving runtime lifecycle setup.
- PASS: `npm pack --dry-run --json` includes `shogunate_mod/runtime/banner.sh`, `bootstrap.sh`, `lifecycle.sh`, and `load.sh`; no `__pycache__` or `.pyc` entries after moving startup bootstrap delivery flow and startup-time ASCII banner rendering.
- PASS: `npm pack --dry-run --json` includes `shogunate_mod/runtime/options.sh`, `topology.sh`, `load.sh`, and `shogunate_mod/manifest.yaml`; no `__pycache__` or `.pyc` entries after moving runtime options/help parsing and topology resolution.
- PASS: `npm pack --dry-run --json` includes `shogunate_mod/runtime/departure.sh`, `load.sh`, and `shogunate_mod/manifest.yaml`; no `__pycache__` or `.pyc` entries after moving runtime departure entrypoint orchestration.
- PASS: `npm pack --dry-run --json` includes `Shogunate-Runtime.sh`, `Shutsujin.sh`, `shutsujin_departure.sh`, `shogunate_mod/runtime/departure.sh`, and `load.sh`; no `__pycache__` or `.pyc` entries after fixing the npm runtime launch chain.
- PASS: `npm pack --dry-run --json` includes `Shogunate-Runtime.sh`, `Shutsujin.sh`, `shutsujin_departure.sh`, `shogunate_mod/runtime/launcher.sh`, `shogunate_mod/runtime/departure.sh`, and `load.sh` after moving runtime launcher shared setup.
- PASS: `npm pack --dry-run --json` includes `bin/shogunate.js`, `shogunate_mod/package/npm_cli.js`, `shogunate_mod/package/bootstrap.sh`, and `shogunate_mod/manifest.yaml` after moving npm package CLI implementation.
- PASS: `npm pack --dry-run --json` includes `scripts/inbox_write.sh`, `shogunate_mod/inbox/write.sh`, and `shogunate_mod/manifest.yaml` after moving inbox writer policy.
- PASS: `npm pack --dry-run --json` includes `scripts/watcher_supervisor.sh`, `shogunate_mod/watcher/supervisor.sh`, and `shogunate_mod/manifest.yaml` after moving watcher supervisor.
- PASS: `npm pack --dry-run --json` includes `scripts/inbox_watcher.sh`, `shogunate_mod/watcher/inbox_watcher.sh`, `scripts/watcher_supervisor.sh`, `shogunate_mod/watcher/supervisor.sh`, and `shogunate_mod/manifest.yaml`; no `__pycache__` or `.pyc` entries after moving inbox watcher.
- PASS: `git status --short --untracked-files=all` shows `shogunate_mod/manifest.yaml` and `shogunate_mod/watcher/inbox_watcher.sh` after adding the `.gitignore` whitelist.
- PASS: `npm pack --dry-run --json` includes `lib/cli_adapter.sh`, `shogunate_mod/cli/adapter.sh`, `shogunate_mod/manifest.yaml`, and no `__pycache__` or `.pyc` entries after moving CLI adapter.
- PASS: `git status --short --untracked-files=all` shows `shogunate_mod/cli/adapter.sh` after adding the `.gitignore` whitelist.
- PASS: `npm pack --dry-run --json` includes `lib/file_watch.sh`, `lib/inbox_path.sh`, `shogunate_mod/watcher/file_watch.sh`, `shogunate_mod/inbox/path.sh`, and `shogunate_mod/manifest.yaml`; no `__pycache__` or `.pyc` entries after moving file-watch and inbox path helpers.
- PASS: `npm pack --dry-run --json` includes `lib/agent_registry.sh`, `lib/topology_adapter.sh`, `shogunate_mod/topology/agent_registry.sh`, `shogunate_mod/topology/adapter.sh`, and `shogunate_mod/manifest.yaml` after moving topology helpers.
- PASS: `npm pack --dry-run --json` includes `lib/agent_status.sh`, `shogunate_mod/status/agent_status.sh`, and `shogunate_mod/manifest.yaml`; no `__pycache__` / `.pyc` / `.pyo` entries after moving agent status helpers.
- PASS: `npm pack --dry-run --json` includes `scripts/agent_status.sh`, `shogunate_mod/status/command.sh`, `shogunate_mod/status/agent_status.sh`, and `shogunate_mod/manifest.yaml`; no `__pycache__` / `.pyc` / `.pyo` entries after moving the agent status command.
- PASS: `npm pack --dry-run --json` includes `lib/ntfy_auth.sh`, `shogunate_mod/notify/ntfy_auth.sh`, and `shogunate_mod/manifest.yaml`; no `__pycache__` / `.pyc` / `.pyo` entries after moving ntfy auth helpers.
- PASS: `npm pack --dry-run --json` includes `lib/branch_policy.sh`, `shogunate_mod/git/branch_policy.sh`, and `shogunate_mod/manifest.yaml`; no `__pycache__` / `.pyc` / `.pyo` entries after moving branch policy helpers.
- PASS: `npm pack --dry-run --json` includes `scripts/runtime_blocker_notice.py`, `shogunate_mod/runtime/blocker_notice.py`, and `shogunate_mod/manifest.yaml`; no `__pycache__` / `.pyc` / `.pyo` entries after moving the runtime blocker notice helper.
- PASS: Android `./gradlew testDebugUnitTest`.
- PASS: Android `./gradlew testDebugUnitTest` after moving runtime bootstrap.
- PASS: Android `./gradlew testDebugUnitTest` after moving runtime directives.
- PASS: Android `./gradlew testDebugUnitTest` after moving Goza helpers.
- PASS: Android `./gradlew testDebugUnitTest` after moving CLI launch helpers.
- PASS: Android `./gradlew testDebugUnitTest` after moving startup/banner/agent-cli helpers and adding runtime MOD loader.
- PASS: Android `./gradlew assembleDebug`.
- PASS: ADB install and launch on device `661ecd40`; `com.shogun.android/.MainActivity` became resumed.
- PASS: Pair server real-process `/health` smoke through `scripts/shogunate_pair_server.py` wrapper.
- PASS: isolated runtime smoke with `./Shogunate-Runtime.sh --project <repo>/runtime_sandboxes/.../project --clean --no-attach -s`; tmux metadata matched target project and runtime root.
- PASS: isolated runtime smoke after moving runtime daemon/blocker helpers; tmux metadata matched target project and runtime root.
- PASS: isolated runtime smoke after moving startup bootstrap helpers; tmux session metadata matched target project and runtime root.
- PASS: isolated runtime smoke after moving runtime directive helpers; tmux session metadata matched target project and runtime root.
- PASS: isolated runtime smoke after moving Goza helpers; tmux session metadata matched target project/runtime root and the Goza window had 8 panes.
- PASS: isolated runtime smoke after moving CLI launch helpers; tmux session metadata matched target project/runtime root and the Goza window had 8 panes.
- PASS: isolated runtime smoke after moving startup/banner/agent-cli helpers and adding runtime MOD loader; `./Shogunate-Runtime.sh --project <repo>/runtime_sandboxes/.../project --clean --no-attach -s` created the project-specific tmux session and the Goza window had 8 panes.
- PASS: isolated runtime smoke after moving project/session/settings/Python preflight initialization; `./Shogunate-Runtime.sh --project <repo>/runtime_sandboxes/.../project --clean --no-attach -s` created the project-specific tmux session and the Goza window had 8 panes.
- PASS: isolated runtime smoke after moving cleanup / queue reset / dashboard init / runtime coordination state; `./Shogunate-Runtime.sh --project <repo>/runtime_sandboxes/.../project --clean --no-attach -s` created the project-specific tmux session, the Goza window had 8 panes, and queue/runtime plus dashboard files were present.
- PASS: isolated runtime smoke after moving Goza tmux session construction; `./Shogunate-Runtime.sh --project <repo>/runtime_sandboxes/.../project --clean --no-attach -s` created the project-specific tmux session and the Goza window had 8 panes.
- PASS: isolated runtime smoke after moving agent CLI launch flow and watcher / bridge startup orchestration; `./Shogunate-Runtime.sh --project <repo>/runtime_sandboxes/.../project --clean --no-attach -s` created the project-specific tmux session and the Goza window had 8 panes.
- PASS: isolated runtime smoke after moving completion summary / Windows Terminal tab rendering; `./Shogunate-Runtime.sh --project <repo>/runtime_sandboxes/.../project --clean --no-attach -s` created the project-specific tmux session, the Goza window had 8 panes, and the completion summary appeared in the startup log.
- PASS: isolated runtime smoke after moving runtime lifecycle setup; `./Shogunate-Runtime.sh --project <repo>/runtime_sandboxes/.../project --clean --no-attach -s` created the project-specific tmux session, the Goza window had 8 panes, `queue/runtime/agent_cli.tsv` existed, and the ntfy skip message appeared in the startup log.
- PASS: isolated runtime smoke after moving startup bootstrap delivery flow and startup-time ASCII banner rendering; `./Shogunate-Runtime.sh --project <repo>/runtime_sandboxes/.../project --clean --no-attach -s` created the project-specific tmux session, the Goza window had 8 panes, the completion summary appeared, and the startup log contained the ninja ASCII banner heading.
- PASS: isolated runtime smoke after moving runtime options/help parsing and topology resolution; `./Shogunate-Runtime.sh --project <repo>/runtime_sandboxes/.../project --clean --no-attach -s` created the project-specific tmux session and the Goza window had 8 panes.
- PASS: isolated runtime smoke after moving runtime departure entrypoint orchestration; `./Shogunate-Runtime.sh --project <repo>/runtime_sandboxes/.../project --clean --no-attach -s` created the project-specific tmux session and the Goza window had 8 panes.
- PASS: isolated runtime smoke after fixing the npm runtime launch chain; `./Shogunate-Runtime.sh --project <repo>/runtime_sandboxes/.../project --clean --no-attach -s` created the project-specific tmux session and the Goza window had 8 panes.
- PASS: `./Shogunate-Runtime.sh --help` and `./Shutsujin.sh --help` after moving runtime launcher shared setup.
- NOT RUN: isolated runtime smoke after moving runtime launcher shared setup. The previous launch-chain smoke already passed; this change only shares launcher preflight, and this checkpoint avoided creating an extra tmux runtime session because this repo's AGENTS rule forbids direct `tmux kill-session` cleanup.
- PASS: `git diff --check`.
- PASS: `git diff --check` after moving startup bootstrap helpers.
- PASS: `git diff --check` after moving runtime directive helpers.
- PASS: `git diff --check` after moving Goza helpers.
- PASS: `git diff --check` after moving CLI launch helpers.
- PASS: `git diff --check` after moving agent CLI launch flow and watcher / bridge startup orchestration.
- PASS: `git diff --check` after moving runtime launcher shared setup.
- PASS: `git diff --check` after moving npm package CLI implementation.
- PASS: `git diff --check` after moving inbox writer policy.
- PASS: `git diff --check` after moving watcher supervisor.
- PASS: `git diff --check` after moving inbox watcher.
- PASS: `git diff --check` after moving CLI adapter.
- PASS: `git diff --check` after moving file-watch and inbox path helpers.
- PASS: `git diff --check` after moving agent registry and topology adapter helpers.
- PASS: `git diff --check` after moving agent status helpers.
- PASS: `git diff --check` after moving the agent status command.
- PASS: `git diff --check` after moving ntfy auth helpers.
- PASS: `git diff --check` after moving branch policy helpers.
- PASS: `git diff --check` after moving the runtime blocker notice helper.
- PASS: `PYTHONDONTWRITEBYTECODE=1 python3 -m py_compile scripts/dashboard-viewer.py shogunate_mod/view/dashboard_viewer.py` after moving the dashboard viewer.
- PASS: direct import smoke confirmed `shogunate_mod/view/dashboard_viewer.py` resolves the repository root while inside a git checkout.
- PASS: `PYTHONDONTWRITEBYTECODE=1 python3 -m unittest tests.unit.test_package_distribution` after moving the dashboard viewer.
- PASS: `npm pack --dry-run --json` includes `scripts/dashboard-viewer.py`, `shogunate_mod/view/dashboard_viewer.py`, and `shogunate_mod/manifest.yaml`.
- PASS: `git diff --check` after moving the dashboard viewer.
- PASS: `bash -n scripts/mux_parity_smoke.sh shogunate_mod/runtime/mux_parity_smoke.sh` after moving the mux parity smoke command.
- PASS: `bash scripts/mux_parity_smoke.sh --dry-run` preserved the historical dry-run output through the compatibility wrapper.
- PASS: `bats tests/unit/test_mux_parity_smoke.bats` after moving the mux parity smoke command.
- PASS: `PYTHONDONTWRITEBYTECODE=1 python3 -m unittest tests.unit.test_package_distribution` after moving the mux parity smoke command.
- PASS: `npm pack --dry-run --json` includes `scripts/mux_parity_smoke.sh`, `shogunate_mod/runtime/mux_parity_smoke.sh`, and `shogunate_mod/manifest.yaml`.
- PASS: `git diff --check` after moving the mux parity smoke command.
- PASS: `bash -n scripts/setup_cron.sh shogunate_mod/git/setup_cron.sh` after moving the branch policy cron setup command.
- PASS: `bash scripts/setup_cron.sh --print` preserved the managed cron block through the compatibility wrapper.
- PASS: `PYTHONDONTWRITEBYTECODE=1 python3 -m unittest tests.unit.test_package_distribution` after moving the branch policy cron setup command.
- PASS: `npm pack --dry-run --json` includes `scripts/setup_cron.sh`, `shogunate_mod/git/setup_cron.sh`, and `shogunate_mod/manifest.yaml`.
- PASS: `git diff --check` after moving the branch policy cron setup command.
- PASS: `PYTHONDONTWRITEBYTECODE=1 python3 -m py_compile scripts/update_manager.py shogunate_mod/update/manager.py` after moving the update manager.
- PASS: `bash -n scripts/upstream_sync.sh scripts/stop_and_apply_update.sh shogunate_mod/update/upstream_sync.sh shogunate_mod/update/stop_and_apply_update.sh shogunate_mod/runtime/startup.sh shogunate_mod/package/bootstrap.sh` after moving update manager and update shell commands.
- PASS: `PYTHONDONTWRITEBYTECODE=1 python3 -m unittest tests.unit.test_update_manager tests.unit.test_package_distribution` after moving update manager and update shell commands.
- PASS: `python3 scripts/update_manager.py status` returned update status through the compatibility wrapper.
- PASS: `bash scripts/upstream_sync.sh --help` and `bash scripts/stop_and_apply_update.sh --help` returned help through the compatibility wrappers.
- PASS: `npm pack --dry-run --json` includes `scripts/update_manager.py`, `scripts/upstream_sync.sh`, `scripts/stop_and_apply_update.sh`, `shogunate_mod/update/manager.py`, `shogunate_mod/update/upstream_sync.sh`, `shogunate_mod/update/stop_and_apply_update.sh`, and `shogunate_mod/manifest.yaml`.
- PASS: `git diff --check` after moving update manager and update shell commands.
- NOT RUN: `bash scripts/upstream_sync.sh --dry-run`, `bash scripts/stop_and_apply_update.sh manual`, or `bash scripts/stop_and_apply_update.sh upstream-sync`; these perform upstream import/update flows or can stop tmux sessions, so this checkpoint limited validation to syntax, help/status, package inclusion, and unit coverage.
- PASS: `bash -n scripts/prepublish_check.sh shogunate_mod/package/prepublish_check.sh scripts/pre_deploy_verify.sh scripts/branch_drift_check.sh scripts/auto_merge_short_lived.sh shogunate_mod/git/pre_deploy_verify.sh shogunate_mod/git/branch_drift_check.sh shogunate_mod/git/auto_merge_short_lived.sh` after moving package prepublish and branch deploy/maintenance commands.
- PASS: `bats tests/unit/test_branch_policy_scripts.bats` after moving branch deploy/maintenance commands.
- PASS: `PYTHONDONTWRITEBYTECODE=1 python3 -m unittest tests.unit.test_package_distribution` after moving package prepublish and branch deploy/maintenance commands.
- PASS: `bash scripts/pre_deploy_verify.sh --help`, `bash scripts/branch_drift_check.sh --help`, and `bash scripts/auto_merge_short_lived.sh --help` returned help through compatibility wrappers.
- PASS: `npm pack --dry-run --json` includes `scripts/prepublish_check.sh`, `scripts/pre_deploy_verify.sh`, `scripts/branch_drift_check.sh`, `scripts/auto_merge_short_lived.sh`, `shogunate_mod/package/prepublish_check.sh`, `shogunate_mod/git/pre_deploy_verify.sh`, `shogunate_mod/git/branch_drift_check.sh`, `shogunate_mod/git/auto_merge_short_lived.sh`, and `shogunate_mod/manifest.yaml`.
- PASS: `git diff --check` after moving package prepublish and branch deploy/maintenance commands.
- NOT RUN: `bash scripts/prepublish_check.sh`; the current worktree is intentionally dirty during this MOD split, so the prepublish gate is expected to fail on dirty state. This checkpoint validated syntax, package inclusion, and wrapper delegation instead.
- PASS: `bash -n first_setup.sh shogunate_mod/package/first_setup.sh shogunate_mod/package/bootstrap.sh shogunate_mod/runtime/startup.sh shogunate_mod/update/stop_and_apply_update.sh` after moving package first setup.
- PASS: static grep confirmed `shogunate_mod/package/first_setup.sh` resolves the install root via `../..` and wrappers/update/bootstrap paths call the MOD canonical first setup.
- PASS: `PYTHONDONTWRITEBYTECODE=1 python3 -m unittest tests.unit.test_package_distribution` after moving package first setup.
- PASS: `bats tests/unit/test_mux_parity.bats` after moving package first setup.
- PASS: `npm pack --dry-run --json` includes `first_setup.sh`, `shogunate_mod/package/first_setup.sh`, package helpers, and `shogunate_mod/manifest.yaml`.
- PASS: `git diff --check` after moving package first setup.
- NOT RUN: `bash first_setup.sh` or `bash shogunate_mod/package/first_setup.sh`; first setup installs dependencies and edits shell/tmux/WSL configuration, so this checkpoint limited validation to syntax, root resolution, package inclusion, and regression tests.
- PASS: `bash -n setup.sh shogunate_mod/runtime/setup_compat.sh shogunate_mod/package/prepublish_check.sh scripts/prepublish_check.sh` after moving legacy setup compatibility behavior to MOD.
- PASS: `PYTHONDONTWRITEBYTECODE=1 python3 -m unittest tests.unit.test_package_distribution` after moving legacy setup compatibility behavior to MOD.
- PASS: direct `cmp` confirmed root `tests/` compatibility files still match `shogunate_mod/tests/`, excluding generated `__pycache__` / `.pyc` / `.pyo`.
- PASS: `npm pack --dry-run --json` parsed path check confirmed both `setup.sh` and `shogunate_mod/runtime/setup_compat.sh` are included, while `shogunate_mod/tests/` remains excluded.
- PASS: `git diff --check` after moving legacy setup compatibility behavior to MOD. Git warned that touched `.bat` files will be normalized to CRLF when Git next touches them, but the check exited 0.
- PASS: `bash -n Shogunate-Configure-Roles.sh Shogunate-Configure-Roles.command shogunate_mod/configure/role_launcher.sh` after moving role configurator OS launchers.
- PASS: `bats tests/unit/test_configure_role_launchers.bats` after moving role configurator OS launchers.
- PASS: `bash shogunate_mod/configure/role_launcher.sh --help` and `bash Shogunate-Configure-Roles.sh --help` returned argparse help through the MOD launcher.
- PASS: `npm pack --dry-run --json` includes `Shogunate-Configure-Roles.command`, `Shogunate-Configure-Roles.sh`, `shogunate_mod/configure/role_launcher.sh`, `shogunate_mod/configure/runtime_roles.py`, and `shogunate_mod/manifest.yaml`.
- PASS: `git diff --check` after moving role configurator OS launchers. Git warned that `Shogunate-Configure-Roles.bat` will be normalized to CRLF when Git next touches it, but the check exited 0.
- PASS: `bats tests/unit/test_runtime_launchers.bats tests/unit/test_configure_role_launchers.bats` after moving Windows runtime launchers.
- PASS: `PYTHONDONTWRITEBYTECODE=1 python3 -m unittest tests.unit.test_package_distribution` after moving Windows runtime launchers and adding package inclusion.
- PASS: `npm pack --dry-run --json` includes root Windows wrappers and `shogunate_mod/windows/runtime_launcher.bat` / `shogunate_mod/windows/shutsujin_launcher.bat`.
- PASS: `git diff --check` after moving Windows runtime launchers. Git warned that touched `.bat` files will be normalized to CRLF when Git next touches them, but the check exited 0.
- PASS: `bash -n Shogunate-Runtime.command shogunate_mod/macos/runtime_launcher.command` after moving the macOS runtime launcher.
- PASS: `bats tests/unit/test_runtime_launchers.bats` after moving the macOS runtime launcher.
- PASS: `PYTHONDONTWRITEBYTECODE=1 python3 -m unittest tests.unit.test_package_distribution` after moving the macOS runtime launcher.
- PASS: `npm pack --dry-run --json` includes `Shogunate-Runtime.command`, `shogunate_mod/macos/runtime_launcher.command`, and `shogunate_mod/manifest.yaml`.
- PASS: `bats tests/unit/test_runtime_launchers.bats` after moving Windows debug launchers.
- PASS: `PYTHONDONTWRITEBYTECODE=1 python3 -m unittest tests.unit.test_package_distribution` after moving Windows debug launchers and tracking `setup.sh`.
- PASS: `npm pack --dry-run --json` includes `Shutsujin-Clean.bat`, `Shutsujin-Resume.bat`, `shogunate_mod/windows/shutsujin_clean.bat`, `shogunate_mod/windows/shutsujin_resume.bat`, and `setup.sh`.
- PASS: `git diff --check` after moving macOS/runtime debug launchers and tracking `setup.sh`. Git warned that touched `.bat` files will be normalized to CRLF when Git next touches them, but the check exited 0.
- PASS: `bash -n Shogunate-Runtime.sh Shutsujin.sh shogunate_mod/runtime/runtime_launcher.sh shogunate_mod/runtime/shutsujin_launcher.sh shogunate_mod/runtime/launcher.sh` after moving runtime shell launchers.
- PASS: `./Shogunate-Runtime.sh --help` and `./Shutsujin.sh --help` returned the historical help through root wrappers after moving runtime shell launchers.
- PASS: `bats tests/unit/test_runtime_launchers.bats` after moving runtime shell launchers.
- PASS: `PYTHONDONTWRITEBYTECODE=1 python3 -m unittest tests.unit.test_package_distribution` after moving runtime shell launchers.
- PASS: `bats tests/unit/test_mux_parity.bats` after moving runtime shell launchers.
- PASS: `npm pack --dry-run --json` includes `Shogunate-Runtime.sh`, `Shutsujin.sh`, `shogunate_mod/runtime/launcher.sh`, `shogunate_mod/runtime/runtime_launcher.sh`, `shogunate_mod/runtime/shutsujin_launcher.sh`, and `shogunate_mod/manifest.yaml`.
- PASS: `git diff --check` after moving runtime shell launchers. Git warned that touched `.bat` files will be normalized to CRLF when Git next touches them, but the check exited 0.
- PASS: `PYTHONDONTWRITEBYTECODE=1 python3 -m unittest tests.unit.test_package_distribution` after moving `shutsujin_departure.sh` to manifest compatibility wrappers and clearing `current_core_touchpoints`.
- PASS: `bats tests/unit/test_mux_parity.bats tests/unit/test_runtime_launchers.bats` after clearing `current_core_touchpoints`.
- PASS: `npm pack --dry-run --json` includes `shutsujin_departure.sh`, `shogunate_mod/runtime/load.sh`, `shogunate_mod/runtime/departure.sh`, and `shogunate_mod/manifest.yaml` after clearing `current_core_touchpoints`.
- PASS: `git diff --check` after clearing `current_core_touchpoints`. Git warned that touched `.bat` files will be normalized to CRLF when Git next touches them, but the check exited 0.
- PASS: isolated root runtime smoke after moving runtime wrappers. `SHOGUNATE_SESSION_NAME=shogunate-mod-smoke-* GOZA_SESSION_NAME=shogunate-mod-smoke-* LEGACY_GOZA_SESSION_NAME=shogunate-mod-smoke-*-legacy RUNTIME_DAEMON_SESSION=goza-runtime-shogunate-mod-smoke-* ./Shogunate-Runtime.sh --project runtime_sandboxes/mod-split-smoke-*/project --clean --no-attach -s` created the unique tmux session through the root wrapper; `@shogunate_project_dir` matched the sandbox project, `@shogunate_runtime_dir` matched the repository root, and `shogunate-mod-smoke-*:goza` had 8 panes. The smoke-created tmux sessions were cleaned up.
- PASS: `PYTHONDONTWRITEBYTECODE=1 python3 -m unittest tests.unit.test_package_distribution` after adding MOD-owned CoDD config and manifest root-overlay touchpoint tracking.
- PASS: `npm pack --dry-run --json` includes `shogunate_mod/gunkan/codd.yaml` after adding the MOD-owned CoDD config.
- PASS: `bash -n scripts/build_instructions.sh shogunate_mod/instructions/build.sh` after making the instruction builder prefer the MOD-owned OpenCode permission matrix.
- PASS: `PYTHONDONTWRITEBYTECODE=1 python3 -m unittest tests.unit.test_package_distribution` after adding the MOD-owned OpenCode permission matrix and root compatibility sync contract.
- PASS: `npm pack --dry-run --json` includes `shogunate_mod/configure/opencode-permissions.yaml` after adding the MOD-owned OpenCode permission matrix.
- PASS: `bash -n shogunate_mod/cli/adapter.sh` after making the OpenCode launch command use the MOD-owned TUI config.
- PASS: `PYTHONDONTWRITEBYTECODE=1 python3 -m unittest tests.unit.test_package_distribution` after adding the MOD-owned OpenCode TUI config and root compatibility sync contract.
- PASS: `bats tests/unit/test_cli_adapter.bats` after switching `OPENCODE_TUI_CONFIG` to `shogunate_mod/configure/opencode-tui.json`.
- PASS: `npm pack --dry-run --json` includes `shogunate_mod/configure/opencode-tui.json` after adding the MOD-owned OpenCode TUI config.
- PASS: `PYTHONDONTWRITEBYTECODE=1 python3 -m unittest tests.unit.test_package_distribution` after adding the MOD-owned ntfy auth sample and root compatibility sync contract.
- PASS: `bats tests/unit/test_ntfy_auth.bats` after adding the MOD-owned ntfy auth sample.
- PASS: `npm pack --dry-run --json` includes `shogunate_mod/notify/ntfy_auth.env.sample` after adding the MOD-owned ntfy auth sample.
- PASS: `bash -n shogunate_mod/package/first_setup.sh` after switching first setup to MOD-owned default config templates.
- PASS: `PYTHONDONTWRITEBYTECODE=1 python3 -m unittest tests.unit.test_package_distribution` after adding MOD-owned default config templates.
- PASS: `npm pack --dry-run --json` includes `shogunate_mod/configure/settings.yaml.sample` and `shogunate_mod/configure/projects.yaml.sample`.
- PASS: `bash -n shogunate_mod/instructions/build.sh shogunate_mod/instructions/ensure_generated.sh scripts/build_instructions.sh scripts/ensure_generated_instructions.sh` after switching instruction build source to `shogunate_mod/instructions/source`.
- PASS: `bats tests/unit/test_build_system.bats` after switching instruction build source to `shogunate_mod/instructions/source`.
- PASS: `PYTHONDONTWRITEBYTECODE=1 python3 -m unittest tests.unit.test_package_distribution` after adding MOD-owned instruction source sync contract.
- PASS: `npm pack --dry-run --json` includes `shogunate_mod/instructions/source/**`.
- PASS: `bash -n shogunate_mod/instructions/build.sh shogunate_mod/instructions/ensure_generated.sh scripts/build_instructions.sh scripts/ensure_generated_instructions.sh` after switching auto-load generation source to `shogunate_mod/instructions/autoload/CLAUDE.md`.
- PASS: `bats tests/unit/test_build_system.bats` after switching auto-load generation source to `shogunate_mod/instructions/autoload/CLAUDE.md`.
- PASS: `PYTHONDONTWRITEBYTECODE=1 python3 -m unittest tests.unit.test_package_distribution` after adding MOD-owned auto-load Claude source sync contract.
- PASS: `npm pack --dry-run --json` includes `shogunate_mod/instructions/autoload/CLAUDE.md`.
- PASS: `git diff --check` after adding MOD-owned auto-load Claude source. Git warned that touched `.bat` files will be normalized to CRLF when Git next touches them, but the check exited 0.
- PASS: `PYTHONDONTWRITEBYTECODE=1 python3 -m unittest tests.unit.test_package_distribution` after adding MOD-owned GitHub Actions workflow source sync contract.
- PASS: `npm pack --dry-run --json` includes `shogunate_mod/package/workflows/package-release.yml` and `shogunate_mod/package/workflows/test.yml`.
- PASS: `git diff --check` after adding MOD-owned GitHub Actions workflow sources. Git warned that touched `.bat` files will be normalized to CRLF when Git next touches them, but the check exited 0.
- PASS: `PYTHONDONTWRITEBYTECODE=1 python3 -m unittest tests.unit.test_package_distribution` after adding MOD-owned Android source sync contract and Android artifact exclusion checks.
- PASS: `./gradlew tasks --quiet` from `android/` after adding MOD-owned Android source copy.
- PASS: `./gradlew testDebugUnitTest --quiet` from `android/` after adding MOD-owned Android source copy. Gradle warned about SDK XML version mismatch, but the command exited 0.
- PASS: `npm pack --dry-run --json` keeps `shogunate_mod/mobile/android/` out of the runtime npm package while other MOD runtime/package sources remain included.
- PASS: `git diff --check` after adding MOD-owned Android source copy. Git warned that touched `.bat` files will be normalized to CRLF when Git next touches them, but the check exited 0.
- PASS: `PYTHONDONTWRITEBYTECODE=1 python3 -m unittest tests.unit.test_package_distribution` after adding MOD-owned npm package metadata and lockfile sync contract.
- PASS: `npm pack --dry-run --json` includes `shogunate_mod/package/package.json` / `package-lock.json` and keeps `shogunate_mod/mobile/android/` out of the runtime npm package.
- PASS: `bash -n shogunate_mod/package/prepublish_check.sh scripts/prepublish_check.sh` after adding package metadata sync checks to the prepublish gate.
- PASS: `npm pack --dry-run --json` includes MOD package metadata and `shogunate_mod/package/prepublish_check.sh`, while keeping `shogunate_mod/mobile/android/` out of the runtime npm package after the prepublish gate update.
- PASS: `bash -n shogunate_mod/instructions/ensure_generated.sh scripts/ensure_generated_instructions.sh shogunate_mod/instructions/build.sh scripts/build_instructions.sh` after extending freshness targets to root auto-load and OpenCode generated outputs.
- PASS: `PYTHONDONTWRITEBYTECODE=1 python3 -m unittest tests.unit.test_package_distribution` after adding contract coverage for the extended freshness targets.
- PASS: `bash shogunate_mod/instructions/ensure_generated.sh` rebuilt generated files once, then a second run reported generated instruction files are up to date.
- PASS: `bats tests/unit/test_build_system.bats` after extending generated freshness targets.
- PASS: `npm pack --dry-run --json` includes MOD instruction source/guard files and keeps `shogunate_mod/mobile/android/` out of the runtime npm package after the freshness guard update.
- PASS: `bash -n shogunate_mod/package/prepublish_check.sh scripts/prepublish_check.sh` after extending prepublish sync checks to root config / CoDD / instruction source / auto-load compatibility copies.
- PASS: direct root/MOD compatibility sync checks for package metadata, Claude auto-load source, CoDD config, OpenCode TUI config, ntfy sample, OpenCode permission matrix non-comment body, and root non-generated instruction sources.
- PASS: `PYTHONDONTWRITEBYTECODE=1 python3 -m unittest tests.unit.test_package_distribution` after adding contract coverage for the expanded prepublish sync gate.
- PASS: `npm pack --dry-run --json` includes MOD sync sources and `shogunate_mod/package/prepublish_check.sh` after the expanded prepublish sync gate.
- PASS: `bash -n shogunate_mod/package/prepublish_check.sh scripts/prepublish_check.sh` after making prepublish call the generated instruction freshness guard.
- PASS: `bash shogunate_mod/instructions/ensure_generated.sh` reported generated instruction files are up to date after adding the prepublish freshness call.
- PASS: `PYTHONDONTWRITEBYTECODE=1 python3 -m unittest tests.unit.test_package_distribution` after adding release workflow PyYAML setup and `requirements.txt` package inclusion.
- PASS: `npm pack --dry-run --json` includes `requirements.txt`, `shogunate_mod/package/prepublish_check.sh`, and MOD freshness guard inputs after the release freshness gate update.
- PASS: `bash -n shogunate_mod/package/first_setup.sh first_setup.sh shogunate_mod/package/prepublish_check.sh scripts/prepublish_check.sh` after adding MOD-owned `shogunate_mod/package/requirements.txt`.
- PASS: `PYTHONDONTWRITEBYTECODE=1 python3 -m unittest tests.unit.test_package_distribution` after switching first setup / release workflow to prefer MOD-owned requirements.
- PASS: direct `cmp` checks confirmed root `requirements.txt`, package release workflow, and root/MOD package metadata are synchronized after adding MOD-owned requirements.
- PASS: `npm pack --dry-run --json` includes root and MOD requirements files and keeps `shogunate_mod/mobile/android/` out of the runtime npm package.
- PASS: `bash -n shogunate_mod/package/first_setup.sh first_setup.sh shogunate_mod/package/prepublish_check.sh scripts/prepublish_check.sh` after adding MOD-owned Claude/Cursor skill sources.
- PASS: `PYTHONDONTWRITEBYTECODE=1 python3 -m unittest tests.unit.test_package_distribution` after adding skill source sync contracts.
- PASS: direct `cmp` checks confirmed root `skills/` / `.cursor/skills/` compatibility copies match `shogunate_mod/skills/` canonical sources.
- PASS: `npm pack --dry-run --json` includes root compatibility skills and MOD skill sources while excluding `skills/.system/` and `shogunate_mod/mobile/android/`.
- PASS: `bash -n shogunate_mod/package/first_setup.sh first_setup.sh shogunate_mod/package/prepublish_check.sh scripts/prepublish_check.sh` after adding MOD-owned runtime state templates.
- PASS: `PYTHONDONTWRITEBYTECODE=1 python3 -m unittest tests.unit.test_package_distribution` after adding runtime state template sync contracts.
- PASS: `npm pack --dry-run --json` includes `memory/MEMORY.md.sample`, `saytask/streaks.yaml.sample`, and `shogunate_mod/package/templates/**`.
- PASS: direct normalized line-ending sync checks confirmed root `memory/MEMORY.md.sample` / `saytask/streaks.yaml.sample` compatibility copies match MOD templates.
- PASS: `git diff --check` after adding MOD-owned runtime state templates. Git warned that touched `.bat` files will be normalized to CRLF when Git next touches them, but the check exited 0.
- PASS: `PYTHONDONTWRITEBYTECODE=1 python3 -m unittest tests.unit.test_package_distribution` after adding release archive exclusion contracts for root `images/` and `reports/`.
- PASS: `git check-attr export-ignore -- images reports android shogunate_mod/mobile/android images/company-creed-all-panes.png reports/.gitkeep android/build.gradle.kts shogunate_mod/mobile/android/build.gradle.kts` confirmed all non-runtime asset roots and files are marked `export-ignore`.
- PASS: `git archive --worktree-attributes --format=tar HEAD | tar -tf - | rg '^(images|reports|android)(/|$)' || true` returned no paths after adding directory and recursive `export-ignore` rules.
- PASS: `npm pack --dry-run --json` confirmed npm runtime package still excludes root `images/`, root `reports/`, root `android/`, and `shogunate_mod/mobile/android/`.
- PASS: `PYTHONDONTWRITEBYTECODE=1 python3 -m unittest tests.unit.test_package_distribution` after adding MOD-owned reusable integration templates and root compatibility sync contracts.
- PASS: direct `cmp` checks confirmed root `templates/*.md` compatibility copies match `shogunate_mod/templates/*.md`.
- PASS: `npm pack --dry-run --json` includes root `templates/` and `shogunate_mod/templates/`.
- PASS: `PYTHONDONTWRITEBYTECODE=1 python3 -m unittest tests.unit.test_package_distribution` after adding MOD-owned Claude Code settings and root compatibility sync contracts.
- PASS: `python3 -m json.tool .claude/settings.json` and `python3 -m json.tool shogunate_mod/hooks/claude_settings.json` validated both settings files as JSON.
- PASS: direct `cmp` confirmed root `.claude/settings.json` compatibility copy matches `shogunate_mod/hooks/claude_settings.json`.
- PASS: `npm pack --dry-run --json` includes root `.claude/settings.json` and `shogunate_mod/hooks/claude_settings.json`.
- PASS: `PYTHONDONTWRITEBYTECODE=1 python3 -m unittest tests.unit.test_package_distribution` after adding MOD-owned context README and root compatibility sync contracts.
- PASS: direct `cmp` confirmed root `context/README.md` compatibility copy matches `shogunate_mod/context/README.md`.
- PASS: `npm pack --dry-run --json` includes root `context/README.md` and `shogunate_mod/context/README.md`.
- PASS: `PYTHONDONTWRITEBYTECODE=1 python3 -m unittest tests.unit.test_package_distribution` after adding MOD-owned OpenCode mark-as-read tool and root compatibility sync contracts.
- PASS: direct `cmp` confirmed root `.opencode/tools/mark-as-read.ts` compatibility copy matches `shogunate_mod/opencode/tools/mark-as-read.ts`.
- PASS: `npm pack --dry-run --json` includes root `.opencode/tools/mark-as-read.ts` and `shogunate_mod/opencode/tools/mark-as-read.ts`.
- PASS: `PYTHONDONTWRITEBYTECODE=1 python3 -m unittest tests.unit.test_package_distribution` after adding MOD-owned gitleaks config and root compatibility sync contracts.
- PASS: direct `cmp` confirmed root `.gitleaks.toml` compatibility copy matches `shogunate_mod/security/gitleaks.toml`.
- PASS: `npm pack --dry-run --json` includes root `.gitleaks.toml` and `shogunate_mod/security/gitleaks.toml`.
- PASS: direct `cmp` confirmed root `Makefile` compatibility copy matches `shogunate_mod/development/Makefile`.
- PASS: `bash -n shogunate_mod/package/prepublish_check.sh scripts/prepublish_check.sh` after adding the Makefile sync gate.
- PASS: `PYTHONDONTWRITEBYTECODE=1 python3 -m unittest tests.unit.test_package_distribution` after adding MOD-owned Makefile contract coverage.
- PASS: `npm pack --dry-run --json` includes root `Makefile` and `shogunate_mod/development/Makefile`.
- PASS: `git diff --check` after adding MOD-owned Makefile. Git warned that touched `.bat` files will be normalized to CRLF when Git next touches them, but the check exited 0.
- PASS: direct `cmp` confirmed root `.gitattributes` compatibility copy matches `shogunate_mod/package/gitattributes`.
- PASS: `bash -n shogunate_mod/package/prepublish_check.sh scripts/prepublish_check.sh` after adding the `.gitattributes` sync gate.
- PASS: `PYTHONDONTWRITEBYTECODE=1 python3 -m unittest tests.unit.test_package_distribution` after adding MOD-owned `.gitattributes` contract coverage.
- PASS: `npm pack --dry-run --json` includes `shogunate_mod/package/gitattributes` along with root `Makefile` and `shogunate_mod/development/Makefile`.
- PASS: `git diff --check` after adding MOD-owned `.gitattributes`. Git warned that touched `.bat` files will be normalized to CRLF when Git next touches them, but the check exited 0.
- PASS: direct `cmp` confirmed root `README.md` / `README_ja.md` compatibility copies match `shogunate_mod/docs/README.md` / `README_ja.md`.
- PASS: `bash -n shogunate_mod/package/prepublish_check.sh scripts/prepublish_check.sh` after adding the README sync gate.
- PASS: `PYTHONDONTWRITEBYTECODE=1 python3 -m unittest tests.unit.test_package_distribution` after adding MOD-owned README contract coverage.
- PASS: `npm pack --dry-run --json` includes root README files and `shogunate_mod/docs/README*.md`.
- PASS: `git diff --check` after adding MOD-owned README docs. Git warned that touched `.bat` files will be normalized to CRLF when Git next touches them, but the check exited 0.
- PASS: direct `cmp` confirmed root `CHANGELOG.md` / `CONTRIBUTING.md` / `SECURITY.md` compatibility copies match `shogunate_mod/docs/` copies.
- PASS: `bash -n shogunate_mod/package/prepublish_check.sh scripts/prepublish_check.sh` after adding the community docs sync gate.
- PASS: `PYTHONDONTWRITEBYTECODE=1 python3 -m unittest tests.unit.test_package_distribution` after adding MOD-owned community docs contract coverage.
- PASS: `npm pack --dry-run --json` includes root community docs and `shogunate_mod/docs/{CHANGELOG,CONTRIBUTING,SECURITY}.md`.
- PASS: `git diff --check` after adding MOD-owned community docs. Git warned that touched `.bat` files will be normalized to CRLF when Git next touches them, but the check exited 0.
- PASS: direct `cmp` confirmed root `.github/FUNDING.yml` and `.gitmodules` compatibility copies match `shogunate_mod/github/FUNDING.yml` and `shogunate_mod/development/gitmodules`.
- PASS: `bash -n shogunate_mod/package/prepublish_check.sh scripts/prepublish_check.sh` after adding metadata sync gates.
- PASS: `PYTHONDONTWRITEBYTECODE=1 python3 -m unittest tests.unit.test_package_distribution` after adding MOD-owned GitHub/development metadata contract coverage.
- PASS: `npm pack --dry-run --json` includes `shogunate_mod/github/FUNDING.yml` and `shogunate_mod/development/gitmodules`.
- PASS: `git diff --check` after adding MOD-owned GitHub/development metadata. Git warned that touched `.bat` files will be normalized to CRLF when Git next touches them, but the check exited 0.
- PASS: direct `cmp` confirmed root `docs/codd/*.md` compatibility copies match `shogunate_mod/gunkan/docs/*.md`.
- PASS: `bash -n shogunate_mod/package/prepublish_check.sh scripts/prepublish_check.sh` after adding the CoDD docs sync gate.
- PASS: `PYTHONDONTWRITEBYTECODE=1 python3 -m unittest tests.unit.test_package_distribution` after adding MOD-owned Gunkan/CoDD docs contract coverage.
- PASS: `npm pack --dry-run --json` includes root `docs/codd/*.md` and `shogunate_mod/gunkan/docs/*.md`.
- PASS: `git diff --check` after adding MOD-owned Gunkan/CoDD docs. Git warned that touched `.bat` files will be normalized to CRLF when Git next touches them, but the check exited 0.
- PASS: direct `cmp` confirmed root `tests/` compatibility files match `shogunate_mod/tests/`, excluding generated `__pycache__` / `.pyc` / `.pyo`.
- PASS: `bash -n shogunate_mod/package/prepublish_check.sh scripts/prepublish_check.sh tests/*.sh shogunate_mod/tests/*.sh tests/e2e/mock_cli.sh shogunate_mod/tests/e2e/mock_cli.sh tests/e2e/mock_behaviors/*.sh shogunate_mod/tests/e2e/mock_behaviors/*.sh` after adding the full test tree sync gate.
- PASS: `python3 -m py_compile tests/unit/*.py shogunate_mod/tests/unit/*.py` after adding the full test tree sync gate; generated `__pycache__` directories were removed.
- PASS: `PYTHONDONTWRITEBYTECODE=1 python3 -m unittest tests.unit.test_package_distribution` after adding full test tree contract coverage.
- PASS: `npm pack --dry-run --json` parsed path check confirmed runtime package excludes `shogunate_mod/tests/` after adding full test tree sources.
- PASS: `git diff --check` after adding MOD-owned full test tree. Git warned that touched `.bat` files will be normalized to CRLF when Git next touches them, but the check exited 0.
- PASS: `PYTHONDONTWRITEBYTECODE=1 python3 -m unittest tests.unit.test_package_distribution` after consolidating manifest test touchpoints to root `tests/`.
- PASS: direct `cmp` confirmed root `tests/` compatibility files still match `shogunate_mod/tests/`, excluding generated `__pycache__` / `.pyc` / `.pyo`, after consolidating test touchpoints.
- PASS: `bash -n shogunate_mod/package/prepublish_check.sh scripts/prepublish_check.sh` after consolidating test touchpoints.
- PASS: `npm pack --dry-run --json` parsed path check confirmed runtime package still excludes `shogunate_mod/tests/` after consolidating test touchpoints.
- PASS: `git diff --check` after consolidating manifest test touchpoints. Git warned that touched `.bat` files will be normalized to CRLF when Git next touches them, but the check exited 0.
- PASS: `PYTHONDONTWRITEBYTECODE=1 python3 -m unittest tests.unit.test_package_distribution` after adding manifest declared path existence coverage.
- PASS: direct `cmp` confirmed root `tests/` compatibility files still match `shogunate_mod/tests/`, excluding generated `__pycache__` / `.pyc` / `.pyo`, after adding manifest declared path coverage.
- PASS: `bash -n shogunate_mod/package/prepublish_check.sh scripts/prepublish_check.sh` after adding manifest declared path coverage.
- PASS: `npm pack --dry-run --json` parsed path check confirmed runtime package still excludes `shogunate_mod/tests/` after adding manifest declared path coverage.
- PASS: `git diff --check` after adding manifest declared path coverage. Git warned that touched `.bat` files will be normalized to CRLF when Git next touches them, but the check exited 0.
- PASS: direct `cmp` confirmed root `tests/specs/`, `tests/fixtures/`, and `tests/helpers/` compatibility files match `shogunate_mod/tests/`.
- PASS: `bash -n shogunate_mod/package/prepublish_check.sh scripts/prepublish_check.sh` after adding test support sync gates.
- PASS: `PYTHONDONTWRITEBYTECODE=1 python3 -m unittest tests.unit.test_package_distribution` after adding MOD-owned test support contract coverage.
- PASS: `npm pack --dry-run --json` confirms runtime package excludes `shogunate_mod/tests/`.
- PASS: `git diff --check` after adding MOD-owned test support files. Git warned that touched `.bat` files will be normalized to CRLF when Git next touches them, but the check exited 0.
- PASS: direct `cmp` confirmed root `tests/unit/*` compatibility files match `shogunate_mod/tests/unit/*`.
- PASS: `python3 -m py_compile tests/unit/*.py shogunate_mod/tests/unit/*.py` after adding MOD-owned unit test cases; generated `__pycache__` directories were removed.
- PASS: `bash -n shogunate_mod/package/prepublish_check.sh scripts/prepublish_check.sh tests/e2e/mock_cli.sh shogunate_mod/tests/e2e/mock_cli.sh shogunate_mod/tests/e2e/mock_behaviors/*.sh` after adding unit test case sync gates.
- PASS: `PYTHONDONTWRITEBYTECODE=1 python3 -m unittest tests.unit.test_package_distribution` after adding MOD-owned unit test case contract coverage.
- PASS: `npm pack --dry-run --json` parsed path check confirmed runtime package excludes `shogunate_mod/tests/` after adding unit test case sources.
- PASS: `git diff --check` after adding MOD-owned unit test cases. Git warned that touched `.bat` files will be normalized to CRLF when Git next touches them, but the check exited 0.
- PASS: direct `cmp` confirmed root `tests/e2e/fixtures/`, `tests/e2e/helpers/`, `tests/e2e/mock_behaviors/`, and `tests/e2e/mock_cli.sh` compatibility files match `shogunate_mod/tests/e2e/`.
- PASS: `bash -n shogunate_mod/package/prepublish_check.sh scripts/prepublish_check.sh tests/e2e/mock_cli.sh shogunate_mod/tests/e2e/mock_cli.sh shogunate_mod/tests/e2e/mock_behaviors/*.sh` after adding E2E support sync gates.
- PASS: `PYTHONDONTWRITEBYTECODE=1 python3 -m unittest tests.unit.test_package_distribution` after adding MOD-owned E2E support contract coverage.
- PASS: `npm pack --dry-run --json` confirms runtime package excludes `shogunate_mod/tests/` after adding E2E support sources.
- PASS: `git diff --check` after adding MOD-owned E2E support files. Git warned that touched `.bat` files will be normalized to CRLF when Git next touches them, but the check exited 0.
- PASS: direct `cmp` confirmed root `tests/e2e/*.bats` and E2E support files match `shogunate_mod/tests/e2e/`.
- PASS: `bash -n shogunate_mod/package/prepublish_check.sh scripts/prepublish_check.sh tests/e2e/mock_cli.sh shogunate_mod/tests/e2e/mock_cli.sh shogunate_mod/tests/e2e/mock_behaviors/*.sh` after adding E2E test case sync gates.
- PASS: `PYTHONDONTWRITEBYTECODE=1 python3 -m unittest tests.unit.test_package_distribution` after adding MOD-owned E2E test case contract coverage.
- PASS: `npm pack --dry-run --json` and parsed path check confirmed runtime package excludes `shogunate_mod/tests/` after adding E2E test case sources.
- PASS: `git diff --check` after adding MOD-owned E2E test cases. Git warned that touched `.bat` files will be normalized to CRLF when Git next touches them, but the check exited 0.
- PASS: `PYTHONDONTWRITEBYTECODE=1 python3 -m unittest tests.unit.test_package_distribution` ran 34 tests after adding package files coverage for MOD manifest runtime sources.
- PASS: direct `diff -qr tests shogunate_mod/tests -x __pycache__ -x '*.pyc' -x '*.pyo'` confirmed root test compatibility files match MOD test sources.
- PASS: `bash -n shogunate_mod/package/prepublish_check.sh scripts/prepublish_check.sh` after adding package files coverage.
- PASS: `npm pack --dry-run --json` parsed path check confirmed runtime package excludes `shogunate_mod/tests/` and `shogunate_mod/mobile/android/` after adding package files coverage.
- PASS: `git diff --check` after adding package files coverage. Git warned that touched `.bat` files will be normalized to CRLF when Git next touches them, but the check exited 0.
- PASS: `PYTHONDONTWRITEBYTECODE=1 python3 -m unittest tests.unit.test_package_distribution` ran 34 tests after adding current core touchpoint existence coverage.
- PASS: direct `diff -qr tests shogunate_mod/tests -x __pycache__ -x '*.pyc' -x '*.pyo'` confirmed root test compatibility files match MOD test sources after adding touchpoint coverage.
- PASS: `bash -n shogunate_mod/package/prepublish_check.sh scripts/prepublish_check.sh` after adding touchpoint coverage.
- PASS: `npm pack --dry-run --json` parsed path check confirmed runtime package excludes `shogunate_mod/tests/` and `shogunate_mod/mobile/android/` after adding touchpoint coverage.
- PASS: `git diff --check` after adding touchpoint coverage. Git warned that touched `.bat` files will be normalized to CRLF when Git next touches them, but the check exited 0.
- PASS: `PYTHONDONTWRITEBYTECODE=1 python3 -m unittest tests.unit.test_package_distribution` ran 35 tests after adding compatibility wrapper delegation and package inclusion coverage.
- PASS: direct `diff -qr tests shogunate_mod/tests -x __pycache__ -x '*.pyc' -x '*.pyo'` confirmed root test compatibility files match MOD test sources after adding wrapper coverage.
- PASS: `bash -n shogunate_mod/package/prepublish_check.sh scripts/prepublish_check.sh` after adding wrapper coverage.
- PASS: `npm pack --dry-run --json` parsed path check confirmed runtime package excludes `shogunate_mod/tests/` and `shogunate_mod/mobile/android/` after adding wrapper coverage.
- PASS: `git diff --check` after adding wrapper coverage. Git warned that touched `.bat` files will be normalized to CRLF when Git next touches them, but the check exited 0.
- PASS: `PYTHONDONTWRITEBYTECODE=1 python3 -m unittest tests.unit.test_package_distribution` ran 35 tests after adding `shogunate_mod/README.md` to manifest/package contract coverage.
- PASS: direct `diff -qr tests shogunate_mod/tests -x __pycache__ -x '*.pyc' -x '*.pyo'` confirmed root test compatibility files match MOD test sources after adding MOD README coverage.
- PASS: `bash -n shogunate_mod/package/prepublish_check.sh scripts/prepublish_check.sh` after adding MOD README coverage.
- PASS: `npm pack --dry-run --json` parsed path check confirmed `shogunate_mod/README.md` is included while `shogunate_mod/tests/` and `shogunate_mod/mobile/android/` remain excluded after adding MOD README coverage.
- PASS: `git diff --check` after adding MOD README coverage. Git warned that touched `.bat` files will be normalized to CRLF when Git next touches them, but the check exited 0.
- PASS: `PYTHONDONTWRITEBYTECODE=1 python3 -m unittest tests.unit.test_package_distribution` ran 36 tests after adding complete MOD file coverage by manifest `canonical_paths`.
- PASS: direct `diff -qr tests shogunate_mod/tests -x __pycache__ -x '*.pyc' -x '*.pyo'` confirmed root test compatibility files match MOD test sources after adding complete MOD file coverage.
- PASS: `bash -n shogunate_mod/package/prepublish_check.sh scripts/prepublish_check.sh` after adding complete MOD file coverage.
- PASS: `npm pack --dry-run --json` parsed path check confirmed `shogunate_mod/manifest.yaml` and `shogunate_mod/README.md` are included while `shogunate_mod/tests/` and `shogunate_mod/mobile/android/` remain excluded after adding complete MOD file coverage.
- PASS: `git diff --check` after adding complete MOD file coverage. Git warned that touched `.bat` files will be normalized to CRLF when Git next touches them, but the check exited 0.
- PASS: `PYTHONDONTWRITEBYTECODE=1 python3 -m unittest tests.unit.test_package_distribution` ran 37 tests after adding MOD README top-level directory coverage.
- PASS: direct `diff -qr tests shogunate_mod/tests -x __pycache__ -x '*.pyc' -x '*.pyo'` confirmed root test compatibility files match MOD test sources after adding MOD README top-level directory coverage.
- PASS: `bash -n shogunate_mod/package/prepublish_check.sh scripts/prepublish_check.sh` after adding MOD README top-level directory coverage.
- PASS: `npm pack --dry-run --json` parsed path check confirmed `shogunate_mod/manifest.yaml` and `shogunate_mod/README.md` are included while `shogunate_mod/tests/` and `shogunate_mod/mobile/android/` remain excluded after adding MOD README top-level directory coverage.
- PASS: `git diff --check` after adding MOD README top-level directory coverage. Git warned that touched `.bat` files will be normalized to CRLF when Git next touches them, but the check exited 0.
- PASS: `PYTHONDONTWRITEBYTECODE=1 python3 -m unittest tests.unit.test_package_distribution` ran 37 tests after wiring package distribution contract tests into `shogunate_mod/package/prepublish_check.sh`.
- PASS: direct `diff -qr tests shogunate_mod/tests -x __pycache__ -x '*.pyc' -x '*.pyo'` confirmed root test compatibility files match MOD test sources after wiring prepublish contract execution.
- PASS: `bash -n shogunate_mod/package/prepublish_check.sh scripts/prepublish_check.sh` after wiring prepublish contract execution.
- PASS: `npm pack --dry-run --json` parsed path check confirmed `shogunate_mod/package/prepublish_check.sh`, `shogunate_mod/manifest.yaml`, and `shogunate_mod/README.md` are included while `shogunate_mod/tests/` and `shogunate_mod/mobile/android/` remain excluded after wiring prepublish contract execution.
- PASS: `git diff --check` after wiring prepublish contract execution. Git warned that touched `.bat` files will be normalized to CRLF when Git next touches them, but the check exited 0.
- NOTE: Full `bash scripts/prepublish_check.sh` is expected to stop at the dirty-worktree gate in this active migration checkout; the added release-gate command was verified directly through the same package distribution unittest it invokes.
- PASS: `PYTHONDONTWRITEBYTECODE=1 python3 -m unittest tests.unit.test_package_distribution` ran 37 tests after fixing prepublish contract execution order before generated instruction freshness and dirty-worktree gates.
- PASS: direct `diff -qr tests shogunate_mod/tests -x __pycache__ -x '*.pyc' -x '*.pyo'` confirmed root test compatibility files match MOD test sources after adding prepublish order coverage.
- PASS: `bash -n shogunate_mod/package/prepublish_check.sh scripts/prepublish_check.sh` after adding prepublish order coverage.
- PASS: `npm pack --dry-run --json` parsed path check confirmed `shogunate_mod/package/prepublish_check.sh`, `shogunate_mod/manifest.yaml`, and `shogunate_mod/README.md` are included while `shogunate_mod/tests/` and `shogunate_mod/mobile/android/` remain excluded after adding prepublish order coverage.
- PASS: `git diff --check` after adding prepublish order coverage. Git warned that touched `.bat` files will be normalized to CRLF when Git next touches them, but the check exited 0.
- PASS: `PYTHONDONTWRITEBYTECODE=1 python3 -m unittest tests.unit.test_package_distribution` ran 38 tests after adding `current_core_touchpoints` metadata and wrapper-overlap coverage.
- PASS: direct `diff -qr tests shogunate_mod/tests -x __pycache__ -x '*.pyc' -x '*.pyo'` confirmed root test compatibility files match MOD test sources after adding touchpoint metadata coverage.
- PASS: `bash -n shogunate_mod/package/prepublish_check.sh scripts/prepublish_check.sh` after adding touchpoint metadata coverage.
- PASS: `npm pack --dry-run --json` parsed path check confirmed `shogunate_mod/package/prepublish_check.sh`, `shogunate_mod/manifest.yaml`, and `shogunate_mod/README.md` are included while `shogunate_mod/tests/` and `shogunate_mod/mobile/android/` remain excluded after adding touchpoint metadata coverage.
- PASS: `git diff --check` after adding touchpoint metadata coverage. Git warned that touched `.bat` files will be normalized to CRLF when Git next touches them, but the check exited 0.
- PASS: `PYTHONDONTWRITEBYTECODE=1 python3 -m unittest tests.unit.test_package_distribution` ran 38 tests after moving the Windows role configurator launcher body into `shogunate_mod/windows/configure_roles.bat`.
- PASS: direct `diff -qr tests shogunate_mod/tests -x __pycache__ -x '*.pyc' -x '*.pyo'` confirmed root test compatibility files match MOD test sources after moving the Windows role configurator launcher.
- PASS: `bash -n shogunate_mod/package/prepublish_check.sh scripts/prepublish_check.sh` after moving the Windows role configurator launcher.
- PASS: `npm pack --dry-run --json` parsed path check confirmed `shogunate_mod/windows/configure_roles.bat` and root `Shogunate-Configure-Roles.bat` are included while `shogunate_mod/tests/` and `shogunate_mod/mobile/android/` remain excluded.
- PASS: `git diff --check` after moving the Windows role configurator launcher. Git warned that touched `.bat` files will be normalized to CRLF when Git next touches them, but the check exited 0.
- PASS: `PYTHONDONTWRITEBYTECODE=1 python3 -m unittest tests.unit.test_package_distribution` ran 39 tests after adding thin-wrapper coverage for `compatibility_wrappers`.
- PASS: direct `diff -qr tests shogunate_mod/tests -x __pycache__ -x '*.pyc' -x '*.pyo'` confirmed root test compatibility files match MOD test sources after adding thin-wrapper coverage.
- PASS: `bash -n shogunate_mod/package/prepublish_check.sh scripts/prepublish_check.sh` after adding thin-wrapper coverage.
- PASS: `npm pack --dry-run --json` parsed path check confirmed `shogunate_mod/windows/configure_roles.bat` and root `Shogunate-Configure-Roles.bat` are included while `shogunate_mod/tests/` and `shogunate_mod/mobile/android/` remain excluded after adding thin-wrapper coverage.
- PASS: `git diff --check` after adding thin-wrapper coverage. Git warned that touched `.bat` files will be normalized to CRLF when Git next touches them, but the check exited 0.
- PASS: `PYTHONDONTWRITEBYTECODE=1 python3 -m unittest tests.unit.test_package_distribution` ran 39 tests after moving root `.gitignore` under MOD-owned package boundary sync.
- PASS: direct `diff -qr tests shogunate_mod/tests -x __pycache__ -x '*.pyc' -x '*.pyo'` confirmed root test compatibility files match MOD test sources after adding `.gitignore` sync coverage.
- PASS: `bash -n shogunate_mod/package/prepublish_check.sh scripts/prepublish_check.sh` after adding `.gitignore` sync coverage.
- PASS: `npm pack --dry-run --json` parsed path check confirmed `shogunate_mod/package/gitignore` and `shogunate_mod/package/prepublish_check.sh` are included while `shogunate_mod/tests/` and `shogunate_mod/mobile/android/` remain excluded after adding `.gitignore` sync coverage.
- PASS: `git diff --check` after adding `.gitignore` sync coverage. Git warned that touched `.bat` files will be normalized to CRLF when Git next touches them, but the check exited 0.
- PASS: `PYTHONDONTWRITEBYTECODE=1 python3 -m unittest tests.unit.test_package_distribution` ran 39 tests after adding `bin/shogunate.js` to manifest `compatibility_wrappers`.
- PASS: direct `diff -qr tests shogunate_mod/tests -x __pycache__ -x '*.pyc' -x '*.pyo'` confirmed root test compatibility files match MOD test sources after adding npm bin wrapper manifest coverage.
- PASS: `bash -n shogunate_mod/package/prepublish_check.sh scripts/prepublish_check.sh` after adding npm bin wrapper manifest coverage.
- PASS: `npm pack --dry-run --json` parsed path check confirmed `bin/shogunate.js`, `shogunate_mod/package/npm_cli.js`, and `shogunate_mod/manifest.yaml` are included while `shogunate_mod/tests/` and `shogunate_mod/mobile/android/` remain excluded after adding npm bin wrapper manifest coverage.
- PASS: `git diff --check` after adding npm bin wrapper manifest coverage. Git warned that touched `.bat` files will be normalized to CRLF when Git next touches them, but the check exited 0.
- PASS: `PYTHONDONTWRITEBYTECODE=1 python3 -m unittest tests.unit.test_package_distribution` ran 40 tests after adding root MOD delegate manifest coverage.
- PASS: direct `diff -qr tests shogunate_mod/tests -x __pycache__ -x '*.pyc' -x '*.pyo'` confirmed root test compatibility files match MOD test sources after adding root MOD delegate manifest coverage.
- PASS: `bash -n shogunate_mod/package/prepublish_check.sh scripts/prepublish_check.sh` after adding root MOD delegate manifest coverage.
- PASS: `npm pack --dry-run --json` parsed path check confirmed `bin/shogunate.js`, `shogunate_mod/package/npm_cli.js`, and `shogunate_mod/manifest.yaml` are included while `shogunate_mod/tests/`, `shogunate_mod/mobile/android/`, `__pycache__`, `.pyc`, and `.pyo` files remain excluded after adding root MOD delegate manifest coverage.
- PASS: `git diff --check` after adding root MOD delegate manifest coverage. Git warned that touched `.bat` files will be normalized to CRLF when Git next touches them, but the check exited 0.
- PASS: `PYTHONDONTWRITEBYTECODE=1 python3 -m unittest tests.unit.test_package_distribution` ran 41 tests after adding prepublish sync target manifest tracking coverage.
- PASS: direct `diff -qr tests shogunate_mod/tests -x __pycache__ -x '*.pyc' -x '*.pyo'` confirmed root test compatibility files match MOD test sources after adding prepublish sync target manifest tracking coverage.
- PASS: `bash -n shogunate_mod/package/prepublish_check.sh scripts/prepublish_check.sh` after adding prepublish sync target manifest tracking coverage.
- PASS: `npm pack --dry-run --json` parsed path check confirmed `bin/shogunate.js`, `shogunate_mod/package/npm_cli.js`, `shogunate_mod/manifest.yaml`, and `shogunate_mod/package/prepublish_check.sh` are included while `shogunate_mod/tests/`, `shogunate_mod/mobile/android/`, `__pycache__`, `.pyc`, and `.pyo` files remain excluded after adding prepublish sync target manifest tracking coverage.
- PASS: `git diff --check` after adding prepublish sync target manifest tracking coverage. Git warned that touched `.bat` files will be normalized to CRLF when Git next touches them, but the check exited 0.
- PASS: `PYTHONDONTWRITEBYTECODE=1 python3 -m unittest tests.unit.test_package_distribution` ran 42 tests after adding package coverage for MOD-side prepublish sync targets.
- PASS: direct `diff -qr tests shogunate_mod/tests -x __pycache__ -x '*.pyc' -x '*.pyo'` confirmed root test compatibility files match MOD test sources after adding package coverage for MOD-side prepublish sync targets.
- PASS: `bash -n shogunate_mod/package/prepublish_check.sh scripts/prepublish_check.sh` after adding package coverage for MOD-side prepublish sync targets.
- PASS: `npm pack --dry-run --json` parsed path check confirmed `bin/shogunate.js`, `shogunate_mod/package/npm_cli.js`, `shogunate_mod/manifest.yaml`, and `shogunate_mod/package/prepublish_check.sh` are included while `shogunate_mod/tests/`, `shogunate_mod/mobile/android/`, `__pycache__`, `.pyc`, and `.pyo` files remain excluded after adding package coverage for MOD-side prepublish sync targets.
- PASS: `git diff --check` after adding package coverage for MOD-side prepublish sync targets. Git warned that touched `.bat` files will be normalized to CRLF when Git next touches them, but the check exited 0.
- PASS: `PYTHONDONTWRITEBYTECODE=1 python3 -m unittest tests.unit.test_package_distribution` ran 43 tests after adding compatibility wrapper target canonical path coverage.
- PASS: direct `diff -qr tests shogunate_mod/tests -x __pycache__ -x '*.pyc' -x '*.pyo'` confirmed root test compatibility files match MOD test sources after adding compatibility wrapper target canonical path coverage.
- PASS: `bash -n shogunate_mod/package/prepublish_check.sh scripts/prepublish_check.sh` after adding compatibility wrapper target canonical path coverage.
- PASS: `npm pack --dry-run --json` parsed path check confirmed `bin/shogunate.js`, `shogunate_mod/package/npm_cli.js`, `shogunate_mod/manifest.yaml`, and `shogunate_mod/package/prepublish_check.sh` are included while `shogunate_mod/tests/`, `shogunate_mod/mobile/android/`, `__pycache__`, `.pyc`, and `.pyo` files remain excluded after adding compatibility wrapper target canonical path coverage.
- PASS: `git diff --check` after adding compatibility wrapper target canonical path coverage. Git warned that touched `.bat` files will be normalized to CRLF when Git next touches them, but the check exited 0.
- PASS: `PYTHONDONTWRITEBYTECODE=1 python3 -m unittest tests.unit.test_package_distribution` ran 44 tests after adding explicit delegate target coverage for `compatibility_wrappers`.
- PASS: direct `diff -qr tests shogunate_mod/tests -x __pycache__ -x '*.pyc' -x '*.pyo'` confirmed root test compatibility files match MOD test sources after adding explicit delegate target coverage.
- PASS: `bash -n shogunate_mod/package/prepublish_check.sh scripts/prepublish_check.sh` after adding explicit delegate target coverage.
- PASS: `npm pack --dry-run --json` parsed path check confirmed `bin/shogunate.js`, `shogunate_mod/package/npm_cli.js`, `shogunate_mod/manifest.yaml`, and `shogunate_mod/package/prepublish_check.sh` are included while `shogunate_mod/tests/`, `shogunate_mod/mobile/android/`, `__pycache__`, `.pyc`, and `.pyo` files remain excluded after adding explicit delegate target coverage.
- PASS: `git diff --check` after adding explicit delegate target coverage. Git warned that touched `.bat` files will be normalized to CRLF when Git next touches them, but the check exited 0.
- PASS: `PYTHONDONTWRITEBYTECODE=1 python3 -m unittest tests.unit.test_package_distribution` ran 44 tests after adding workflow sync checks to `shogunate_mod/package/prepublish_check.sh`.
- PASS: direct `diff -qr tests shogunate_mod/tests -x __pycache__ -x '*.pyc' -x '*.pyo'` confirmed root test compatibility files match MOD test sources after adding workflow prepublish sync checks.
- PASS: `bash -n shogunate_mod/package/prepublish_check.sh scripts/prepublish_check.sh` after adding workflow prepublish sync checks.
- PASS: `npm pack --dry-run --json` parsed path check confirmed `shogunate_mod/package/workflows/package-release.yml`, `shogunate_mod/package/workflows/test.yml`, and `shogunate_mod/package/prepublish_check.sh` are included while `shogunate_mod/tests/`, `shogunate_mod/mobile/android/`, `__pycache__`, `.pyc`, and `.pyo` files remain excluded after adding workflow prepublish sync checks. Root `.github/workflows/*` remains a GitHub-facing compatibility path, not a runtime package requirement.
- PASS: `git diff --check` after adding workflow prepublish sync checks. Git warned that touched `.bat` files will be normalized to CRLF when Git next touches them, but the check exited 0.
- PASS: `PYTHONDONTWRITEBYTECODE=1 python3 -m unittest tests.unit.test_package_distribution.PackageDistributionContractTests.test_test_workflow_has_mod_canonical_copy` after adding the CI `mod-check` job to root and MOD workflow copies.
- PASS: `PYTHONDONTWRITEBYTECODE=1 python3 -m unittest tests.unit.test_package_distribution` ran 44 tests after adding Android source sync to `shogunate_mod/package/prepublish_check.sh`.
- PASS: direct Android source sync check confirmed 75 Android source files match between `android/` and `shogunate_mod/mobile/android/` after excluding SDK/cache/build/local/apk artifacts.
- PASS: direct `diff -qr tests shogunate_mod/tests -x __pycache__ -x '*.pyc' -x '*.pyo'` confirmed root test compatibility files match MOD test sources after adding Android prepublish sync checks.
- PASS: `bash -n shogunate_mod/package/prepublish_check.sh scripts/prepublish_check.sh` after adding Android prepublish sync checks.
- PASS: `npm pack --dry-run --json` parsed path check confirmed `shogunate_mod/package/prepublish_check.sh` and `shogunate_mod/manifest.yaml` are included while `android/`, `shogunate_mod/mobile/android/`, `shogunate_mod/tests/`, `__pycache__`, `.pyc`, and `.pyo` files remain excluded after adding Android prepublish sync checks.
- PASS: `git diff --check` after adding Android prepublish sync checks. Git warned that touched `.bat` files will be normalized to CRLF when Git next touches them, but the check exited 0.
- PASS: `PYTHONDONTWRITEBYTECODE=1 python3 -m unittest tests.unit.test_package_distribution` ran 45 tests after adding generated root touchpoint freshness coverage and package files entries.
- PASS: `npm pack --dry-run --json` parsed path check confirmed `AGENTS.md`, `.github/copilot-instructions.md`, `agents/default/system.md`, `agents/default/agent.yaml`, `.opencode/agents/shogun.md`, `.opencode/agents/ashigaru8.md`, `shogunate_mod/instructions/ensure_generated.sh`, and `shogunate_mod/manifest.yaml` are included while `android/`, `shogunate_mod/mobile/android/`, `shogunate_mod/tests/`, `__pycache__`, `.pyc`, and `.pyo` files remain excluded.
- PASS: direct `diff -qr tests shogunate_mod/tests -x __pycache__ -x '*.pyc' -x '*.pyo'` confirmed root test compatibility files match MOD test sources after adding generated root touchpoint package coverage.
- PASS: `bash -n shogunate_mod/package/prepublish_check.sh scripts/prepublish_check.sh shogunate_mod/instructions/ensure_generated.sh scripts/ensure_generated_instructions.sh` after adding generated root touchpoint package coverage.
- PASS: `git diff --check` after adding generated root touchpoint package coverage. Git warned that touched `.bat` files will be normalized to CRLF when Git next touches them, but the check exited 0.
- PASS: `PYTHONDONTWRITEBYTECODE=1 python3 -m unittest tests.unit.test_package_distribution` ran 46 tests after adding the manifest MOD canonical source gitignore visibility contract.
- PASS: `PYTHONDONTWRITEBYTECODE=1 python3 -m unittest tests.unit.test_package_distribution` ran 47 tests after adding the manifest synchronized core touchpoint prepublish-gate contract.
- PASS: `npm pack --dry-run --json` parsed path check confirmed root `CLAUDE.md`, root `.codd/codd.yaml`, MOD `shogunate_mod/instructions/autoload/CLAUDE.md`, and MOD `shogunate_mod/gunkan/codd.yaml` are included after adding root compatibility package entries.
- PASS: `PYTHONDONTWRITEBYTECODE=1 python3 -m unittest tests.unit.test_package_distribution` ran 48 tests after adding the actual `npm pack --dry-run --json` runtime package boundary contract.
- PASS: `PYTHONDONTWRITEBYTECODE=1 python3 -m unittest tests.unit.test_package_distribution` ran 48 tests after switching MOD manifest runtime package coverage to actual `npm pack --dry-run --json` results.
- PASS: `PYTHONDONTWRITEBYTECODE=1 python3 -m unittest tests.unit.test_package_distribution` ran 48 tests after switching compatibility wrapper and MOD prepublish sync package coverage to actual `npm pack --dry-run --json` results.
- PASS: `PYTHONDONTWRITEBYTECODE=1 python3 -m unittest tests.unit.test_package_distribution` ran 48 tests after removing the stale package-files coverage helper.
- PASS: `PYTHONDONTWRITEBYTECODE=1 python3 -m unittest tests.unit.test_package_distribution` ran 48 tests after switching public community docs and integration template package coverage to actual `npm pack --dry-run --json` results.
- PASS: `PYTHONDONTWRITEBYTECODE=1 python3 -m unittest tests.unit.test_package_distribution` ran 49 tests after adding actual npm pack materialization coverage for package `files` entries.
- PASS: `PYTHONDONTWRITEBYTECODE=1 python3 -m unittest tests.unit.test_package_distribution` ran 49 tests after narrowing root `docs/` package coverage to `docs/codd/` and forbidding working docs from the runtime npm package.
- PASS: `npm pack --dry-run --json` showed root docs package coverage is limited to the 4 files under `docs/codd/`.
- PASS: `PYTHONDONTWRITEBYTECODE=1 python3 -m unittest tests.unit.test_package_distribution` ran 49 tests after narrowing root `context/` package coverage to `context/README.md`.
- PASS: `npm pack --dry-run --json` showed root context package coverage is limited to `context/README.md`.
- PASS: `PYTHONDONTWRITEBYTECODE=1 python3 -m unittest tests.unit.test_package_distribution` ran 50 tests after forbidding broad root runtime / working-state directory entries in package `files`.
- PASS: `PYTHONDONTWRITEBYTECODE=1 python3 -m unittest tests.unit.test_package_distribution` ran 51 tests after replacing root script globs with explicit manifest-declared compatibility wrappers.
- PASS: `npm pack --dry-run --json` showed the 50 packaged root `scripts/` entries match the 50 manifest `compatibility_wrappers` under `scripts/`.
- PASS: `PYTHONDONTWRITEBYTECODE=1 python3 -m unittest tests.unit.test_package_distribution` ran 52 tests after replacing root `lib/` directory packaging with explicit manifest-declared compatibility wrappers.
- PASS: `npm pack --dry-run --json` showed the 8 packaged root `lib/` entries match the 8 manifest `compatibility_wrappers` under `lib/`.
- PASS: `PYTHONDONTWRITEBYTECODE=1 python3 -m unittest tests.unit.test_package_distribution` ran 53 tests after replacing root `bin/` directory packaging with explicit manifest-declared compatibility wrappers.
- PASS: `npm pack --dry-run --json` showed the 59 packaged root `bin/` / `lib/` / `scripts/` entries match the 59 manifest `compatibility_wrappers` under those roots.
- PASS: `bash shogunate_mod/instructions/ensure_generated.sh` rebuilt generated instruction files after adding Cursor generated instruction freshness targets.
- PASS: `PYTHONDONTWRITEBYTECODE=1 python3 -m unittest tests.unit.test_package_distribution` ran 54 tests after requiring packaged root instructions to be either MOD source compatibility copies or generated freshness targets.
- PASS: `PYTHONDONTWRITEBYTECODE=1 python3 -m unittest tests.unit.test_package_distribution` ran 55 tests after requiring generated OpenCode agent definitions to identify MOD instruction sources.
- PASS: `PYTHONDONTWRITEBYTECODE=1 python3 -m unittest tests.unit.test_package_distribution` ran 56 tests after replacing generated root directory package entries with explicit freshness-target files.
- PASS: direct `diff -qr tests shogunate_mod/tests -x __pycache__ -x '*.pyc' -x '*.pyo'` confirmed root test compatibility files match MOD test sources after adding generated root file package boundary coverage.
- PASS: `npm pack --dry-run --json` showed the 17 packaged generated root files under `.opencode/agents/` and `agents/default/` match freshness targets, with no broad generated root directory entries.
- PASS: `bash -n shogunate_mod/instructions/ensure_generated.sh scripts/ensure_generated_instructions.sh shogunate_mod/package/prepublish_check.sh scripts/prepublish_check.sh` after replacing generated root directory package entries.
- PASS: `git diff --check` after replacing generated root directory package entries. Git warned that touched `.bat` files will be normalized to CRLF when Git next touches them, but the check exited 0.
- PASS: `PYTHONDONTWRITEBYTECODE=1 python3 -m unittest tests.unit.test_package_distribution` ran 56 tests after replacing root `.opencode/tools/` package entry with `.opencode/tools/mark-as-read.ts`.
- PASS: direct `diff -qr tests shogunate_mod/tests -x __pycache__ -x '*.pyc' -x '*.pyo'` confirmed root test compatibility files match MOD test sources after adding the root OpenCode tool package boundary coverage.
- PASS: `npm pack --dry-run --json` showed root `.opencode/tools/` package coverage is limited to `.opencode/tools/mark-as-read.ts`, while `.opencode/agents/` and `agents/default/` still contain the 17 explicit generated root files and no broad directory entries.
- PASS: `bash -n shogunate_mod/instructions/ensure_generated.sh scripts/ensure_generated_instructions.sh shogunate_mod/package/prepublish_check.sh scripts/prepublish_check.sh` after replacing the root OpenCode tool package entry.
- PASS: `git diff --check` after replacing the root OpenCode tool package entry. Git warned that touched `.bat` files will be normalized to CRLF when Git next touches them, but the check exited 0.
- PASS: `PYTHONDONTWRITEBYTECODE=1 python3 -m unittest tests.unit.test_package_distribution` ran 56 tests after replacing root `instructions/` package entry with 67 explicit instruction files.
- PASS: direct `diff -qr tests shogunate_mod/tests -x __pycache__ -x '*.pyc' -x '*.pyo'` confirmed root test compatibility files match MOD test sources after adding root instruction package boundary coverage.
- PASS: `npm pack --dry-run --json` showed root `instructions/` package coverage remains exactly 67 instruction files, with no `instructions/` broad package entry.
- PASS: `bash -n shogunate_mod/instructions/ensure_generated.sh scripts/ensure_generated_instructions.sh shogunate_mod/package/prepublish_check.sh scripts/prepublish_check.sh` after replacing the root instruction package entry.
- PASS: `git diff --check` after replacing the root instruction package entry. Git warned that touched `.bat` files will be normalized to CRLF when Git next touches them, but the check exited 0.
- PASS: `PYTHONDONTWRITEBYTECODE=1 python3 -m unittest tests.unit.test_package_distribution` ran 57 tests after replacing root `skills/` / `.cursor/skills/` / `templates/` package entries with explicit sync-target files.
- PASS: direct `diff -qr tests shogunate_mod/tests -x __pycache__ -x '*.pyc' -x '*.pyo'` confirmed root test compatibility files match MOD test sources after adding root skills/templates package boundary coverage.
- PASS: `npm pack --dry-run --json` showed root skills package coverage is limited to 11 files, root templates coverage is limited to 6 files, and `skills/.system/` is not included.
- PASS: `bash -n shogunate_mod/instructions/ensure_generated.sh scripts/ensure_generated_instructions.sh shogunate_mod/package/prepublish_check.sh scripts/prepublish_check.sh` after replacing root skills/templates package entries.
- PASS: `git diff --check` after replacing root skills/templates package entries. Git warned that touched `.bat` files will be normalized to CRLF when Git next touches them, but the check exited 0.
- PASS: `PYTHONDONTWRITEBYTECODE=1 python3 -m unittest tests.unit.test_package_distribution` ran 58 tests after replacing root `docs/codd/` package entry with explicit CoDD doc files.
- PASS: direct `diff -qr tests shogunate_mod/tests -x __pycache__ -x '*.pyc' -x '*.pyo'` confirmed root test compatibility files match MOD test sources after adding root CoDD docs package boundary coverage.
- PASS: `npm pack --dry-run --json` showed root docs package coverage is limited to the 4 files under `docs/codd/`, with no `docs/` or `docs/codd/` broad package entry.
- PASS: `bash -n shogunate_mod/instructions/ensure_generated.sh scripts/ensure_generated_instructions.sh shogunate_mod/package/prepublish_check.sh scripts/prepublish_check.sh` after replacing root CoDD docs package entry.
- PASS: `git diff --check` after replacing root CoDD docs package entry. Git warned that touched `.bat` files will be normalized to CRLF when Git next touches them, but the check exited 0.
- PASS: `PYTHONDONTWRITEBYTECODE=1 python3 -m unittest tests.unit.test_package_distribution` ran 59 tests after adding the contract that package broad entries are MOD canonical source directories only.
- PASS: direct `diff -qr tests shogunate_mod/tests -x __pycache__ -x '*.pyc' -x '*.pyo'` confirmed root test compatibility files match MOD test sources after adding package broad-entry canonical coverage.
- PASS: `npm pack --dry-run --json` showed the 28 positive broad package entries are all under `shogunate_mod/`, with no non-MOD broad entries.
- PASS: `bash -n shogunate_mod/instructions/ensure_generated.sh scripts/ensure_generated_instructions.sh shogunate_mod/package/prepublish_check.sh scripts/prepublish_check.sh` after adding package broad-entry canonical coverage.
- PASS: `git diff --check` after adding package broad-entry canonical coverage. Git warned that touched `.bat` files will be normalized to CRLF when Git next touches them, but the check exited 0.
- PASS: `PYTHONDONTWRITEBYTECODE=1 python3 -m unittest tests.unit.test_package_distribution` ran 59 tests after adding `git check-attr export-ignore` coverage for release archive exclusions.
- PASS: `git check-attr export-ignore -- android android/README.md shogunate_mod/mobile/android shogunate_mod/mobile/android/README.md images reports README.md` showed Android / images / reports paths are `set` and `README.md` is `unspecified`.
- PASS: direct `diff -qr tests shogunate_mod/tests -x __pycache__ -x '*.pyc' -x '*.pyo'` confirmed root test compatibility files match MOD test sources after adding release archive attribute coverage.
- PASS: `npm pack --dry-run --json` still excluded `android/`, `shogunate_mod/mobile/android/`, `images/`, and `reports/`.
- PASS: `bash -n shogunate_mod/instructions/ensure_generated.sh scripts/ensure_generated_instructions.sh shogunate_mod/package/prepublish_check.sh scripts/prepublish_check.sh` after adding release archive attribute coverage.
- PASS: `git diff --check` after adding release archive attribute coverage. Git warned that touched `.bat` files will be normalized to CRLF when Git next touches them, but the check exited 0.
- PASS: `PYTHONDONTWRITEBYTECODE=1 python3 -m unittest tests.unit.test_package_distribution` ran 59 tests after adding release workflow order coverage that requires prepublish to run before tag validation and archive creation.
- PASS: direct `diff -qr tests shogunate_mod/tests -x __pycache__ -x '*.pyc' -x '*.pyo'` confirmed root test compatibility files match MOD test sources after adding release workflow order coverage.
- PASS: `bash -n shogunate_mod/instructions/ensure_generated.sh scripts/ensure_generated_instructions.sh shogunate_mod/package/prepublish_check.sh scripts/prepublish_check.sh` after adding release workflow order coverage.
- PASS: `npm pack --dry-run --json` parsed 361 files and confirmed `android/`, `shogunate_mod/mobile/android/`, `images/`, and `reports/` are excluded while `shogunate_mod/` is included after adding release workflow order coverage.
- PASS: `git diff --check` after adding release workflow order coverage. Git warned that touched `.bat` files will be normalized to CRLF when Git next touches them, but the check exited 0.
- PASS: `PYTHONDONTWRITEBYTECODE=1 python3 -m unittest tests.unit.test_package_distribution tests.unit.test_shogunate_pair_server tests.unit.test_runtime_blocker_notice tests.unit.test_update_manager` ran 93 tests after release workflow order coverage. Pair server test printed the expected local Pairing complete message and exited 0.
- PASS: `bats tests/unit/test_runtime_launchers.bats tests/unit/test_shell_aliases.bats tests/unit/test_mux_parity.bats tests/unit/test_watcher_supervisor.bats` ran 92 tests after release workflow order coverage.
- PASS: `./gradlew testDebugUnitTest --quiet` from `android/` after release workflow order coverage. Gradle warned about SDK XML version mismatch, but the command exited 0.
- PASS: `PYTHONDONTWRITEBYTECODE=1 python3 -m unittest tests.unit.test_package_distribution` ran 59 tests after tightening the global context template/runtime-state package boundary.
- PASS: direct `diff -qr tests shogunate_mod/tests -x __pycache__ -x '*.pyc' -x '*.pyo'` confirmed root test compatibility files match MOD test sources after tightening the global context template/runtime-state package boundary.
- PASS: `npm pack --dry-run --json` parsed 361 files and confirmed `shogunate_mod/package/templates/memory/global_context.md.sample` is included while root runtime state `memory/global_context.md` is not included.
- PASS: `bash -n shogunate_mod/package/first_setup.sh first_setup.sh shogunate_mod/package/prepublish_check.sh scripts/prepublish_check.sh` after tightening the global context template/runtime-state package boundary.
- PASS: `git diff --check` after tightening the global context template/runtime-state package boundary. Git warned that touched `.bat` files will be normalized to CRLF when Git next touches them, but the check exited 0.
- PASS: `PYTHONDONTWRITEBYTECODE=1 python3 -m unittest tests.unit.test_package_distribution` ran 59 tests after adding explicit npm package exclusions for root runtime/local state.
- PASS: direct `diff -qr tests shogunate_mod/tests -x __pycache__ -x '*.pyc' -x '*.pyo'` confirmed root test compatibility files match MOD test sources after adding runtime/local state package exclusions.
- PASS: `npm pack --dry-run --json` parsed 361 files and confirmed no `config/projects.yaml`, `config/settings.yaml`, `dashboard.md`, `memory/MEMORY.md`, `memory/global_context.md`, `saytask/streaks.yaml`, `queue/`, or `runtime_sandboxes/` entries are present.
- PASS: `bash -n shogunate_mod/package/prepublish_check.sh scripts/prepublish_check.sh shogunate_mod/package/first_setup.sh first_setup.sh` after adding runtime/local state package exclusions.
- PASS: `git diff --check` after adding runtime/local state package exclusions. Git warned that touched `.bat` files will be normalized to CRLF when Git next touches them, but the check exited 0.
- PASS: `PYTHONDONTWRITEBYTECODE=1 python3 -m unittest tests.unit.test_package_distribution` ran 59 tests after adding release archive export-ignore coverage for test trees, runtime/local state, and working docs.
- PASS: direct `diff -qr tests shogunate_mod/tests -x __pycache__ -x '*.pyc' -x '*.pyo'` confirmed root test compatibility files match MOD test sources after adding release archive export-ignore coverage.
- PASS: `git check-attr export-ignore -- tests/unit/test_package_distribution.py shogunate_mod/tests/unit/test_package_distribution.py queue/runtime/session_name runtime_sandboxes/example dashboard.md config/settings.yaml config/projects.yaml memory/MEMORY.md memory/global_context.md saytask/streaks.yaml docs/REQS.md docs/WORKLOG.md docs/EXECPLAN_2026-06-16_upstream_core_mod_split.md README.md shogunate_mod/package/templates/memory/global_context.md.sample` showed runtime/test/working-doc paths are `set`, while `README.md` and the MOD global context template are `unspecified`.
- PASS: `bash -n shogunate_mod/package/prepublish_check.sh scripts/prepublish_check.sh` after adding release archive export-ignore coverage.
- PASS: `npm pack --dry-run --json` still parsed 361 files and confirmed npm package excludes root/shogunate_mod tests and `queue/`.
- PASS: `git diff --check` after adding release archive export-ignore coverage. Git warned that touched `.bat` files will be normalized to CRLF when Git next touches them, but the check exited 0.
- PASS: `PYTHONDONTWRITEBYTECODE=1 python3 -m unittest tests.unit.test_package_distribution` ran 59 tests after excluding GitHub/CI/development metadata from cURL release archives.
- PASS: direct `diff -qr tests shogunate_mod/tests -x __pycache__ -x '*.pyc' -x '*.pyo'` confirmed root test compatibility files match MOD test sources after excluding GitHub/CI/development metadata from cURL release archives.
- PASS: `git check-attr export-ignore -- .github/workflows/package-release.yml .github/workflows/test.yml .github/FUNDING.yml .gitmodules .gitignore .gitattributes package-lock.json shogunate_mod/package/package-lock.json shogunate_mod/package/workflows/package-release.yml shogunate_mod/package/gitattributes shogunate_mod/package/gitignore package.json README.md .github/copilot-instructions.md shogunate_mod/package/templates/memory/global_context.md.sample` showed GitHub/CI/development metadata paths are `set`, while runtime-facing `package.json`, `README.md`, Copilot instructions, and the MOD global context template are `unspecified`.
- PASS: `bash -n shogunate_mod/package/prepublish_check.sh scripts/prepublish_check.sh` after excluding GitHub/CI/development metadata from cURL release archives.
- PASS: `npm pack --dry-run --json` still parsed 361 files. npm package intentionally keeps workflow and lock metadata; this change only narrows cURL release archives.
- PASS: `git diff --check` after excluding GitHub/CI/development metadata from cURL release archives. Git warned that touched `.bat` files will be normalized to CRLF when Git next touches them, but the check exited 0.
- PASS: `PYTHONDONTWRITEBYTECODE=1 python3 -m unittest tests.unit.test_package_distribution` ran 59 tests after adding positive archive checks for install/runtime entrypoints.
- PASS: direct `diff -qr tests shogunate_mod/tests -x __pycache__ -x '*.pyc' -x '*.pyo'` confirmed root test compatibility files match MOD test sources after adding positive archive checks.
- PASS: `git check-attr export-ignore -- first_setup.sh shogunate_mod/package/first_setup.sh shogunate_mod/package/requirements.txt scripts/shogunate_pair_server.py shogunate_mod/pair/server.py bin/shogunate.js Shogunate-Runtime.sh Shutsujin.sh shutsujin_departure.sh shogunate_mod/runtime/runtime_launcher.sh shogunate_mod/runtime/departure.sh .github/workflows/package-release.yml package-lock.json` showed install/runtime entrypoints are `unspecified`, while excluded CI/lock metadata remains `set`.
- PASS: `bash -n shogunate_mod/package/prepublish_check.sh scripts/prepublish_check.sh` after adding positive archive checks.
- PASS: `git diff --check` after adding positive archive checks. Git warned that touched `.bat` files will be normalized to CRLF when Git next touches them, but the check exited 0.
- PASS: `PYTHONDONTWRITEBYTECODE=1 python3 -m unittest tests.unit.test_package_distribution` ran 60 tests after adding the root Shogunate surface classification contract. The new contract scans tracked root public surfaces with Shogunate-specific markers and requires each match to be declared as either a `compatibility_wrapper` or `current_core_touchpoint`.
- PASS: direct `diff -qr tests shogunate_mod/tests -x __pycache__ -x '*.pyc' -x '*.pyo'` confirmed root test compatibility files match MOD test sources after adding root surface classification coverage.
- PASS: `bash -n shogunate_mod/package/prepublish_check.sh scripts/prepublish_check.sh` after adding root surface classification coverage.
- PASS: `git diff --check` after adding root surface classification coverage. Git warned that touched `.bat` files will be normalized to CRLF when Git next touches them, but the check exited 0.
- PASS: `PYTHONDONTWRITEBYTECODE=1 python3 -m unittest tests.unit.test_package_distribution` ran 61 tests after adding release archive coverage for MOD canonical sources. The new contract expands `shogunate_mod/manifest.yaml` canonical paths to files and verifies with `git check-attr export-ignore` that runtime-facing MOD sources remain in cURL release archives while Android, tests, package workflows, package lock, and package boundary metadata stay excluded.
- PASS: direct `diff -qr tests shogunate_mod/tests -x __pycache__ -x '*.pyc' -x '*.pyo'` confirmed root test compatibility files match MOD test sources after adding release archive MOD canonical source coverage.
- PASS: `bash -n shogunate_mod/package/prepublish_check.sh scripts/prepublish_check.sh` after adding release archive MOD canonical source coverage.
- PASS: `git diff --check` after adding release archive MOD canonical source coverage. Git warned that touched `.bat` files will be normalized to CRLF when Git next touches them, but the check exited 0.
- PASS: `PYTHONDONTWRITEBYTECODE=1 python3 -m unittest tests.unit.test_package_distribution.PackageDistributionContractTests.test_synchronized_core_touchpoints_have_prepublish_gates` after adding `config/` to the synchronized touchpoint gate.
- PASS: `PYTHONDONTWRITEBYTECODE=1 python3 -m unittest tests.unit.test_package_distribution` ran 61 tests after clarifying tracked root config defaults as MOD-owned compatibility copies.
- PASS: direct `diff -qr tests shogunate_mod/tests -x __pycache__ -x '*.pyc' -x '*.pyo'` confirmed root test compatibility files match MOD test sources after the config touchpoint clarification.
- PASS: `bash -n shogunate_mod/package/prepublish_check.sh scripts/prepublish_check.sh` after the config touchpoint clarification.
- PASS: `git diff --check` after the config touchpoint clarification. Git warned that touched `.bat` files will be normalized to CRLF when Git next touches them, but the check exited 0.
- PASS: `PYTHONDONTWRITEBYTECODE=1 python3 -m unittest tests.unit.test_package_distribution.PackageDistributionContractTests.test_compatibility_wrappers_delegate_to_shogunate_mod tests.unit.test_package_distribution.PackageDistributionContractTests.test_npm_wrapper_points_to_curl_bootstrap` after adding explicit `config/projects.yaml` local-state gates.
- PASS: `git check-ignore -v config/settings.yaml config/projects.yaml` showed both local config files are explicitly ignored by `.gitignore`.
- PASS: `PYTHONDONTWRITEBYTECODE=1 python3 -m unittest tests.unit.test_package_distribution` ran 61 tests after adding explicit `config/projects.yaml` local-state gates.
- PASS: direct `diff -qr tests shogunate_mod/tests -x __pycache__ -x '*.pyc' -x '*.pyo'` confirmed root test compatibility files match MOD test sources after adding explicit `config/projects.yaml` local-state gates.
- PASS: `bash -n shogunate_mod/package/prepublish_check.sh scripts/prepublish_check.sh` after adding explicit `config/projects.yaml` local-state gates.
- PASS: `git diff --check` after adding explicit `config/projects.yaml` local-state gates. Git warned that touched `.bat` files will be normalized to CRLF when Git next touches them, but the check exited 0.
- PASS: `PYTHONDONTWRITEBYTECODE=1 python3 -m unittest tests.unit.test_package_distribution.PackageDistributionContractTests.test_prepublish_requires_manifest_mod_sources_tracked` after adding the release prepublish gate that requires manifest MOD canonical sources to be tracked by Git.
- PASS: `bash -n shogunate_mod/package/prepublish_check.sh scripts/prepublish_check.sh` after adding the tracked-MOD-source prepublish gate.
- PASS: `PYTHONDONTWRITEBYTECODE=1 python3 -m unittest tests.unit.test_package_distribution` ran 62 tests after adding the tracked-MOD-source prepublish gate.
- PASS: direct `diff -qr tests shogunate_mod/tests -x __pycache__ -x '*.pyc' -x '*.pyo'` confirmed root test compatibility files match MOD test sources after adding the tracked-MOD-source prepublish gate.
- PASS: `git diff --check` after adding the tracked-MOD-source prepublish gate. Git warned that touched `.bat` files will be normalized to CRLF when Git next touches them, but the check exited 0.
- PASS: `PYTHONDONTWRITEBYTECODE=1 python3 -m unittest tests.unit.test_package_distribution.PackageDistributionContractTests.test_prepublish_requires_manifest_mod_sources_in_head` after tightening the MOD canonical source release gate to check the archive source tree (`HEAD`) instead of the index.
- PASS: `bash -n shogunate_mod/package/prepublish_check.sh scripts/prepublish_check.sh` after tightening the MOD canonical source release gate to checked `HEAD`.
- PASS: `PYTHONDONTWRITEBYTECODE=1 python3 -m unittest tests.unit.test_package_distribution` ran 62 tests after tightening the MOD canonical source release gate to checked `HEAD`.
- PASS: direct `diff -qr tests shogunate_mod/tests -x __pycache__ -x '*.pyc' -x '*.pyo'` confirmed root test compatibility files match MOD test sources after tightening the MOD canonical source release gate to checked `HEAD`.
- PASS: `git diff --check` after tightening the MOD canonical source release gate to checked `HEAD`. Git warned that touched `.bat` files will be normalized to CRLF when Git next touches them, but the check exited 0.
- PASS: `PYTHONDONTWRITEBYTECODE=1 python3 -m unittest tests.unit.test_package_distribution.PackageDistributionContractTests.test_release_workflow_builds_packages_not_installers_or_apks tests.unit.test_package_distribution.PackageDistributionContractTests.test_test_workflow_has_mod_canonical_copy` after changing package release archive creation to checked `HEAD` with tag-to-HEAD validation.
- PASS: `bash -n shogunate_mod/package/prepublish_check.sh scripts/prepublish_check.sh` after changing package release archive creation to checked `HEAD`.
- PASS: `PYTHONDONTWRITEBYTECODE=1 python3 -m unittest tests.unit.test_package_distribution` ran 62 tests after changing package release archive creation to checked `HEAD`.
- PASS: direct `diff -qr tests shogunate_mod/tests -x __pycache__ -x '*.pyc' -x '*.pyo'` confirmed root test compatibility files match MOD test sources after changing package release archive creation to checked `HEAD`.
- PASS: `git diff --check` after changing package release archive creation to checked `HEAD`. Git warned that touched `.bat` files will be normalized to CRLF when Git next touches them, but the check exited 0.
- PASS: `PYTHONDONTWRITEBYTECODE=1 python3 -m unittest tests.unit.test_package_distribution.PackageDistributionContractTests.test_release_workflow_builds_packages_not_installers_or_apks` after adding the package-only upload/release asset contract.
- PASS: direct `diff -qr tests shogunate_mod/tests -x __pycache__ -x '*.pyc' -x '*.pyo'` confirmed root test compatibility files match MOD test sources after adding the package-only release asset contract.
- PASS: `PYTHONDONTWRITEBYTECODE=1 python3 -m unittest tests.unit.test_package_distribution` ran 62 tests after adding the package-only release asset contract.
- PASS: `bash -n shogunate_mod/package/prepublish_check.sh scripts/prepublish_check.sh` after adding the package-only release asset contract.
- PASS: `git diff --check` after adding the package-only release asset contract. Git warned that touched `.bat` files will be normalized to CRLF when Git next touches them, but the check exited 0.
- PASS: `PYTHONDONTWRITEBYTECODE=1 python3 -m unittest tests.unit.test_package_distribution.PackageDistributionContractTests.test_prepublish_requires_manifest_mod_sources_in_head` after adding a clearer missing-from-HEAD message to the MOD canonical source release gate.
- PASS: `bash -n shogunate_mod/package/prepublish_check.sh scripts/prepublish_check.sh` after adding the clearer missing-from-HEAD message.
- PASS: direct `diff -qr tests shogunate_mod/tests -x __pycache__ -x '*.pyc' -x '*.pyo'` confirmed root test compatibility files match MOD test sources after adding the clearer missing-from-HEAD message.
- PASS: `PYTHONDONTWRITEBYTECODE=1 python3 -m unittest tests.unit.test_package_distribution` ran 62 tests after adding the clearer missing-from-HEAD message.
- PASS: `git diff --check` after adding the clearer missing-from-HEAD message. Git warned that touched `.bat` files will be normalized to CRLF when Git next touches them, but the check exited 0.
- OBSERVED: `bash shogunate_mod/package/prepublish_check.sh` initially failed at `missing MOD source: shogunate_mod/skills/claude/.system/.codex-system-skills.marker`; fixed by excluding `*/.system/*` from generic directory sync.
- OBSERVED: full `prepublish_check.sh` then spent too long in Python while traversing Android source checks; fixed by changing Android sync from `rglob` to `os.walk` with directory pruning.
- PASS: `PYTHONDONTWRITEBYTECODE=1 python3 -m unittest tests.unit.test_package_distribution.PackageDistributionContractTests.test_android_source_has_mod_canonical_copy tests.unit.test_package_distribution.PackageDistributionContractTests.test_prepublish_requires_manifest_mod_sources_in_head` after excluding `.system` sync targets and pruning Android/HEAD-gate traversal.
- PASS: `bash -n shogunate_mod/package/prepublish_check.sh scripts/prepublish_check.sh` after excluding `.system` sync targets and pruning Android/HEAD-gate traversal.
- EXPECTED FAIL: `bash shogunate_mod/package/prepublish_check.sh` now reaches `require_manifest_mod_sources_in_head` in about 3 seconds and reports `310 manifest MOD canonical source files are missing from HEAD.` This is expected until the new `shogunate_mod/` canonical sources are committed.
- PASS: `PYTHONDONTWRITEBYTECODE=1 python3 -m unittest tests.unit.test_package_distribution` ran 62 tests after the prepublish runtime fixes.
- PASS: direct `diff -qr tests shogunate_mod/tests -x __pycache__ -x '*.pyc' -x '*.pyo'` confirmed root test compatibility files match MOD test sources after the prepublish runtime fixes.
- PASS: `git diff --check` after the prepublish runtime fixes. Git warned that touched `.bat` files will be normalized to CRLF when Git next touches them, but the check exited 0.
- PASS: `PYTHONDONTWRITEBYTECODE=1 python3 -m unittest tests.unit.test_package_distribution.PackageDistributionContractTests.test_release_workflow_builds_packages_not_installers_or_apks tests.unit.test_package_distribution.PackageDistributionContractTests.test_test_workflow_has_mod_canonical_copy` after fixing GitHub Release `target_commitish` to the validated release tag output.
- PASS: `bash -n shogunate_mod/package/prepublish_check.sh scripts/prepublish_check.sh` after fixing GitHub Release `target_commitish` to the validated release tag output.
- PASS: `PYTHONDONTWRITEBYTECODE=1 python3 -m unittest tests.unit.test_package_distribution` ran 62 tests after fixing GitHub Release `target_commitish` to the validated release tag output.
- PASS: direct `diff -qr tests shogunate_mod/tests -x __pycache__ -x '*.pyc' -x '*.pyo'` confirmed root test compatibility files match MOD test sources after fixing GitHub Release `target_commitish`.
- PASS: `git diff --check` after fixing GitHub Release `target_commitish`. Git warned that touched `.bat` files will be normalized to CRLF when Git next touches them, but the check exited 0.
- CHECKPOINT: commit `23bcb29` (`Split Shogunate mod sources from root wrappers`) added the MOD canonical source tree to `HEAD`.
- PASS: `bash shogunate_mod/package/prepublish_check.sh` after checkpoint commit `23bcb29`; the full release prepublish gate ran package distribution contract tests, verified generated instructions, and passed.
- PASS: isolated runtime smoke in temporary worktree `runtime_sandboxes/mod-smoke` with `SHOGUNATE_SESSION_NAME=mod-smoke-<timestamp>`, `LEGACY_GOZA_SESSION_NAME=mod-smoke-<timestamp>-legacy`, and `bash shutsujin_departure.sh -s -c`; tmux created the `goza` window with `shogun`, `gunkan`, `karo`, `gunshi`, and `ashigaru1` panes, wrote runtime queue files, and the temporary sessions/worktree were removed afterward.
- PASS: `./gradlew testDebugUnitTest assembleDebug` in `android/` on the synced root Android working tree.
- PASS: `./gradlew connectedDebugAndroidTest` in `android/` with connected device `661ecd40` (`OnePlus9Pro`).
- PASS: `PYTHONDONTWRITEBYTECODE=1 python3 -m unittest tests.unit.test_package_distribution.PackageDistributionContractTests.test_curl_bootstrap_is_release_package_aware` after adding the package URL override.
- PASS: `bash -n shogunate_mod/package/bootstrap.sh scripts/shogunate_package_bootstrap.sh` after adding the package URL override.
- PASS: `PYTHONDONTWRITEBYTECODE=1 python3 -m unittest tests.unit.test_package_distribution` ran 62 tests after adding the package URL override.
- PASS: direct `diff -qr tests shogunate_mod/tests -x __pycache__ -x '*.pyc' -x '*.pyo'` confirmed root test compatibility files match MOD test sources after adding the package URL override.
- PASS: `git diff --check` after adding the package URL override.
- PASS: local release-channel smoke using `git archive --format=tar.gz --prefix=multi-agent-shognate/ HEAD` and `SHOGUNATE_PACKAGE_URL=file://... bash shogunate_mod/package/bootstrap.sh --version v0.0.0-local --prefix <sandbox-home>/.shogunate/shogunate --bin-dir <sandbox-home>/.local/bin --no-setup`; verified `shogunate help`, `shogunate where --project <project>`, engine/runtime `shogunate_mod/manifest.yaml`, and `queue/runtime/{target_project,engine_dir}`.
- PASS: package-installed runtime smoke using a local release archive, isolated `HOME`, isolated `SHOGUNATE_WORKSPACE_HOME`, and unique `SHOGUNATE_SESSION_NAME`; `shogunate clean --project <project> --no-attach -s` created the project runtime tmux session through the installed command, wrote `queue/runtime/{target_project,engine_dir,session_name}`, created role panes for `shogun`, `gunkan`, `karo`, `gunshi`, and `ashigaru1`, and did not print the old `指示書再生成スクリプトが見つからない` warning.
- PASS: package-installed Pair smoke using a local release archive, isolated `HOME`, sandbox `--authorized-keys`, fixed `--pair-password`, `--no-usb`, `--no-start-runtime`, and `--client-ssh-port 22222`; `shogunate pair --project <project>` served `/pair`, accepted an Android-style public key, wrote exactly the sandbox authorized key, returned `project` as the project runtime copy and `target_project` as the requested project, returned port `22222`, printed `Pairing complete.`, and stopped automatically after success.
- OBSERVED: package-installed two-project runtime smoke initially showed project A session disappearing after project B startup because `tmux kill-session -t shogun` prefix-matched `shogunate-project-alpha-*`.
- PASS: `PYTHONDONTWRITEBYTECODE=1 python3 -m unittest tests.unit.test_package_distribution.PackageDistributionContractTests.test_runtime_cleanup_uses_exact_tmux_session_targets` after adding exact tmux cleanup target coverage.
- PASS: `bash -n shogunate_mod/runtime/state.sh shogunate_mod/runtime/android_compat.sh` after switching runtime cleanup helpers to exact tmux targets.
- PASS: `PYTHONDONTWRITEBYTECODE=1 python3 -m unittest tests.unit.test_package_distribution` ran 63 tests after adding exact tmux cleanup target coverage.
- PASS: direct `diff -qr tests shogunate_mod/tests -x __pycache__ -x '*.pyc' -x '*.pyo'` confirmed root test compatibility files match MOD test sources after adding exact tmux cleanup target coverage.
- PASS: `git diff --check` after adding exact tmux cleanup target coverage.
- PASS: package-installed two-project runtime smoke using a local `git archive HEAD` release package, isolated `HOME`, and isolated `SHOGUNATE_WORKSPACE_HOME`; project alpha and beta produced distinct `shogunate-project-alpha-aed8c4f9` / `shogunate-project-beta-503c296b` tmux sessions concurrently, each with `shogun`, `gunkan`, `karo`, `gunshi`, and `ashigaru1` panes, and each runtime metadata pointed at its own target project.
- PASS: targeted package distribution contract checks for MOD philosophy sync, runtime npm package boundary, release archive export-ignore, and MOD canonical source archive inclusion after moving `docs/philosophy.md` to MOD ownership and excluding `docs/vps_pr118_verification_plan.md` from cURL release archives.
- PASS: `PYTHONDONTWRITEBYTECODE=1 python3 -m unittest tests.unit.test_package_distribution` ran 63 tests after adding MOD philosophy ownership and VPS verification-log release archive exclusion.
- PASS: `PYTHONDONTWRITEBYTECODE=1 python3 -m unittest tests.unit.test_package_distribution.PackageDistributionContractTests.test_package_archive_excludes_android_app` after excluding `docs/INDEX.md` from cURL release archives.
- PASS: `PYTHONDONTWRITEBYTECODE=1 python3 -m unittest tests.unit.test_package_distribution` ran 63 tests after adding `docs/INDEX.md` release archive exclusion coverage.
- PASS: `PYTHONDONTWRITEBYTECODE=1 python3 -m unittest tests.unit.test_package_distribution.PackageDistributionContractTests.test_release_archive_docs_boundary_is_explicit` after adding the dynamic tracked-docs release archive boundary contract.
- PASS: `PYTHONDONTWRITEBYTECODE=1 python3 -m unittest tests.unit.test_package_distribution` ran 64 tests after adding the dynamic tracked-docs release archive boundary contract.
- PASS: targeted package distribution contract checks for cURL release archive exclusion of `shogunate_mod/github/FUNDING.yml` and `shogunate_mod/development/gitmodules`, while keeping runtime-facing `shogunate_mod/development/Makefile` unspecified.
- PASS: `git archive --worktree-attributes --format=tar HEAD | tar -tf - | rg '^(shogunate_mod/github/FUNDING.yml|shogunate_mod/development/gitmodules)$' || true` returned no paths after excluding MOD metadata from cURL release archives.
- PASS: `PYTHONDONTWRITEBYTECODE=1 python3 -m unittest tests.unit.test_package_distribution` ran 64 tests after adding MOD metadata release archive exclusions.
- PASS: `git archive --worktree-attributes --format=tar HEAD | tar -tf - | rg '^config/(opencode-permissions.yaml|opencode-tui.json)$'` confirmed cURL release archives retain the root OpenCode guard config compatibility files.
- PASS: `PYTHONDONTWRITEBYTECODE=1 python3 -m unittest tests.unit.test_package_distribution` ran 64 tests after adding positive release archive coverage for root OpenCode guard config files.
- PASS: `PYTHONDONTWRITEBYTECODE=1 python3 -m unittest tests.unit.test_package_distribution.PackageDistributionContractTests.test_release_archive_actual_runtime_boundary` after adding actual `git archive --worktree-attributes` content checks for cURL release archives.
- PASS: `PYTHONDONTWRITEBYTECODE=1 python3 -m unittest tests.unit.test_package_distribution` ran 65 tests after adding actual release archive content checks.
- PASS: `PYTHONDONTWRITEBYTECODE=1 python3 -m unittest tests.unit.test_package_distribution.PackageDistributionContractTests.test_release_archive_root_wrappers_match_manifest` after adding cURL release archive root wrapper surface coverage.
- PASS: `PYTHONDONTWRITEBYTECODE=1 python3 -m unittest tests.unit.test_package_distribution` ran 66 tests after adding cURL release archive root wrapper surface coverage.
- PASS: `PYTHONDONTWRITEBYTECODE=1 python3 -m unittest tests.unit.test_package_distribution.PackageDistributionContractTests.test_release_archive_root_instructions_are_mod_source_or_freshness_targets` after adding cURL release archive root instruction source/freshness coverage.
- PASS: `PYTHONDONTWRITEBYTECODE=1 python3 -m unittest tests.unit.test_package_distribution` ran 67 tests after adding cURL release archive root instruction source/freshness coverage.
- PASS: `PYTHONDONTWRITEBYTECODE=1 python3 -m unittest tests.unit.test_package_distribution.PackageDistributionContractTests.test_release_archive_generated_root_files_are_freshness_targets` after adding cURL release archive generated root touchpoint freshness coverage.
- PASS: `PYTHONDONTWRITEBYTECODE=1 python3 -m unittest tests.unit.test_package_distribution` ran 68 tests after adding cURL release archive generated root touchpoint freshness coverage.
- PASS: `PYTHONDONTWRITEBYTECODE=1 python3 -m unittest tests.unit.test_package_distribution.PackageDistributionContractTests.test_release_archive_top_level_launchers_match_manifest_wrappers` after adding cURL release archive top-level launcher wrapper coverage.
- PASS: `PYTHONDONTWRITEBYTECODE=1 python3 -m unittest tests.unit.test_package_distribution` ran 69 tests after adding cURL release archive top-level launcher wrapper coverage.
- PASS: direct `diff -q tests/unit/test_package_distribution.py shogunate_mod/tests/unit/test_package_distribution.py` confirmed root test compatibility file matches MOD test source after adding top-level launcher wrapper coverage.
- PASS: `bash -n shogunate_mod/package/prepublish_check.sh scripts/prepublish_check.sh` after adding top-level launcher wrapper coverage.
- PASS: `git diff --check` after adding top-level launcher wrapper coverage.
- PASS: `PYTHONDONTWRITEBYTECODE=1 python3 -m unittest tests.unit.test_package_distribution.PackageDistributionContractTests.test_npm_pack_top_level_launchers_match_manifest_wrappers` after adding npm package top-level launcher wrapper coverage.
- PASS: `PYTHONDONTWRITEBYTECODE=1 python3 -m unittest tests.unit.test_package_distribution` ran 70 tests after adding npm package top-level launcher wrapper coverage.
- PASS: direct `diff -q tests/unit/test_package_distribution.py shogunate_mod/tests/unit/test_package_distribution.py` confirmed root test compatibility file matches MOD test source after adding npm top-level launcher wrapper coverage.
- PASS: `bash -n shogunate_mod/package/prepublish_check.sh scripts/prepublish_check.sh` after adding npm top-level launcher wrapper coverage.
- PASS: `git diff --check` after adding npm top-level launcher wrapper coverage.
- PASS: `PYTHONDONTWRITEBYTECODE=1 python3 -m unittest tests.unit.test_package_distribution.PackageDistributionContractTests.test_npm_pack_top_level_launchers_match_manifest_wrappers tests.unit.test_package_distribution.PackageDistributionContractTests.test_release_archive_top_level_launchers_match_manifest_wrappers` after strengthening top-level launcher wrapper coverage to compare from actual npm/cURL archive contents.
- PASS: `PYTHONDONTWRITEBYTECODE=1 python3 -m unittest tests.unit.test_package_distribution` ran 70 tests after strengthening top-level launcher wrapper coverage.
- PASS: direct `diff -q tests/unit/test_package_distribution.py shogunate_mod/tests/unit/test_package_distribution.py` confirmed root test compatibility file matches MOD test source after strengthening launcher wrapper coverage.
- PASS: `bash -n shogunate_mod/package/prepublish_check.sh scripts/prepublish_check.sh` after strengthening launcher wrapper coverage.
- PASS: `git diff --check` after strengthening launcher wrapper coverage.
- PASS: `PYTHONDONTWRITEBYTECODE=1 python3 -m unittest tests.unit.test_package_distribution.PackageDistributionContractTests.test_npm_pack_root_config_surface_is_only_public_auth_sample tests.unit.test_package_distribution.PackageDistributionContractTests.test_release_archive_root_config_surface_is_runtime_defaults_only` after adding exact root config package/archive surface coverage.
- PASS: `PYTHONDONTWRITEBYTECODE=1 python3 -m unittest tests.unit.test_package_distribution` ran 72 tests after adding root config surface coverage.
- PASS: direct `diff -q tests/unit/test_package_distribution.py shogunate_mod/tests/unit/test_package_distribution.py` confirmed root test compatibility file matches MOD test source after adding root config surface coverage.
- PASS: `bash -n shogunate_mod/package/prepublish_check.sh scripts/prepublish_check.sh` after adding root config surface coverage.
- PASS: `git diff --check` after adding root config surface coverage.
- PASS: `PYTHONDONTWRITEBYTECODE=1 python3 -m unittest tests.unit.test_package_distribution.PackageDistributionContractTests.test_npm_pack_root_dot_compatibility_surface_is_explicit tests.unit.test_package_distribution.PackageDistributionContractTests.test_release_archive_root_dot_compatibility_surface_is_explicit` after adding exact root dot-directory compatibility surface coverage.
- PASS: `PYTHONDONTWRITEBYTECODE=1 python3 -m unittest tests.unit.test_package_distribution` ran 74 tests after adding root dot-directory compatibility surface coverage.
- PASS: direct `diff -q tests/unit/test_package_distribution.py shogunate_mod/tests/unit/test_package_distribution.py` confirmed root test compatibility file matches MOD test source after adding dot-directory surface coverage.
- PASS: `bash -n shogunate_mod/package/prepublish_check.sh scripts/prepublish_check.sh` after adding dot-directory surface coverage.
- PASS: `git diff --check` after adding dot-directory surface coverage.
- PASS: `PYTHONDONTWRITEBYTECODE=1 python3 -m unittest tests.unit.test_package_distribution.PackageDistributionContractTests.test_npm_pack_top_level_file_surface_is_explicit tests.unit.test_package_distribution.PackageDistributionContractTests.test_release_archive_top_level_file_surface_is_explicit` after adding exact top-level runtime file surface coverage.
- PASS: `PYTHONDONTWRITEBYTECODE=1 python3 -m unittest tests.unit.test_package_distribution` ran 76 tests after adding top-level runtime file surface coverage.
- PASS: direct `diff -q tests/unit/test_package_distribution.py shogunate_mod/tests/unit/test_package_distribution.py` confirmed root test compatibility file matches MOD test source after adding top-level file surface coverage.
- PASS: `bash -n shogunate_mod/package/prepublish_check.sh scripts/prepublish_check.sh` after adding top-level file surface coverage.
- PASS: `git diff --check` after adding top-level file surface coverage.
- PASS: `PYTHONDONTWRITEBYTECODE=1 python3 -m unittest tests.unit.test_package_distribution.PackageDistributionContractTests.test_npm_pack_root_directory_surface_is_explicit tests.unit.test_package_distribution.PackageDistributionContractTests.test_release_archive_root_directory_surface_is_explicit` after adding exact root directory surface coverage.
- PASS: `PYTHONDONTWRITEBYTECODE=1 python3 -m unittest tests.unit.test_package_distribution` ran 78 tests after adding root directory surface coverage.
- PASS: direct `diff -q tests/unit/test_package_distribution.py shogunate_mod/tests/unit/test_package_distribution.py` confirmed root test compatibility file matches MOD test source after adding root directory surface coverage.
- PASS: `bash -n shogunate_mod/package/prepublish_check.sh scripts/prepublish_check.sh` after adding root directory surface coverage.
- PASS: `git diff --check` after adding root directory surface coverage.
- PASS: `PYTHONDONTWRITEBYTECODE=1 python3 -m unittest tests.unit.test_package_distribution.PackageDistributionContractTests.test_package_root_directory_surface_is_declared_by_manifest` after requiring root directory surface to be declared by manifest.
- PASS: `PYTHONDONTWRITEBYTECODE=1 python3 -m unittest tests.unit.test_package_distribution` ran 79 tests after requiring manifest declaration for root directory surface.
- PASS: direct `diff -q tests/unit/test_package_distribution.py shogunate_mod/tests/unit/test_package_distribution.py` confirmed root test compatibility file matches MOD test source after adding manifest declaration coverage.
- PASS: `bash -n shogunate_mod/package/prepublish_check.sh scripts/prepublish_check.sh` after adding manifest declaration coverage.
- PASS: `git diff --check` after adding manifest declaration coverage.
- PASS: `PYTHONDONTWRITEBYTECODE=1 python3 -m unittest tests.unit.test_package_distribution.PackageDistributionContractTests.test_package_top_level_file_surface_is_declared_by_manifest` after adding `LICENSE` as a root public metadata touchpoint and requiring top-level file surface to be manifest-declared.
- PASS: `PYTHONDONTWRITEBYTECODE=1 python3 -m unittest tests.unit.test_package_distribution` ran 80 tests after adding top-level file manifest declaration coverage.
- PASS: direct `diff -q tests/unit/test_package_distribution.py shogunate_mod/tests/unit/test_package_distribution.py` confirmed root test compatibility file matches MOD test source after adding top-level file manifest declaration coverage.
- PASS: `bash -n shogunate_mod/package/prepublish_check.sh scripts/prepublish_check.sh` after adding top-level file manifest declaration coverage.
- PASS: `git diff --check` after adding top-level file manifest declaration coverage.
- PASS: `PYTHONDONTWRITEBYTECODE=1 python3 -m unittest tests.unit.test_package_distribution.PackageDistributionContractTests.test_manifest_directory_touchpoints_excluded_from_package_surface_are_explicit` after adding explicit classification for manifest root directory touchpoints excluded from package/archive surfaces.
- PASS: direct `diff -q tests/unit/test_package_distribution.py shogunate_mod/tests/unit/test_package_distribution.py` confirmed root test compatibility file matches MOD test source after adding excluded-directory touchpoint classification.
- PASS: `PYTHONDONTWRITEBYTECODE=1 python3 -m unittest tests.unit.test_package_distribution` ran 81 tests after adding excluded-directory touchpoint classification.
- PASS: `bash -n shogunate_mod/package/prepublish_check.sh scripts/prepublish_check.sh` after adding excluded-directory touchpoint classification.
- PASS: `git diff --check` after adding excluded-directory touchpoint classification.
- PASS: `PYTHONDONTWRITEBYTECODE=1 python3 -m unittest tests.unit.test_package_distribution.PackageDistributionContractTests.test_manifest_top_level_file_touchpoints_excluded_from_package_surface_are_explicit` after adding explicit classification for manifest top-level file touchpoints excluded from package/archive surfaces.
- PASS: direct `diff -q tests/unit/test_package_distribution.py shogunate_mod/tests/unit/test_package_distribution.py` confirmed root test compatibility file matches MOD test source after adding excluded-top-level-file touchpoint classification.
- PASS: `PYTHONDONTWRITEBYTECODE=1 python3 -m unittest tests.unit.test_package_distribution` ran 82 tests after adding excluded-top-level-file touchpoint classification.
- PASS: `bash -n shogunate_mod/package/prepublish_check.sh scripts/prepublish_check.sh` after adding excluded-top-level-file touchpoint classification.
- PASS: `git diff --check` after adding excluded-top-level-file touchpoint classification.
- PASS: `PYTHONDONTWRITEBYTECODE=1 python3 -m unittest tests.unit.test_package_distribution.PackageDistributionContractTests.test_manifest_directory_touchpoints_excluded_from_package_surface_are_explicit` after extending excluded root touchpoint classification to nested manifest paths.
- PASS: direct `diff -q tests/unit/test_package_distribution.py shogunate_mod/tests/unit/test_package_distribution.py` confirmed root test compatibility file matches MOD test source after extending nested root touchpoint classification.
- PASS: `PYTHONDONTWRITEBYTECODE=1 python3 -m unittest tests.unit.test_package_distribution` ran 82 tests after extending nested root touchpoint classification.
- PASS: `bash -n shogunate_mod/package/prepublish_check.sh scripts/prepublish_check.sh` after extending nested root touchpoint classification.
- PASS: `git diff --check` after extending nested root touchpoint classification.
- PASS: `PYTHONDONTWRITEBYTECODE=1 python3 -m unittest tests.unit.test_package_distribution.PackageDistributionContractTests.test_manifest_canonical_paths_are_mod_scoped` after adding the MOD-scoped canonical path contract.
- PASS: direct `diff -q tests/unit/test_package_distribution.py shogunate_mod/tests/unit/test_package_distribution.py` confirmed root test compatibility file matches MOD test source after adding the MOD-scoped canonical path contract.
- PASS: `PYTHONDONTWRITEBYTECODE=1 python3 -m unittest tests.unit.test_package_distribution` ran 83 tests after adding the MOD-scoped canonical path contract.
- PASS: `bash -n shogunate_mod/package/prepublish_check.sh scripts/prepublish_check.sh` after adding the MOD-scoped canonical path contract.
- PASS: `git diff --check` after adding the MOD-scoped canonical path contract.
- PASS: `PYTHONDONTWRITEBYTECODE=1 python3 -m unittest tests.unit.test_package_distribution.PackageDistributionContractTests.test_manifest_current_core_touchpoints_stay_on_root_surface` after adding the root-surface current core touchpoint contract.
- PASS: direct `diff -q tests/unit/test_package_distribution.py shogunate_mod/tests/unit/test_package_distribution.py` confirmed root test compatibility file matches MOD test source after adding the root-surface current core touchpoint contract.
- PASS: `PYTHONDONTWRITEBYTECODE=1 python3 -m unittest tests.unit.test_package_distribution` ran 84 tests after adding the root-surface current core touchpoint contract.
- PASS: `bash -n shogunate_mod/package/prepublish_check.sh scripts/prepublish_check.sh` after adding the root-surface current core touchpoint contract.
- PASS: `git diff --check` after adding the root-surface current core touchpoint contract.
- PASS: `PYTHONDONTWRITEBYTECODE=1 python3 -m unittest tests.unit.test_package_distribution.PackageDistributionContractTests.test_mod_readme_boundary_paths_are_manifest_canonical tests.unit.test_package_distribution.PackageDistributionContractTests.test_manifest_canonical_directories_have_mod_readme_boundaries` after tying MOD README boundary ownership to manifest canonical paths.
- PASS: direct `diff -q tests/unit/test_package_distribution.py shogunate_mod/tests/unit/test_package_distribution.py` confirmed root test compatibility file matches MOD test source after tying MOD README boundaries to manifest canonical paths.
- PASS: `PYTHONDONTWRITEBYTECODE=1 python3 -m unittest tests.unit.test_package_distribution` ran 86 tests after tying MOD README boundaries to manifest canonical paths.
- PASS: `bash -n shogunate_mod/package/prepublish_check.sh scripts/prepublish_check.sh` after tying MOD README boundaries to manifest canonical paths.
- PASS: `git diff --check` after tying MOD README boundaries to manifest canonical paths.
- PASS: `PYTHONDONTWRITEBYTECODE=1 python3 -m unittest tests.unit.test_package_distribution.PackageDistributionContractTests.test_release_archive_actual_runtime_boundary` after requiring MOD manifest and MOD README in cURL release archives.
- PASS: direct `diff -q tests/unit/test_package_distribution.py shogunate_mod/tests/unit/test_package_distribution.py` confirmed root test compatibility file matches MOD test source after requiring MOD manifest and MOD README in cURL release archives.
- PASS: `PYTHONDONTWRITEBYTECODE=1 python3 -m unittest tests.unit.test_package_distribution` ran 86 tests after requiring MOD manifest and MOD README in cURL release archives.
- PASS: `bash -n shogunate_mod/package/prepublish_check.sh scripts/prepublish_check.sh` after requiring MOD manifest and MOD README in cURL release archives.
- PASS: `git diff --check` after requiring MOD manifest and MOD README in cURL release archives.
- PASS: `PYTHONDONTWRITEBYTECODE=1 python3 -m unittest tests.unit.test_package_distribution.PackageDistributionContractTests.test_tracked_root_wrapper_surface_matches_manifest` after requiring tracked root wrapper surface to match manifest compatibility wrappers.
- PASS: direct `diff -q tests/unit/test_package_distribution.py shogunate_mod/tests/unit/test_package_distribution.py` confirmed root test compatibility file matches MOD test source after requiring tracked root wrapper surface to match manifest compatibility wrappers.
- PASS: `PYTHONDONTWRITEBYTECODE=1 python3 -m unittest tests.unit.test_package_distribution` ran 87 tests after requiring tracked root wrapper surface to match manifest compatibility wrappers.
- PASS: `bash -n shogunate_mod/package/prepublish_check.sh scripts/prepublish_check.sh` after requiring tracked root wrapper surface to match manifest compatibility wrappers.
- PASS: `git diff --check` after requiring tracked root wrapper surface to match manifest compatibility wrappers.
- PASS: `PYTHONDONTWRITEBYTECODE=1 python3 -m unittest tests.unit.test_package_distribution.PackageDistributionContractTests.test_prepublish_sync_pairs_flow_from_root_compatibility_to_mod_source` after requiring prepublish sync pairs to flow from root compatibility paths to MOD canonical source paths.
- PASS: direct `diff -q tests/unit/test_package_distribution.py shogunate_mod/tests/unit/test_package_distribution.py` confirmed root test compatibility file matches MOD test source after requiring prepublish sync direction.
- PASS: `PYTHONDONTWRITEBYTECODE=1 python3 -m unittest tests.unit.test_package_distribution` ran 88 tests after requiring prepublish sync direction.
- PASS: `bash -n shogunate_mod/package/prepublish_check.sh scripts/prepublish_check.sh` after requiring prepublish sync direction.
- PASS: `git diff --check` after requiring prepublish sync direction.
- PASS: `PYTHONDONTWRITEBYTECODE=1 python3 -m unittest tests.unit.test_package_distribution.PackageDistributionContractTests.test_non_synchronized_core_touchpoints_are_explicitly_classified` after requiring non-synchronized current core touchpoints to be classified as generated output, root public metadata, or release-archive excluded.
- PASS: direct `diff -q tests/unit/test_package_distribution.py shogunate_mod/tests/unit/test_package_distribution.py` confirmed root test compatibility file matches MOD test source after requiring non-synchronized touchpoint classification.
- PASS: `PYTHONDONTWRITEBYTECODE=1 python3 -m unittest tests.unit.test_package_distribution` ran 89 tests after requiring non-synchronized touchpoint classification.
- PASS: `bash -n shogunate_mod/package/prepublish_check.sh scripts/prepublish_check.sh` after requiring non-synchronized touchpoint classification.
- PASS: `git diff --check` after requiring non-synchronized touchpoint classification.
- PASS: `PYTHONDONTWRITEBYTECODE=1 python3 -m unittest tests.unit.test_package_distribution.PackageDistributionContractTests.test_manifest_sections_do_not_repeat_entries` after requiring manifest sections to avoid duplicate keys and path entries.
- PASS: direct `diff -q tests/unit/test_package_distribution.py shogunate_mod/tests/unit/test_package_distribution.py` confirmed root test compatibility file matches MOD test source after requiring manifest duplicate-free sections.
- PASS: `PYTHONDONTWRITEBYTECODE=1 python3 -m unittest tests.unit.test_package_distribution` ran 90 tests after requiring manifest duplicate-free sections.
- PASS: `bash -n shogunate_mod/package/prepublish_check.sh scripts/prepublish_check.sh` after requiring manifest duplicate-free sections.
- PASS: `git diff --check` after requiring manifest duplicate-free sections.
- PASS: `PYTHONDONTWRITEBYTECODE=1 python3 -m unittest tests.unit.test_package_distribution.PackageDistributionContractTests.test_manifest_paths_use_normalized_relative_forms` after requiring normalized relative manifest paths and trailing slash conventions.
- PASS: direct `diff -q tests/unit/test_package_distribution.py shogunate_mod/tests/unit/test_package_distribution.py` confirmed root test compatibility file matches MOD test source after requiring normalized manifest path forms.
- PASS: `PYTHONDONTWRITEBYTECODE=1 python3 -m unittest tests.unit.test_package_distribution` ran 91 tests after requiring normalized manifest path forms.
- PASS: `bash -n shogunate_mod/package/prepublish_check.sh scripts/prepublish_check.sh` after requiring normalized manifest path forms.
- PASS: `git diff --check` after requiring normalized manifest path forms.
- PASS: `PYTHONDONTWRITEBYTECODE=1 python3 -m unittest tests.unit.test_package_distribution.PackageDistributionContractTests.test_prepublish_sync_pairs_do_not_duplicate_nested_roots tests.unit.test_package_distribution.PackageDistributionContractTests.test_prepublish_sync_targets_are_tracked_by_manifest tests.unit.test_package_distribution.PackageDistributionContractTests.test_synchronized_core_touchpoints_have_prepublish_gates` after collapsing redundant `tests/` prepublish sync gates.
- PASS: `PYTHONDONTWRITEBYTECODE=1 python3 -m unittest tests.unit.test_package_distribution` ran 92 tests after collapsing redundant `tests/` prepublish sync gates.
- PASS: direct `diff -q tests/unit/test_package_distribution.py shogunate_mod/tests/unit/test_package_distribution.py` confirmed root test compatibility file matches MOD test source after collapsing redundant `tests/` prepublish sync gates.
- PASS: `bash -n shogunate_mod/package/prepublish_check.sh scripts/prepublish_check.sh` after collapsing redundant `tests/` prepublish sync gates.
- PASS: `git diff --check` after collapsing redundant `tests/` prepublish sync gates.
- PASS: `PYTHONDONTWRITEBYTECODE=1 python3 -m unittest tests.unit.test_package_distribution.PackageDistributionContractTests.test_manifest_nested_canonical_paths_are_limited_to_test_subsections tests.unit.test_package_distribution.PackageDistributionContractTests.test_manifest_sections_do_not_repeat_entries tests.unit.test_package_distribution.PackageDistributionContractTests.test_manifest_paths_use_normalized_relative_forms` after limiting nested manifest canonical paths to test subsections.
- PASS: `PYTHONDONTWRITEBYTECODE=1 python3 -m unittest tests.unit.test_package_distribution` ran 93 tests after limiting nested manifest canonical paths to test subsections.
- PASS: direct `diff -q tests/unit/test_package_distribution.py shogunate_mod/tests/unit/test_package_distribution.py` confirmed root test compatibility file matches MOD test source after limiting nested manifest canonical paths to test subsections.
- PASS: `bash -n shogunate_mod/package/prepublish_check.sh scripts/prepublish_check.sh` after limiting nested manifest canonical paths to test subsections.
- PASS: `git diff --check` after limiting nested manifest canonical paths to test subsections.
- PASS: `PYTHONDONTWRITEBYTECODE=1 python3 -m unittest tests.unit.test_package_distribution.PackageDistributionContractTests.test_synchronized_core_touchpoints_are_covered_by_prepublish_sync tests.unit.test_package_distribution.PackageDistributionContractTests.test_synchronized_core_touchpoints_have_prepublish_gates tests.unit.test_package_distribution.PackageDistributionContractTests.test_non_synchronized_core_touchpoints_are_explicitly_classified` after adding dynamic prepublish coverage for synchronized manifest touchpoints.
- PASS: `PYTHONDONTWRITEBYTECODE=1 python3 -m unittest tests.unit.test_package_distribution` ran 94 tests after adding dynamic prepublish coverage for synchronized manifest touchpoints.
- PASS: direct `diff -q tests/unit/test_package_distribution.py shogunate_mod/tests/unit/test_package_distribution.py` confirmed root test compatibility file matches MOD test source after adding dynamic prepublish coverage for synchronized manifest touchpoints.
- PASS: `bash -n shogunate_mod/package/prepublish_check.sh scripts/prepublish_check.sh` after adding dynamic prepublish coverage for synchronized manifest touchpoints.
- PASS: `git diff --check` after adding dynamic prepublish coverage for synchronized manifest touchpoints.
- PASS: `PYTHONDONTWRITEBYTECODE=1 python3 -m unittest tests.unit.test_package_distribution.PackageDistributionContractTests.test_generated_freshness_targets_are_manifest_classified tests.unit.test_package_distribution.PackageDistributionContractTests.test_generated_root_touchpoints_are_freshness_targets tests.unit.test_package_distribution.PackageDistributionContractTests.test_non_synchronized_core_touchpoints_are_explicitly_classified` after requiring generated freshness targets to be manifest-classified.
- PASS: `PYTHONDONTWRITEBYTECODE=1 python3 -m unittest tests.unit.test_package_distribution` ran 95 tests after requiring generated freshness targets to be manifest-classified.
- PASS: direct `diff -q tests/unit/test_package_distribution.py shogunate_mod/tests/unit/test_package_distribution.py` confirmed root test compatibility file matches MOD test source after requiring generated freshness targets to be manifest-classified.
- PASS: `bash -n shogunate_mod/package/prepublish_check.sh scripts/prepublish_check.sh` after requiring generated freshness targets to be manifest-classified.
- PASS: `git diff --check` after requiring generated freshness targets to be manifest-classified.
- PASS: `PYTHONDONTWRITEBYTECODE=1 python3 -m unittest tests.unit.test_package_distribution.PackageDistributionContractTests.test_release_archive_includes_all_manifest_compatibility_wrappers tests.unit.test_package_distribution.PackageDistributionContractTests.test_release_archive_actual_runtime_boundary` after requiring release archives to include every manifest compatibility wrapper.
- PASS: `PYTHONDONTWRITEBYTECODE=1 python3 -m unittest tests.unit.test_package_distribution` ran 96 tests after requiring release archives to include every manifest compatibility wrapper.
- PASS: direct `diff -q tests/unit/test_package_distribution.py shogunate_mod/tests/unit/test_package_distribution.py` confirmed root test compatibility file matches MOD test source after requiring release archives to include every manifest compatibility wrapper.
- PASS: `bash -n shogunate_mod/package/prepublish_check.sh scripts/prepublish_check.sh` after requiring release archives to include every manifest compatibility wrapper.
- PASS: `git diff --check` after requiring release archives to include every manifest compatibility wrapper.
- PASS: `PYTHONDONTWRITEBYTECODE=1 python3 -m unittest tests.unit.test_package_distribution.PackageDistributionContractTests.test_package_archive_excludes_android_app tests.unit.test_package_distribution.PackageDistributionContractTests.test_release_archive_includes_runtime_mod_canonical_sources` after restoring `shogunate_mod/queue/` to cURL release archives.
- PASS: `PYTHONDONTWRITEBYTECODE=1 python3 -m unittest tests.unit.test_package_distribution` ran 96 tests after restoring `shogunate_mod/queue/` to cURL release archives.
- PASS: direct `diff -q tests/unit/test_package_distribution.py shogunate_mod/tests/unit/test_package_distribution.py` confirmed root test compatibility file matches MOD test source after restoring `shogunate_mod/queue/` to cURL release archives.
- PASS: `bash -n shogunate_mod/package/prepublish_check.sh scripts/prepublish_check.sh` after restoring `shogunate_mod/queue/` to cURL release archives.
- PASS: `git diff --check` after restoring `shogunate_mod/queue/` to cURL release archives.
- PASS: `PYTHONDONTWRITEBYTECODE=1 python3 -m unittest tests.unit.test_package_distribution.PackageDistributionContractTests.test_manifest_compatibility_wrapper_targets_are_canonical_paths tests.unit.test_package_distribution.PackageDistributionContractTests.test_release_archive_includes_manifest_wrapper_delegate_targets tests.unit.test_package_distribution.PackageDistributionContractTests.test_release_archive_includes_all_manifest_compatibility_wrappers` after requiring wrapper delegate targets to be release-archive covered.
- PASS: `PYTHONDONTWRITEBYTECODE=1 python3 -m unittest tests.unit.test_package_distribution` ran 97 tests after requiring wrapper delegate targets to be release-archive covered.
- PASS: direct `diff -q tests/unit/test_package_distribution.py shogunate_mod/tests/unit/test_package_distribution.py` confirmed root test compatibility file matches MOD test source after requiring wrapper delegate targets to be release-archive covered.
- PASS: `bash -n shogunate_mod/package/prepublish_check.sh scripts/prepublish_check.sh` after requiring wrapper delegate targets to be release-archive covered.
- PASS: `git diff --check` after requiring wrapper delegate targets to be release-archive covered.
- PASS: `PYTHONDONTWRITEBYTECODE=1 python3 -m unittest tests.unit.test_package_distribution.PackageDistributionContractTests.test_npm_pack_includes_manifest_wrapper_delegate_targets tests.unit.test_package_distribution.PackageDistributionContractTests.test_release_archive_includes_manifest_wrapper_delegate_targets tests.unit.test_package_distribution.PackageDistributionContractTests.test_manifest_compatibility_wrapper_targets_are_canonical_paths` after requiring npm package coverage for wrapper delegate targets.
- PASS: `PYTHONDONTWRITEBYTECODE=1 python3 -m unittest tests.unit.test_package_distribution` ran 98 tests after requiring npm package coverage for wrapper delegate targets.
- PASS: direct `diff -q tests/unit/test_package_distribution.py shogunate_mod/tests/unit/test_package_distribution.py` confirmed root test compatibility file matches MOD test source after requiring npm package coverage for wrapper delegate targets.
- PASS: `bash -n shogunate_mod/package/prepublish_check.sh scripts/prepublish_check.sh` after requiring npm package coverage for wrapper delegate targets.
- PASS: `git diff --check` after requiring npm package coverage for wrapper delegate targets.
- PASS: `PYTHONDONTWRITEBYTECODE=1 python3 -m unittest tests.unit.test_package_distribution.PackageDistributionContractTests.test_npm_pack_covers_runtime_mod_manifest_sources tests.unit.test_package_distribution.PackageDistributionContractTests.test_prepublish_mod_sync_targets_are_packaged_unless_intentionally_excluded` after classifying intentionally unpacked npm MOD canonical paths.
- PASS: `PYTHONDONTWRITEBYTECODE=1 python3 -m unittest tests.unit.test_package_distribution` ran 98 tests after classifying intentionally unpacked npm MOD canonical paths.
- PASS: direct `diff -q tests/unit/test_package_distribution.py shogunate_mod/tests/unit/test_package_distribution.py` confirmed root test compatibility file matches MOD test source after classifying intentionally unpacked npm MOD canonical paths.
- PASS: `bash -n shogunate_mod/package/prepublish_check.sh scripts/prepublish_check.sh` after classifying intentionally unpacked npm MOD canonical paths.
- PASS: `git diff --check` after classifying intentionally unpacked npm MOD canonical paths.
- PASS: `PYTHONDONTWRITEBYTECODE=1 python3 -m unittest tests.unit.test_package_distribution.PackageDistributionContractTests.test_release_archive_includes_runtime_mod_canonical_sources tests.unit.test_package_distribution.PackageDistributionContractTests.test_release_archive_actual_runtime_boundary` after classifying intentionally excluded cURL release archive MOD canonical paths.
- PASS: `PYTHONDONTWRITEBYTECODE=1 python3 -m unittest tests.unit.test_package_distribution` ran 98 tests after classifying intentionally excluded cURL release archive MOD canonical paths.
- PASS: direct `diff -q tests/unit/test_package_distribution.py shogunate_mod/tests/unit/test_package_distribution.py` confirmed root test compatibility file matches MOD test source after classifying intentionally excluded cURL release archive MOD canonical paths.
- PASS: `bash -n shogunate_mod/package/prepublish_check.sh scripts/prepublish_check.sh` after classifying intentionally excluded cURL release archive MOD canonical paths.
- PASS: `git diff --check` after classifying intentionally excluded cURL release archive MOD canonical paths.
- PASS: `PYTHONDONTWRITEBYTECODE=1 python3 -m unittest tests.unit.test_package_distribution.PackageDistributionContractTests.test_manifest_compatibility_wrappers_stay_thin` after restricting Python compatibility wrappers to bootstrap-only imports and no local definitions.
- PASS: `PYTHONDONTWRITEBYTECODE=1 python3 -m unittest tests.unit.test_package_distribution` ran 98 tests after restricting Python compatibility wrappers to bootstrap-only imports and no local definitions.
- PASS: direct `diff -q tests/unit/test_package_distribution.py shogunate_mod/tests/unit/test_package_distribution.py` confirmed root test compatibility file matches MOD test source after restricting Python compatibility wrappers to bootstrap-only imports and no local definitions.
- PASS: `bash -n shogunate_mod/package/prepublish_check.sh scripts/prepublish_check.sh` after restricting Python compatibility wrappers to bootstrap-only imports and no local definitions.
- PASS: `git diff --check` after restricting Python compatibility wrappers to bootstrap-only imports and no local definitions.
- PASS: `PYTHONDONTWRITEBYTECODE=1 python3 -m unittest tests.unit.test_package_distribution.PackageDistributionContractTests.test_manifest_compatibility_wrappers_stay_thin` after extending wrapper bootstrap-only checks to shell function definitions and batch labels.
- PASS: `PYTHONDONTWRITEBYTECODE=1 python3 -m unittest tests.unit.test_package_distribution` ran 98 tests after extending wrapper bootstrap-only checks to shell function definitions and batch labels.
- PASS: direct `diff -q tests/unit/test_package_distribution.py shogunate_mod/tests/unit/test_package_distribution.py` confirmed root test compatibility file matches MOD test source after extending wrapper bootstrap-only checks.
- PASS: `bash -n shogunate_mod/package/prepublish_check.sh scripts/prepublish_check.sh` after extending wrapper bootstrap-only checks.
- PASS: `git diff --check` after extending wrapper bootstrap-only checks.
- PASS: `PYTHONDONTWRITEBYTECODE=1 python3 -m unittest tests.unit.test_package_distribution.PackageDistributionContractTests.test_manifest_compatibility_wrappers_stay_thin` after restricting JavaScript compatibility wrappers to MOD npm CLI delegation with no local JS definitions.
- PASS: `PYTHONDONTWRITEBYTECODE=1 python3 -m unittest tests.unit.test_package_distribution.PackageDistributionContractTests.test_tracked_root_code_like_files_are_classified_by_manifest` after requiring every tracked root code-like file outside `shogunate_mod/` to be manifest-classified.
- PASS: `PYTHONDONTWRITEBYTECODE=1 python3 -m unittest tests.unit.test_package_distribution.PackageDistributionContractTests.test_tracked_root_code_like_touchpoints_have_sync_or_generation_gate` after requiring non-wrapper root code-like touchpoints to be covered by prepublish sync or generated freshness gates.
- PASS: `PYTHONDONTWRITEBYTECODE=1 python3 -m unittest tests.unit.test_package_distribution.PackageDistributionContractTests.test_npm_pack_covers_runtime_mod_manifest_source_files` after requiring npm package file-level coverage for MOD canonical sources except Android/tests.
- PASS: `PYTHONDONTWRITEBYTECODE=1 python3 -m unittest tests.unit.test_package_distribution.PackageDistributionContractTests.test_mod_readme_boundary_directories_match_tracked_mod_sources` after requiring MOD README ownership boundaries to match tracked MOD top-level source directories.
- PASS: `PYTHONDONTWRITEBYTECODE=1 python3 -m unittest tests.unit.test_package_distribution.PackageDistributionContractTests.test_upstream_modified_root_code_like_files_are_classified_by_manifest` after requiring upstream-modified root code-like files to be manifest-classified when `upstream/main` is available.
- PASS: `PYTHONDONTWRITEBYTECODE=1 python3 -m unittest tests.unit.test_package_distribution.PackageDistributionContractTests.test_npm_pack_excludes_legacy_installer_surface tests.unit.test_package_distribution.PackageDistributionContractTests.test_release_archive_excludes_legacy_installer_surface` after requiring npm package and cURL release archive to exclude legacy installer surfaces.
- PASS: `PYTHONDONTWRITEBYTECODE=1 python3 -m unittest tests.unit.test_package_distribution.PackageDistributionContractTests.test_development_branch_keeps_upstream_main_as_ancestor` after requiring development checkouts with `upstream/main` to retain upstream ancestry.
- PASS: source checkout smoke in detached worktree `runtime_sandboxes/source-runtime-smoke-20260618060303` with `SHOGUNATE_PROJECT_DIR=<worktree>/target-project SHOGUNATE_SESSION_NAME=shogunate-mod-source-smoke-20260618060303 GOZA_SESSION_NAME=shogunate-mod-source-smoke-20260618060303 RUNTIME_DAEMON_SESSION=goza-runtime-shogunate-mod-source-smoke-20260618060303 MAS_BOOTSTRAP_READY_TIMEOUT=3 bash shutsujin_departure.sh -s -c`; verified MOD loader setup-only clean start created the `goza` tmux window, 5 role panes, 5 `queue/runtime/agent_cli.tsv` entries, `dashboard.md`, and matching tmux `@shogunate_project_dir` / `@shogunate_runtime_dir` metadata. The smoke-owned tmux sessions and worktree were removed after verification.
- PASS: `PYTHONDONTWRITEBYTECODE=1 python3 -m unittest tests.unit.test_package_distribution.PackageDistributionContractTests.test_curl_bootstrap_is_release_package_aware tests.unit.test_package_distribution.PackageDistributionContractTests.test_synchronized_core_touchpoints_have_prepublish_gates tests.unit.test_package_distribution.PackageDistributionContractTests.test_synchronized_core_touchpoints_are_covered_by_prepublish_sync tests.unit.test_package_distribution.PackageDistributionContractTests.test_prepublish_sync_targets_are_tracked_by_manifest tests.unit.test_package_distribution.PackageDistributionContractTests.test_prepublish_sync_pairs_flow_from_root_compatibility_to_mod_source tests.unit.test_package_distribution.PackageDistributionContractTests.test_instruction_sources_have_mod_canonical_copy tests.unit.test_package_distribution.PackageDistributionContractTests.test_cli_skills_have_mod_canonical_copy tests.unit.test_package_distribution.PackageDistributionContractTests.test_integration_templates_have_mod_canonical_copy tests.unit.test_package_distribution.PackageDistributionContractTests.test_codd_docs_have_mod_canonical_copy tests.unit.test_package_distribution.PackageDistributionContractTests.test_test_support_files_have_mod_canonical_copy` after making root/MOD directory sync gates bidirectional.
- PASS: `PYTHONDONTWRITEBYTECODE=1 python3 -m unittest tests.unit.test_package_distribution.PackageDistributionContractTests.test_android_source_has_mod_canonical_copy tests.unit.test_package_distribution.PackageDistributionContractTests.test_synchronized_core_touchpoints_have_prepublish_gates tests.unit.test_package_distribution.PackageDistributionContractTests.test_synchronized_core_touchpoints_are_covered_by_prepublish_sync tests.unit.test_package_distribution.PackageDistributionContractTests.test_prepublish_sync_targets_are_tracked_by_manifest tests.unit.test_package_distribution.PackageDistributionContractTests.test_test_support_files_have_mod_canonical_copy` after making Android source sync bidirectional.
- PASS: `PYTHONDONTWRITEBYTECODE=1 python3 -m unittest tests.unit.test_package_distribution.PackageDistributionContractTests.test_opencode_permissions_have_mod_canonical_copy tests.unit.test_package_distribution.PackageDistributionContractTests.test_prepublish_sync_targets_are_tracked_by_manifest tests.unit.test_package_distribution.PackageDistributionContractTests.test_prepublish_sync_pairs_flow_from_root_compatibility_to_mod_source tests.unit.test_package_distribution.PackageDistributionContractTests.test_synchronized_core_touchpoints_have_prepublish_gates tests.unit.test_package_distribution.PackageDistributionContractTests.test_test_support_files_have_mod_canonical_copy` after narrowing OpenCode permission matrix sync tolerance to the leading comment block.
- PASS: `PYTHONDONTWRITEBYTECODE=1 python3 -m unittest tests.unit.test_package_distribution.PackageDistributionContractTests.test_release_archive_mod_files_are_manifest_canonical tests.unit.test_package_distribution.PackageDistributionContractTests.test_release_archive_includes_runtime_mod_canonical_sources tests.unit.test_package_distribution.PackageDistributionContractTests.test_release_archive_actual_runtime_boundary tests.unit.test_package_distribution.PackageDistributionContractTests.test_test_support_files_have_mod_canonical_copy` after requiring cURL release archive MOD files to be manifest-canonical.
- PASS: `PYTHONDONTWRITEBYTECODE=1 python3 -m unittest tests.unit.test_package_distribution.PackageDistributionContractTests.test_npm_pack_mod_files_are_manifest_canonical tests.unit.test_package_distribution.PackageDistributionContractTests.test_npm_pack_covers_runtime_mod_manifest_source_files tests.unit.test_package_distribution.PackageDistributionContractTests.test_package_broad_entries_are_mod_canonical_sources tests.unit.test_package_distribution.PackageDistributionContractTests.test_test_support_files_have_mod_canonical_copy` after requiring npm package MOD files to be manifest-canonical.
- PASS: `PYTHONDONTWRITEBYTECODE=1 python3 -m unittest tests.unit.test_package_distribution.PackageDistributionContractTests.test_package_direct_mod_file_entries_are_manifest_canonical tests.unit.test_package_distribution.PackageDistributionContractTests.test_package_broad_entries_are_mod_canonical_sources tests.unit.test_package_distribution.PackageDistributionContractTests.test_npm_pack_mod_files_are_manifest_canonical tests.unit.test_package_distribution.PackageDistributionContractTests.test_test_support_files_have_mod_canonical_copy` after requiring direct MOD file entries in package metadata to be manifest-canonical.
- PASS: `PYTHONDONTWRITEBYTECODE=1 python3 -m unittest tests.unit.test_package_distribution.PackageDistributionContractTests.test_package_direct_root_file_entries_are_manifest_classified tests.unit.test_package_distribution.PackageDistributionContractTests.test_package_direct_mod_file_entries_are_manifest_canonical tests.unit.test_package_distribution.PackageDistributionContractTests.test_npm_pack_top_level_file_surface_is_explicit tests.unit.test_package_distribution.PackageDistributionContractTests.test_test_support_files_have_mod_canonical_copy` after requiring direct root file entries in package metadata to be manifest-classified.
- PASS: `PYTHONDONTWRITEBYTECODE=1 python3 -m unittest tests.unit.test_package_distribution.PackageDistributionContractTests.test_release_archive_root_code_like_files_are_manifest_classified tests.unit.test_package_distribution.PackageDistributionContractTests.test_release_archive_root_wrappers_match_manifest tests.unit.test_package_distribution.PackageDistributionContractTests.test_release_archive_top_level_file_surface_is_explicit tests.unit.test_package_distribution.PackageDistributionContractTests.test_test_support_files_have_mod_canonical_copy` after requiring root code-like files in cURL release archives to be manifest-classified.
- PASS: `PYTHONDONTWRITEBYTECODE=1 python3 -m unittest tests.unit.test_package_distribution.PackageDistributionContractTests.test_npm_pack_root_code_like_files_are_manifest_classified tests.unit.test_package_distribution.PackageDistributionContractTests.test_npm_pack_root_scripts_are_manifest_compatibility_wrappers tests.unit.test_package_distribution.PackageDistributionContractTests.test_npm_pack_top_level_file_surface_is_explicit tests.unit.test_package_distribution.PackageDistributionContractTests.test_test_support_files_have_mod_canonical_copy` after requiring root code-like files in npm packages to be manifest-classified.
- PASS: `PYTHONDONTWRITEBYTECODE=1 python3 -m unittest tests.unit.test_package_distribution.PackageDistributionContractTests.test_packaged_mod_directories_have_readme_boundaries tests.unit.test_package_distribution.PackageDistributionContractTests.test_mod_readme_boundary_directories_match_tracked_mod_sources tests.unit.test_package_distribution.PackageDistributionContractTests.test_manifest_canonical_directories_have_mod_readme_boundaries tests.unit.test_package_distribution.PackageDistributionContractTests.test_test_support_files_have_mod_canonical_copy` after requiring packaged MOD directories to be documented in the MOD README boundaries.
- PASS: `PYTHONDONTWRITEBYTECODE=1 python3 -m unittest tests.unit.test_package_distribution.PackageDistributionContractTests.test_mod_readme_boundaries_are_packaged_or_intentionally_excluded tests.unit.test_package_distribution.PackageDistributionContractTests.test_packaged_mod_directories_have_readme_boundaries tests.unit.test_package_distribution.PackageDistributionContractTests.test_mod_readme_boundary_paths_are_manifest_canonical tests.unit.test_package_distribution.PackageDistributionContractTests.test_test_support_files_have_mod_canonical_copy` after requiring MOD README boundary paths to be packaged or intentionally excluded.
- PASS: `PYTHONDONTWRITEBYTECODE=1 python3 -m unittest tests.unit.test_package_distribution.PackageDistributionContractTests.test_npm_and_release_mod_directory_surface_diff_is_explicit tests.unit.test_package_distribution.PackageDistributionContractTests.test_packaged_mod_directories_have_readme_boundaries tests.unit.test_package_distribution.PackageDistributionContractTests.test_mod_readme_boundaries_are_packaged_or_intentionally_excluded tests.unit.test_package_distribution.PackageDistributionContractTests.test_test_support_files_have_mod_canonical_copy` after requiring the npm/cURL MOD directory surface difference to stay explicit.
- PASS: `PYTHONDONTWRITEBYTECODE=1 python3 -m unittest tests.unit.test_package_distribution.PackageDistributionContractTests.test_npm_and_release_mod_file_surface_diff_is_explicit tests.unit.test_package_distribution.PackageDistributionContractTests.test_npm_and_release_mod_directory_surface_diff_is_explicit tests.unit.test_package_distribution.PackageDistributionContractTests.test_mod_readme_boundaries_are_packaged_or_intentionally_excluded tests.unit.test_package_distribution.PackageDistributionContractTests.test_test_support_files_have_mod_canonical_copy` after requiring the npm/cURL MOD file surface difference to stay explicit.
- PASS: `bash shogunate_mod/package/prepublish_check.sh` ran 116 package distribution contract tests, confirmed generated instruction files are up to date, and passed after requiring the npm/cURL MOD file surface difference to stay explicit.
- PASS: `PYTHONDONTWRITEBYTECODE=1 python3 -m unittest tests.unit.test_package_distribution.PackageDistributionContractTests.test_npm_and_release_root_directory_surface_matches tests.unit.test_package_distribution.PackageDistributionContractTests.test_npm_and_release_root_file_surface_diff_is_explicit tests.unit.test_package_distribution.PackageDistributionContractTests.test_test_support_files_have_mod_canonical_copy` after requiring the npm/cURL root compatibility surface difference to stay explicit.
- PASS: `bash shogunate_mod/package/prepublish_check.sh` ran 118 package distribution contract tests, confirmed generated instruction files are up to date, and passed after requiring the npm/cURL root compatibility surface difference to stay explicit.
- PASS: `PYTHONDONTWRITEBYTECODE=1 python3 -m unittest tests.unit.test_package_distribution.PackageDistributionContractTests.test_root_shogunate_text_surfaces_have_sync_or_generation_gate tests.unit.test_package_distribution.PackageDistributionContractTests.test_root_shogunate_surfaces_are_classified_by_manifest tests.unit.test_package_distribution.PackageDistributionContractTests.test_instruction_sources_have_mod_canonical_copy tests.unit.test_package_distribution.PackageDistributionContractTests.test_test_support_files_have_mod_canonical_copy` after requiring root Shogunate text surfaces to have a wrapper, generated, prepublish sync, or instruction source sync gate.
- PASS: `bash shogunate_mod/package/prepublish_check.sh` ran 119 package distribution contract tests, confirmed generated instruction files are up to date, and passed after requiring root Shogunate text surfaces to have a wrapper, generated, prepublish sync, or instruction source sync gate.
- PASS: `PYTHONDONTWRITEBYTECODE=1 python3 -m unittest tests.unit.test_package_distribution.PackageDistributionContractTests.test_root_shogunate_text_surfaces_have_sync_or_generation_gate tests.unit.test_package_distribution.PackageDistributionContractTests.test_root_shogunate_surfaces_are_classified_by_manifest tests.unit.test_package_distribution.PackageDistributionContractTests.test_codd_docs_have_mod_canonical_copy tests.unit.test_package_distribution.PackageDistributionContractTests.test_test_support_files_have_mod_canonical_copy` after adding public/design docs to the root Shogunate text surface scan.
- PASS: `bash shogunate_mod/package/prepublish_check.sh` ran 119 package distribution contract tests, confirmed generated instruction files are up to date, and passed after adding public/design docs to the root Shogunate text surface scan.
- PASS: source checkout smoke in detached worktree `runtime_sandboxes/source-runtime-smoke-20260618191513` with `SHOGUNATE_PROJECT_DIR=<worktree>/target-project SHOGUNATE_SESSION_NAME=shogunate-mod-source-runtime-smoke-20260618191513 GOZA_SESSION_NAME=shogunate-mod-source-runtime-smoke-20260618191513 RUNTIME_DAEMON_SESSION=goza-runtime-shogunate-mod-source-runtime-smoke-20260618191513 MAS_BOOTSTRAP_READY_TIMEOUT=3 bash shutsujin_departure.sh -s -c`; verified the `goza` tmux window had 5 role panes (`shogun`, `gunkan`, `karo`, `gunshi`, `ashigaru1`), `queue/runtime/agent_cli.tsv` had 5 role entries, dashboard and Gunkan queue/report files existed, and tmux `@shogunate_project_dir` / `@shogunate_runtime_dir` matched the target project and detached runtime worktree. The smoke-owned tmux session and worktree were removed after verification.
- PASS: `bash -n shogunate_mod/runtime/source_smoke.sh` and targeted package distribution contracts (`test_manifest_declared_paths_exist`, `test_manifest_mod_canonical_sources_are_not_gitignored`, `test_release_archive_includes_runtime_mod_canonical_sources`, `test_npm_pack_covers_runtime_mod_manifest_source_files`, `test_npm_pack_mod_files_are_manifest_canonical`, `test_release_archive_mod_files_are_manifest_canonical`) after adding the MOD-owned source runtime smoke helper.
- PASS: `SHOGUNATE_SOURCE_SMOKE_RUN_ID=source-runtime-smoke-script-20260618192701 bash shogunate_mod/runtime/source_smoke.sh`; verified detached source checkout setup-only runtime, exact tmux/project metadata, 5 role panes, `agent_cli.tsv`, dashboard, Gunkan inbox/report files, and smoke-owned cleanup.
- PASS: `PYTHONDONTWRITEBYTECODE=1 python3 -m unittest tests.unit.test_package_distribution.PackageDistributionContractTests.test_makefile_has_mod_canonical_copy` after adding `make source-smoke` to the MOD-owned development Makefile and synchronized root Makefile.
- PASS: `SHOGUNATE_SOURCE_SMOKE_RUN_ID=source-runtime-smoke-make-20260618193849 make source-smoke`; verified the Makefile target invokes the MOD-owned source runtime smoke and performs smoke-owned cleanup after detached runtime verification.
- PASS: `make -n package-check` and `PYTHONDONTWRITEBYTECODE=1 python3 -m unittest tests.unit.test_package_distribution.PackageDistributionContractTests.test_makefile_has_mod_canonical_copy` after adding `make package-check` to the MOD-owned development Makefile and synchronized root Makefile.
- PASS: `make -n mod-check` and `PYTHONDONTWRITEBYTECODE=1 python3 -m unittest tests.unit.test_package_distribution.PackageDistributionContractTests.test_makefile_has_mod_canonical_copy` after adding the combined MOD verification target and extending it to Android.
- PASS: `SHOGUNATE_SOURCE_SMOKE_RUN_ID=source-runtime-smoke-mod-check-20260618202700 make mod-check`; ran package prepublish checks (source syntax checks, 120 package distribution contract tests, 34 MOD behavior unit tests, generated instruction freshness, dirty gate) and the detached source runtime smoke against commit `51004dd`, then removed the smoke-owned worktree and tmux sessions.
- PASS: `make -n android-check` and `PYTHONDONTWRITEBYTECODE=1 python3 -m unittest tests.unit.test_package_distribution.PackageDistributionContractTests.test_makefile_has_mod_canonical_copy` after adding the Android Gradle verification target.
- PASS: `make android-check`; ran Android `testDebugUnitTest assembleDebug` from the root Android Gradle working tree. Gradle warned about SDK XML version mismatch, but exited 0 with `BUILD SUCCESSFUL`.
- PASS: `SHOGUNATE_SOURCE_SMOKE_RUN_ID=source-runtime-smoke-mod-check-android-20260618204318 make mod-check`; ran package prepublish checks, detached source runtime smoke, and Android `testDebugUnitTest assembleDebug` through the combined MOD verification target against commit `a02b291`. Gradle warned about SDK XML version mismatch, but exited 0 with `BUILD SUCCESSFUL`; smoke-owned runtime worktree and tmux sessions were removed.
- PASS: `PYTHONDONTWRITEBYTECODE=1 python3 -m unittest tests.unit.test_shogunate_pair_server tests.unit.test_package_distribution.PackageDistributionContractTests.test_test_support_files_have_mod_canonical_copy` after switching Pair server unit tests to import `shogunate_mod/pair/server.py` directly.
- PASS: `PYTHONDONTWRITEBYTECODE=1 python3 -m unittest tests.unit.test_package_distribution.PackageDistributionContractTests.test_unit_tests_import_mod_canonical_runtime_sources tests.unit.test_package_distribution.PackageDistributionContractTests.test_unit_test_cases_have_mod_canonical_copy` after adding a contract that runtime/Pair/update unit tests import MOD canonical sources instead of root wrappers.
- PASS: `PYTHONDONTWRITEBYTECODE=1 python3 -m unittest tests.unit.test_package_distribution.PackageDistributionContractTests.test_e2e_support_files_have_mod_canonical_copy tests.unit.test_shogunate_pair_server tests.unit.test_runtime_blocker_notice tests.unit.test_update_manager` after adding MOD behavior unit tests to package prepublish.
- PASS: tracked source syntax checks (`bash -n` for `*.sh` / `*.command`, `compile(..., "exec")` for `*.py` without bytecode generation, `node --check` for `*.js`) and `PYTHONDONTWRITEBYTECODE=1 python3 -m unittest tests.unit.test_package_distribution.PackageDistributionContractTests.test_e2e_support_files_have_mod_canonical_copy` after adding syntax checks to package prepublish.
- PASS: `make package-check` ran source syntax checks, 120 package distribution contract tests, 34 MOD behavior unit tests, generated instruction freshness, and the dirty-worktree gate after adding the syntax checks to package prepublish.
- PASS: `python3 -m unittest tests.unit.test_package_distribution.PackageDistributionContractTests.test_manifest_core_touchpoint_next_steps_use_operational_classes tests.unit.test_package_distribution.PackageDistributionContractTests.test_manifest_core_touchpoints_are_actionable_and_not_wrappers tests.unit.test_package_distribution.PackageDistributionContractTests.test_synchronized_core_touchpoints_have_prepublish_gates tests.unit.test_package_distribution.PackageDistributionContractTests.test_non_synchronized_core_touchpoints_are_explicitly_classified` after requiring manifest core touchpoint `next_step` values to use operational classes.
- PASS: `PYTHONDONTWRITEBYTECODE=1 python3 -m unittest tests.unit.test_package_distribution` ran 121 package distribution contract tests after adding the manifest `next_step` operational-class contract.
- PASS: direct `diff -q tests/unit/test_package_distribution.py shogunate_mod/tests/unit/test_package_distribution.py` confirmed root test compatibility file matches MOD test source after adding the manifest `next_step` operational-class contract.
- PASS: `git diff --check` after adding the manifest `next_step` operational-class contract.
- PASS: `make package-check` ran source syntax checks, 121 package distribution contract tests, 34 MOD behavior unit tests, generated instruction freshness, and the clean-worktree dirty gate after adding the manifest `next_step` operational-class contract.
- PASS: `PYTHONDONTWRITEBYTECODE=1 python3 -m unittest tests.unit.test_package_distribution.PackageDistributionContractTests.test_manifest_target_direction_keeps_core_mod_boundary tests.unit.test_package_distribution.PackageDistributionContractTests.test_manifest_core_touchpoint_next_steps_use_operational_classes` after fixing manifest `target_direction` as the core/MOD boundary contract.
- PASS: direct `diff -q tests/unit/test_package_distribution.py shogunate_mod/tests/unit/test_package_distribution.py` confirmed root test compatibility file matches MOD test source after adding the manifest `target_direction` contract.
- PASS: `git diff --check` after adding the manifest `target_direction` contract.

## 復旧

wrapper 化で問題が出た場合は、該当 MOD 実装を旧 `scripts/` path へ戻せば従来構成へ復旧できる。旧 path は削除していないため、呼び出し元の互換性は維持される。
