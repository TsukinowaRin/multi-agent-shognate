# Shogunate MOD

This directory is the canonical home for Shogunate-specific behavior layered on
top of the upstream `yohey-w/multi-agent-shogun` core.

The compatibility paths under `scripts/` remain stable for release cURL URLs,
tests, and older installs, but they should delegate here whenever the behavior
is Shogunate-only.

## Direction

- Keep upstream-like runtime entrypoints thin.
- Move Shogunate-only behavior into shogunate_mod/ first.
- Leave compatibility wrappers at historical paths.

## Boundaries

- `battlefield/` owns the Shogunate App-facing battlefield API for registered
  project discovery, runtime start/stop, app sessions, transcripts, role
  listing, and role message delivery.
- `cli/` owns the Multi-CLI adapter used to build role-specific Claude,
  Codex, OpenCode, Kilo, Antigravity, Copilot, Kimi, LocalAPI, and Cursor
  launch commands, plus CLI-specific preflight helpers such as Antigravity
  keyring readiness.
- `configure/` owns role/CLI/settings configuration, including the interactive
  configurator used by `shogunate configure`, runtime role CLI updates, the
  OS launchers for role configuration, live CLI switching, default
  `config/settings.yaml` / `config/projects.yaml` templates, the OpenCode
  permission matrix and TUI keybinding config, OpenCode/Kilo project config
  sync, and the MOD canonical helpers `shogunate_mod/configure/agents.sh`,
  `shogunate_mod/configure/runtime_roles.py`,
  `shogunate_mod/configure/sync_opencode_config.py`, and
  `shogunate_mod/configure/switch_cli.sh`. Historical
  `Shogunate-Configure-Roles.*` and root configure/switch paths remain
  compatibility wrappers only.
- `context/` owns the Shogunate context directory guide. Root
  `context/README.md` remains the compatibility guide next to project-specific
  context files, while `context/{project}.md` stays user/runtime state.
- `development/` owns the Shogunate developer command surface such as the
  MOD-specific `Makefile` targets for instruction builds, package checks,
  Bats tests, shellcheck, Gunkan/CoDD audit helpers, source checkout runtime
  smoke checks, and test helper submodule metadata. Root `Makefile` and
  `.gitmodules` remain the compatibility copies used by `make` and Git.
- `docs/` owns the public Shogunate README source for package install, cURL,
  cwd-first project runtime, Android Pair, supported CLI guidance, changelog,
  contribution rules, and security policy. Root `README.md`, `README_ja.md`,
  `CHANGELOG.md`, `CONTRIBUTING.md`, and `SECURITY.md` remain GitHub/npm
  compatibility copies.
- `git/` owns Shogunate branch policy helpers used by deploy and branch
  maintenance scripts, including deploy verification, drift checks,
  short-lived branch merge automation, and the optional cron block
  printer/installer.
- `github/` owns repository-level GitHub metadata that must also exist at root
  for GitHub to read it, such as funding metadata. Root `.github/FUNDING.yml`
  remains the GitHub compatibility copy.
- `package/` owns cURL/package install, first setup, npm package metadata,
  first-run templates for `memory/` and `saytask/`, Python package
  requirements for build-time generation helpers, release archive
  `.gitattributes` rules, `.gitignore` package/source boundary rules, the npm
  wrapper implementation, cwd-first workspace resolution, prepublish checks, GitHub
  Actions package/test workflow sources, and the generated `shogunate`
  command. Root `package*.json`, `requirements.txt`, `.gitattributes`,
  `.gitignore`, `.github/workflows/`, `memory/MEMORY.md.sample`, and
  `saytask/streaks.yaml.sample` remain compatibility locations synchronized
  from MOD sources.
- `pair/` owns Android Pair and SSH public-key registration.
- `projects/` owns the registered project registry used by cwd-first package
  runtime, `shogunate projects`, `shogunate open`, and Shogunate App project
  selection.
- `queue/` owns queue maintenance utilities such as YAML slimming, history
  book generation, and archive compaction for commands, tasks, reports, and
  inboxes.
- `gunkan/` owns Shogunate's independent auditor helpers: event logging,
  lightweight watch, CoDD audit bridge/check command, CoDD config source,
  Gunkan/CoDD design docs, and emergency stop. The root `.codd/codd.yaml`
  remains the compatibility location consumed by CoDD tooling and should match
  `shogunate_mod/gunkan/codd.yaml`; root `docs/codd/` remains the reader/graph
  compatibility copy for `shogunate_mod/gunkan/docs/`.
