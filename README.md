<div align="center">

# multi-agent-shognate

**A portable `multi-agent-shogun` fork focused on tmux operations and Android remote control.**

[![GitHub Stars](https://img.shields.io/github/stars/TsukinowaRin/multi-agent-shognate?style=social)](https://github.com/TsukinowaRin/multi-agent-shognate)
[![License: MIT](https://img.shields.io/badge/License-MIT-yellow.svg)](https://opensource.org/licenses/MIT)
[![Shell](https://img.shields.io/badge/Shell%2FBash-100%25-green)]()

[English](README.md) | [日本語](README_ja.md)

</div>

<p align="center">
  <img src="images/screenshots/hero/latest-translucent-20260210-190453.png" alt="Controlling multiple agents from the Shogun pane" width="940">
</p>

## What This Repository Is

`multi-agent-shognate` is a fork of [`multi-agent-shogun`](https://github.com/yohey-w/multi-agent-shogun). It keeps the upstream idea, but changes the operational defaults for this repository.

This fork prioritizes:

- `tmux`-centered runtime operation
- package-based installation into a fixed local directory
- Android remote control via the fork APK
- broader multi-CLI support than upstream
- conservative defaults: every role uses `codex`, no model is pinned in `config/settings.yaml`, and the initial active ashigaru are only `ashigaru1` and `ashigaru2`

In practice, the intended flow is:

- put the system in the workspace where you want to use it
- start it with `shutsujin_departure.sh`
- give the Shogun natural-language instructions
- let the Karo infer staffing and parallelism from the intent

## How This Fork Differs From Upstream

| Area | upstream | this fork |
|---|---|---|
| runtime layout | split tmux sessions are primary | `goza-no-ma:overview` is the runtime source of truth; `shogun` / `gunshi` / `multiagent` remain as Android-compatible proxy sessions |
| initial ashigaru roster | historical docs often imply a larger force | the default active ashigaru are only `ashigaru1` and `ashigaru2` |
| default CLI | upstream defaults | all roles default to `codex`; model selection is left to pane-local CLI state |
| CLI coverage | core upstream CLIs | adds `Antigravity CLI`, `OpenCode`, `Kilo`, `localapi`, and local-provider bridges such as `Ollama` / `LM Studio` |
| Android distribution | upstream Android app / APK | the fork APK in this repo's Releases is the supported distribution |
| Distribution | repo-oriented setup flow | Release packages (`tar.gz` / `zip`) plus cURL bootstrap; npm / npx wrapper is available |
| Karo behavior | splits work when instructed | explicitly allows Karo to infer staffing, routing, and parallelism from the task intent |

## Core Model

The command chain is still the Shogun model:

```text
You
 -> Shogun
 -> Karo
 -> Ashigaru / Gunshi
```

What matters in this fork:

- the current active force is defined by `topology.active_ashigaru`
- historical references to `ashigaru1..8` are not treated as proof that all eight are active
- Karo adapts staffing from the active roster and the task intent

## Supported CLIs And Vendors

This fork is not tied to a single vendor.

### Supported agent CLI types

| CLI type | Expected vendor / backend | Notes |
|---|---|---|
| `codex` | OpenAI Codex CLI | the default in this fork |
| `claude` | Anthropic Claude Code | supported as in upstream |
| `copilot` | GitHub Copilot CLI | supported as in upstream |
| `kimi` | Kimi Code | supported as in upstream |
| `antigravity` | Google Antigravity CLI | explicitly supported in this fork; legacy `gemini` settings are mapped to this type |
| `opencode` | OpenCode CLI | added in this fork |
| `kilo` | Kilo CLI | added in this fork |
| `localapi` | OpenAI-compatible local endpoint | for `Ollama`, `LM Studio`, llama.cpp server, and similar backends |

### Default permission / approval stance

In this fork, every agent defaults to an unattended, no-approval-by-default mode.

| CLI type | Default unattended behavior |
|---|---|
| `claude` | `--dangerously-skip-permissions` |
| `codex` | `--sandbox danger-full-access --ask-for-approval never` |
| `copilot` | `--yolo` |
| `kimi` | `--yolo` |
| `antigravity` | `--dangerously-skip-permissions` |
| `opencode` | generated `opencode.json` sets `permission: allow` |
| `kilo` | generated `opencode.json` sets `permission: allow` |
| `localapi` | launches the local REPL directly without a separate approval layer |

OpenCode / Kilo do not expose a stable `--yolo` flag in the current CLI help, so Shogunate treats the generated project `opencode.json` permission setting as the unattended-mode source of truth.

### Runtime File Watcher

Inbox delivery uses a native file watcher when available:

- Linux / WSL: `inotifywait` from `inotify-tools`
- macOS: `fswatch` from Homebrew
- fallback: timed polling, which keeps delivery alive but can add up to the watcher timeout before an unread inbox is processed

`first_setup.sh` checks the current OS and installs the recommended watcher where possible. If neither native watcher is available, Shogunate still starts with the polling backend.

### CLI State / Host Auth

External CLIs launched by the Shogunate runtime reuse host login credentials where known, while keeping model, settings, and history state separate per role / pane.

- CLI executables themselves are resolved from the host shell / WSL environment at Shogunate startup. The launcher prefers common Linux/WSL install paths under `HOME`, `NVM_BIN`, and `PNPM_HOME` before falling back to `PATH`, then passes absolute executable paths to tmux. This avoids accidentally launching Windows npm shims such as `/mnt/c/.../codex` when a native WSL CLI is installed.
- `Codex` launches each role with a repo-local `CODEX_HOME`. If host `~/.codex/auth.json` exists, the role-local `auth.json` points to it; if not, the older repo-local shared auth fallback is still available. Model / `reasoning_effort` / history state stays role-local.
- Codex startup keeps the normal interactive TUI by default: Shogunate launches `codex` first, then delivers the bootstrap prompt through tmux. Set `MAS_CODEX_STARTUP_PROMPT_MODE=argv` only if you need the older `codex <bootstrap prompt>` launch style.
- The exact composer chrome, placeholder prompts, and footer are owned by the installed Codex CLI version. Shogunate does not restyle the Codex TUI; it only avoids the old positional bootstrap prompt that changed the startup state.
- `Claude` / `Copilot` / `Kimi` / `Antigravity` / `OpenCode` / `Kilo` launch with `HOME` and XDG paths pointed at `.shogunate/cli-state/<cli>/agents/<agent>/home`. Known host auth files are symlinked into that pane-local home, but settings, model selections, caches, and history stay pane-local. Antigravity reuses known host OAuth/account files that `agy` relies on, including `.gemini/antigravity-cli/*` auth files and the host `.gemini/oauth_creds.json` / `.gemini/google_accounts.json`, while settings and history remain role-local.
- On Linux / WSL, Antigravity may persist OAuth tokens through Secret Service / keyring rather than plain files. Shogunate runs `scripts/ensure_antigravity_keyring.sh` right before launching Agy and starts `gnome-keyring-daemon` on a best-effort basis. If `agy` logs mention `failed to persist token to keyring` or `failed to unlock correct collection`, install `gnome-keyring` and `libsecret-tools`, then complete one host-side `agy` login. Shogunate does not delete or recreate existing keyrings; switching to an empty-password keyring remains an explicit user operation. To avoid repeating the first-run Terms / onboarding screen, host `.gemini/antigravity-cli/cache/onboarding.json` is copied into the role-local home only when the role-local file is missing.
- `OpenCode` / `Kilo` symlink known host `auth.json` into the pane-local home. `model.json` is copied from the host only when the role-local file is missing, then later model selections stay independent per role. Their SQLite DB, prompt history, telemetry, and other runtime files stay pane-local. Stale DB / model / history symlinks are removed at startup; existing role-local regular files are left intact. Plugin manifests are copied only when missing, while `node_modules` can be linked to the host install to avoid reinstalling dependencies.
- `localapi` is an in-repo local REPL and does not have external CLI login state to isolate.

The reason for this split is to avoid repeated logins while keeping Shogunate role-specific model / reasoning / history state separate from VSCode or unrelated sessions of the same CLI. Secret contents are not read or printed by this bootstrap, and OpenCode / Kilo provider databases are not copied from the host by default.

### Local-provider support

`localapi` is the bridge for local or self-hosted providers. Typical targets include:

- `Ollama`
- `LM Studio`
- llama.cpp server
- any OpenAI-compatible local endpoint

If your primary goal is to run arbitrary local models, use `localapi` first.
It talks to the OpenAI-compatible endpoint directly and is the main path in this fork for:

- custom LM Studio model IDs
- Ollama-hosted local models
- llama.cpp or similar local inference servers
- other self-hosted backends that do not match OpenCode / Kilo's built-in provider registry

`opencode` and `kilo` are still supported agent CLIs in this fork, but local-provider use should be treated as best-effort. Their own provider/model registry may reject model IDs that the backend itself would otherwise serve.

### CoDD Coherence Gate

This repository integrates [CoDD](https://github.com/yohey-w/codd-dev) as the standard external coherence gate. CoDD is not vendored into Shogunate; `Update.bat`, `scripts/update_manager.py manual`, and `make codd-install` install or update `codd-dev` in `.shogunate/codd-venv`.

```bash
make codd-install
make codd
# or one-shot:
CODD_AUTO_INSTALL=1 scripts/codd_check.sh verify
```

The project config lives at `.codd/codd.yaml`. Install/update normally pulls the latest PyPI `codd-dev`. If that fails, the wrapper falls back to the development-verified `CODD_FALLBACK_VERSION` default, currently `1.34.0`. If `python3` / `python3-venv` is missing in WSL, Linux, or macOS, the wrapper prints the required install commands and stops. CI runs `codd dag verify` by default. `scripts/codd_check.sh audit` is exposed for environments that have CoDD's optional audit bridge.

### Simple runtime role settings

Use this for normal setup. It configures only the broad CLI type per role and the active ashigaru count; model / reasoning / thinking choices are made inside each tmux pane and kept in pane-local CLI state.
The interactive order is `cli.default`, shogun, karo, gunshi, ashigaru count, then each active ashigaru.

Linux / WSL terminal:

```bash
./Shogunate-Configure-Roles.sh
```

Windows Explorer:

```text
Shogunate-Configure-Roles.bat
```

macOS Finder / Terminal:

```bash
./Shogunate-Configure-Roles.command
```

For macOS Shortcuts, use a "Run Shell Script" action with:

```bash
cd /path/to/multi-agent-shognate && ./Shogunate-Configure-Roles.sh
```

The direct Python entrypoint is:

```bash
python3 scripts/configure_runtime_roles.py
```

Non-interactive example:

```bash
python3 scripts/configure_runtime_roles.py \
  --ashigaru-count 3 \
  --shogun antigravity \
  --karo codex \
  --gunshi codex \
  --ashigaru1 codex \
  --ashigaru2 opencode \
  --ashigaru3 opencode
```

### Advanced per-role CLI and model settings

Use this when you explicitly want Shogunate to write model / reasoning / provider fields into `config/settings.yaml`:

```bash
bash scripts/configure_agents.sh
```

It can configure:

- CLI type per role
- model per role
- Codex `reasoning_effort`
- OpenCode / Kilo provider settings
- active ashigaru count

## Installation

### Recommended: cURL package bootstrap

Release installation is package-based. The bootstrap downloads the Release package, extracts it into a fixed local directory, removes deprecated installer files from older installs, and runs `first_setup.sh`.

```bash
curl -fsSL https://raw.githubusercontent.com/TsukinowaRin/multi-agent-shognate/main/scripts/shogunate_package_bootstrap.sh | bash
```

Pinned release install:

```bash
curl -fsSL https://raw.githubusercontent.com/TsukinowaRin/multi-agent-shognate/main/scripts/shogunate_package_bootstrap.sh \
  | bash -s -- --version v4.6.0.12 --prefix "$HOME/.shogunate/shogunate"
```

The default install directory is `$SHOGUNATE_HOME` or `~/.shogunate/shogunate`.

### npm / npx wrapper

The npm package is a thin wrapper around the same cURL bootstrap:

```bash
npx @tsukinowarin/shogunate install
npx @tsukinowarin/shogunate install -- --version v4.6.0.12 --prefix "$HOME/.shogunate/shogunate"
```

Release assets:

- `multi-agent-shognate-package.tar.gz`
- `multi-agent-shognate-package.zip`
- `multi-agent-shognate-package-<version>.tar.gz`
- `multi-agent-shognate-package-<version>.zip`

Important behavior:

- package assets are built from the matching Release tag
- `latest` uses GitHub Releases' latest package asset, not a local OS installer
- pinned installs use the exact Release tag you pass
- local state such as `config/settings.yaml`, `queue/`, `logs/`, and `.shogunate/` is not part of the package archive
- OS-specific installer assets are not published

### Manual install from clone or ZIP

If you want to manage the repo directly:

```bash
git clone https://github.com/TsukinowaRin/multi-agent-shognate
cd multi-agent-shognate
bash first_setup.sh
```

The same applies if you unpack a ZIP and run from the repo root.

## Updating

This fork supports two update channels.

### 1. Git `main` install

If you run the repo directly from a `git clone` on `main`, startup treats that as the rolling channel.

- `shutsujin_departure.sh` checks for a fast-forward update before boot
- if the worktree is clean, it pulls latest `origin/main`
- if tracked local edits or local commits would collide, it does **not** destroy them
- instead it writes merge candidates into `.shogunate/merge-candidates/` and notifies Karo after startup

This is the "always follow latest code" path.

If you also want to import the latest content from the original upstream repository and let Shogunate review collisions, run:

```bash
bash scripts/upstream_sync.sh
```

If you want to inspect what would change before touching the tree, use:

```bash
bash scripts/upstream_sync.sh --dry-run
```

That flow:

- fetches `upstream/main`
- imports the upstream snapshot without deleting local customizations
- stores incoming conflicting files under `.shogunate/merge-candidates/`
- appends a pending command to `queue/shogun_to_karo.yaml`
- lets Karo coordinate the merge work after startup

`--dry-run` prints the planned adds / updates / removals / conflicts as JSON and does not modify the worktree.

### 2. Release package install

If you installed the system with the cURL bootstrap or npm wrapper, that is the stable release channel.

Release versions follow upstream plus a fork revision: `v<upstream-version>.<fork-revision>`.
The first three numbers track the upstream Shogun version.
The fourth number is this fork's packaging/release revision.
Current upstream is `v4.6.0`, so aligned examples are `v4.6.0.0` and `v4.6.0.12`.
Package asset names use the same version part.

Use package assets like this:

- `multi-agent-shognate-package.tar.gz`
- `multi-agent-shognate-package.zip`
- `multi-agent-shognate-package-<version>.tar.gz`
- `multi-agent-shognate-package-<version>.zip`

The cURL bootstrap extracts the package into the target directory and runs `first_setup.sh`. Re-running it with a newer version updates that package install while keeping local state. The install is pinned when you pass `--version`.

If you are connected from the Android app, the app can also trigger **host-side** updates over SSH. That does not update the APK itself. It updates the installed Shogunate copy on the host.

### What gets preserved

Updates keep local state and user-specific assets such as:

- `config/settings.yaml`
- `.codex/`
- `.claude/`
- `projects/`
- `context/local/`
- `instructions/local/`
- `skills/local/`
- runtime state under `queue/`, `logs/`, and `dashboard.md`

If an incoming tracked file collides with local edits, the package/update flow keeps the local file in place and stores the incoming version under:

- `.shogunate/merge-candidates/<batch>/incoming/...`

After startup, Karo is nudged to handle the merge work.

### What `first_setup.sh` does

`first_setup.sh` is responsible for local bootstrap. It typically:

- creates local config files such as `config/settings.yaml`
- checks dependencies
- helps bootstrap CLIs
- prepares the tmux runtime

In this fork, `config/settings.yaml` is local-only and is not part of the published Git tree.

## First Launch

After installation:

Linux / WSL terminal:

```bash
./Shogunate-Runtime.sh
```

Windows Explorer:

```text
Shogunate-Runtime.bat
```

macOS Finder / Terminal:

```bash
./Shogunate-Runtime.command
```

For macOS Shortcuts, use a "Run Shell Script" action with:

```bash
cd /path/to/multi-agent-shognate && ./Shogunate-Runtime.sh
```

The direct shell entrypoint is still available:

```bash
bash shutsujin_departure.sh
```

The launcher defaults to a clean start, creates `goza-no-ma`, and first attaches to a startup window. Agent CLIs then launch in the hidden `overview` window, so Codex can initialize its TUI on an attached terminal without exposing launch commands to user input. The startup window streams the full launch log without repainting, so ASCII art and earlier output remain available through tmux copy-mode. When startup finishes, tmux switches to `overview` automatically. If a CLI needs login, follow the prompt in that CLI's tmux pane. Use `./Shogunate-Runtime.sh --resume` to keep existing runtime state, or `./Shogunate-Runtime.sh --no-attach` to start without attaching.

Role configuration can be opened before launch with `Shogunate-Configure-Roles.bat` on Windows, `./Shogunate-Configure-Roles.sh` on Linux / WSL, or `./Shogunate-Configure-Roles.command` on macOS.

## First Project / Solution Walkthrough

Use one Shogunate install for many project workspaces. A "project" here means the repository or directory you want the agents to modify, similar to a Visual Studio solution.

1. Open the role configurator:

   ```bash
   ./Shogunate-Configure-Roles.sh
   ```

   Choose the default CLI family and ashigaru count. You do not need to pick exact models here; model/provider settings can be adjusted inside each CLI pane and are preserved per role.

2. Start Shogunate:

   ```bash
   ./Shogunate-Runtime.sh
   ```

   The default view is `goza-no-ma:overview`. Shogun is the normal command target.

3. Tell Shogun what the project workspace is and what "done" means. You can type directly in the Shogun pane, or send from the Android app with Shogun selected.

   Example:

   ```text
   Work on /home/me/projects/demo-api. Add a small health-check endpoint, update tests, and report the exact test command that passes.
   ```

   For existing repositories, give the absolute path and the user-visible outcome. For new demo work, give the directory to create under `runtime_sandboxes/` or another explicit workspace.

4. Let Shogun route the request. Shogun writes a command for Karo, Karo splits work across the active ashigaru roster, and Gunshi is used for strategy, architecture, root-cause analysis, or complex QC.

5. Check progress from `dashboard.md`, the Goza panes, or Android. Completion is reported back through Shogun; Karo owns final validation and dashboard updates.

6. To keep the same runtime state for the same project, use:

   ```bash
   ./Shogunate-Runtime.sh --resume
   ```

   To switch projects cleanly, start normally and include the new workspace path in the next command. Local Shogunate settings, role CLI preferences, and learned repo docs remain in this install; project-specific source changes stay in the project workspace you named.

Useful commands after startup:

```bash
bash scripts/goza_no_ma.sh
bash scripts/focus_agent_pane.sh shogun
bash scripts/focus_agent_pane.sh karo
bash scripts/focus_agent_pane.sh gunshi
```

If you want the short aliases:

```bash
source scripts/shell_aliases.sh
```

To persist them:

```bash
bash scripts/install_shell_aliases.sh
source ~/.bashrc
```

### Runtime source of truth and compatibility sessions

This matters for Android connectivity.

| session | role |
|---|---|
| `goza-no-ma:overview` | runtime source of truth in this fork |
| `shogun:main` | Android-compatible Shogun target |
| `gunshi:main` | Android-compatible Gunshi target |
| `multiagent:agents` | Android-compatible Karo / Ashigaru target |

## Android App And APK

This repo ships a **fork Android app**.

Do not use the upstream APK here.

### Which APK to use

Download it from this repo's **GitHub Releases**.

The asset name looks like:

- `multi-agent-shognate-android-*.apk`

That APK is the supported Android distribution for this fork.

### What the Android app does

The APK is a remote control and monitoring client.

It connects to the host over SSH and interacts with:

- the `shogun` tmux session
- the `multiagent` tmux session
- `dashboard.md`

It can also send commands into the Shogun pane when needed. In the newer APK, the Shogun tab has target chips that switch by tmux `@agent_id`, so the same input can address Shogun, Karo, Gunshi, or Ashigaru. Shogun remains the default target.

The fork APK can also manage **host-side Shogunate updates** over SSH:

- check update status
- preview upstream import with `--dry-run`
- stop Shogunate and apply a Release update
- stop Shogunate and apply an upstream import

The APK does **not** self-update. Android app updates still come from GitHub Releases.

### Android connection model

The app is SSH-based. No specific VPN product is required. The only requirement is that the phone can reach the host over SSH.

Required settings:

- a reachable SSH hostname or IP
- SSH port
- Linux username on the host
- password or key for that Linux user
- project path on the host
- tmux session names

Typical values in this fork:

| Item | Value |
|---|---|
| Shogun session | `shogun` |
| Agents session | `multiagent` |
| project path | the repo root on the host |

For connection profiles:

```bash
# Tailscale target profile
scripts/android_pairing_profile.sh --mode tailscale --ssh-port 22

# USB adb reverse target profile
scripts/android_pairing_profile.sh --mode usb --ssh-port 22 --android-port 2222
```

The generated JSON can be imported from the Android Settings screen. It does not include passwords, private keys, or tokens.

Notes:

- Android connection defaults are blank or non-identifying placeholders
- no personal hostnames, IPs, or topics are baked into the app
- the APK also has an `ntfy` topic field for app-side notification subscription
- host updates from the APK are applied only after Shogunate is stopped; they are not hot-applied into a running tmux runtime

## Notifications (`ntfy`)

`ntfy` is supported, but it is safer to think of server-side and Android-side usage separately.

- server-side Shogunate notifications use local config such as `config/settings.yaml`
- the Android app can subscribe to an `ntfy` topic itself

Local values such as `ntfy_topic` are treated as private and are not published in the repo tree.

## Portable Use In Another Workspace

This system can be used portably.

If you want it in a different workspace, the intended flow is:

- create or choose the target folder
- run the cURL bootstrap with `--prefix <target-folder>`
- let it extract the Release package and run `first_setup.sh`

That keeps the following scoped to that workspace:

- `queue/`
- `logs/`
- `dashboard.md`
- `config/settings.yaml`
- tmux runtime state

## Defaults In This Fork

Current defaults:

- all roles use `codex`
- no model is pinned in `config/settings.yaml`; each CLI uses its own pane-local/default model state
- initial active ashigaru are `ashigaru1` and `ashigaru2`
- one Karo manages up to 6 ashigaru; at 7 ashigaru and above, Shogunate creates `karo1`, `karo2`, ... and balances ownership
- when multiple Karo exist, `karo1` is the lead Karo and owns Shogun reporting; Karo-to-Karo coordination uses `queue/runtime/karo_coordination.yaml`, not free-form direct inbox chat

If you want more ashigaru, change the active topology instead of relying on historical 1-8 references.

## Common Commands

```bash
bash first_setup.sh
bash shutsujin_departure.sh
./Shogunate-Runtime.sh
./Shogunate-Configure-Roles.sh
python3 scripts/configure_runtime_roles.py
bash scripts/configure_agents.sh
bash scripts/goza_no_ma.sh
bash scripts/focus_agent_pane.sh shogun
bash scripts/focus_agent_pane.sh karo
bash scripts/prepublish_check.sh
```

## Repository Layout

```text
multi-agent-shognate/
├── android/                   # fork Android app
├── config/                    # local/runtime config templates
├── docs/                      # requirements, plans, publishing policy
├── instructions/              # shared and generated CLI instructions
├── lib/                       # shell helper library
├── scripts/                   # runtime, bootstrap, bridge, watcher
├── tests/                     # unit and smoke tests
├── bin/shogunate.js           # npm / npx wrapper for package bootstrap
├── Shogunate-Runtime.bat      # Windows runtime launcher
├── Shogunate-Runtime.sh       # Linux / WSL runtime launcher
├── Shogunate-Runtime.command  # macOS Finder runtime launcher
├── Shogunate-Configure-Roles.bat      # Windows WSL role configurator launcher
├── Shogunate-Configure-Roles.sh       # Linux / WSL role configurator launcher
├── Shogunate-Configure-Roles.command  # macOS Finder role configurator launcher
├── updater.bat                # Legacy Windows updater script kept for compatibility
├── first_setup.sh             # first-time setup
└── shutsujin_departure.sh     # runtime startup
```

## Publishing Hygiene

This fork treats the following as local-only:

- `config/settings.yaml`
- runtime queue state
- local logs
- private notification topics
- personal hostnames, paths, and IPs

Before publishing:

```bash
bash scripts/prepublish_check.sh
```

## Who This Fork Is For

This fork is a better fit if you want:

- package installation into a fixed local directory, with an optional custom prefix
- the fork APK from GitHub Releases
- broader CLI support including Antigravity / OpenCode / Kilo / localapi
- `goza-no-ma` as the runtime source of truth
- conservative defaults for stable operation

If you want upstream defaults and upstream distribution as-is, upstream is the more natural choice.

## Related Docs

- `android/README.md` - Android app details
- `docs/REQS.md` - normalized current requirements
- `docs/PUBLISHING.md` - privacy / cleanup policy before publication
- `docs/philosophy.md` - design philosophy