- `hooks/` owns CLI hook integration such as Claude Code SessionStart
  persona injection, Stop hook inbox delivery / idle flag publication, and the
  MOD-owned Claude Code hook/spinner settings. Root `.claude/settings.json`
  remains the Claude-required compatibility copy.
- `inbox/` owns Shogunate mailbox write policy and inbox path normalization,
  including multi-Karo route checks and non-blocking Gunkan event logging.
- `instructions/` owns Shogunate role/common/CLI prompt source templates,
  the MOD-owned Claude auto-load source, generated instruction rebuilds for
  Shogunate roles, CLI-specific prompt packs, AGENTS.md, Copilot instructions,
  and OpenCode agent definitions. Root `CLAUDE.md` and `instructions/` remain
  compatibility output/copy locations consumed by CLI adapters and docs.
- `localapi/` owns the lightweight OpenAI-compatible local model REPL used by
  the LocalAPI CLI adapter target.
- `macos/` owns macOS Finder `.command` launchers. Root `.command` files
  remain compatibility entrypoints.
- `mobile/android/` owns the Shogunate Android remote-control app source.
  Root `android/` remains the Android Studio / Gradle compatibility working
  tree, and Android build/cache/local APK artifacts stay outside runtime
  package releases.
- `notify/` owns ntfy authentication, the auth sample config, outbound
  notification send, and inbound listener scripts. The root
  `config/ntfy_auth.env.sample` remains the user-facing compatibility sample
  copied to `config/ntfy_auth.env`.
- `opencode/` owns Shogunate-specific OpenCode tools such as the inbox
  `mark-as-read` state updater. Root `.opencode/tools/` remains the OpenCode
  compatibility location loaded by OpenCode.
- `runtime/load.sh` is the root entrypoint's MOD loader. `runtime/` owns
	  Shogunate runtime helpers such as thin launcher shared setup,
	  shell runtime launchers,
	  target project resolution,
	  departure entrypoint orchestration,
	  session naming, Android compatibility sessions, watcher/bridge daemon
  startup orchestration, daemon window orchestration,
	  role directives, runtime topology resolution, Goza tmux session
	  construction, Goza layout/pane helpers, startup banner and startup-time
	  ASCII banner rendering,
	  queue/dashboard/runtime state initialization,
	  runtime bridge scripts, runtime bridge daemons, live CLI preference sync,
	  and live CLI preference sync daemon,
	  MCP health checks,
	  mux parity smoke checks,
	  source checkout runtime smoke checks,
	  upstream core overlay smoke checks,
	  `agent_cli.tsv` emission, startup bootstrap delivery helpers and delivery
	  flow, agent CLI launch flow, runtime lifecycle setup, startup-window helpers,
	  startup lock/update/logging helpers, runtime-blocked relays and dashboard
	  notice repair/update helpers, completion
	  summary / Windows Terminal tab rendering, runtime options/help parsing,
	  and CLI prompt handling used by thin root entrypoints.
- `security/` owns Shogunate-specific secret scanning configuration. Root
  `.gitleaks.toml` remains the compatibility location used by gitleaks.
- `shell/` owns Shogunate view aliases and shell rc installer cleanup.
- `skills/` owns Shogunate Claude Code and Cursor skill sources. Root
  `skills/` and `.cursor/skills/` remain CLI compatibility copies synchronized
  from MOD sources.
- `templates/` owns Shogunate reusable Karo integration/context templates.
  Root `templates/` remains the historical compatibility path referenced by
  generated role instructions.
- `tests/` owns Shogunate-specific test specifications, fixtures, shared Bats
  helpers, unit test cases, and E2E `.bats` cases plus fixtures/helpers/mock
  CLI behavior. Root `tests/` remains the compatibility path consumed by the
  existing test suite and is kept synchronized from the MOD-owned test tree.
- `status/` owns shared tmux pane busy/idle detection and the agent status
  command plus rate-limit status reporting used by watcher, routing helpers,
  and operators.
- `topology/` owns dynamic role formation, active Ashigaru/Karo resolution,
  and ownership map helpers.
- `update/` owns release/git install update management, pending update
  requests, upstream snapshot import, and merge-candidate notices.
- `view/` owns Goza view attach/focus helpers, Goza layout autosave, and
  the browser dashboard viewer.
- `windows/` owns Windows/WSL `.bat` launchers for role configuration,
  runtime, Shutsujin, and debug clean/resume starts. Root `.bat` files remain
  compatibility entrypoints.
- `watcher/` owns the per-agent inbox watcher, cross-platform file-watch
  helpers, and the tmux watcher supervisor that keeps watcher windows attached
  to the current Shogunate session.

Upstream-like runtime files still exist at the repository root while the
runtime core is being separated. New Shogunate-only features should start in
this directory first.
