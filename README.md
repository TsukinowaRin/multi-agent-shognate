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
- portable installation into any folder
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
| CLI coverage | core upstream CLIs | adds `Gemini CLI`, `OpenCode`, `Kilo`, `localapi`, and local-provider bridges such as `Ollama` / `LM Studio` |
| Android distribution | upstream Android app / APK | the fork APK in this repo's Releases is the supported distribution |
| Windows installer | repo-oriented setup flow | Release installer `multi-agent-shognate-installer-<version>.bat` installs portably into the folder where you place it |
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
| `gemini` | Gemini CLI | explicitly supported in this fork |
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
| `gemini` | `--yolo` |
| `opencode` | generated `opencode.json` sets `permission: allow` |
| `kilo` | generated `opencode.json` sets `permission: allow` |
| `localapi` | launches the local REPL directly without a separate approval layer |

OpenCode / Kilo do not expose a stable `--yolo` flag in the current CLI help, so Shogunate treats the generated project `opencode.json` permission setting as the unattended-mode source of truth.

### CLI State / Host Auth

External CLIs launched by the Shogunate runtime reuse host login credentials where known, while keeping model, settings, and history state separate per role / pane.

- CLI executables themselves are resolved from the host shell / WSL environment at Shogunate startup. The launcher prefers common Linux/WSL install paths under `HOME`, `NVM_BIN`, and `PNPM_HOME` before falling back to `PATH`, then passes absolute executable paths to tmux. This avoids accidentally launching Windows npm shims such as `/mnt/c/.../codex` when a native WSL CLI is installed.
- `Codex` launches each role with a repo-local `CODEX_HOME`. If host `~/.codex/auth.json` exists, the role-local `auth.json` points to it; if not, the older repo-local shared auth fallback is still available. Model / `reasoning_effort` / history state stays role-local.
- Codex startup keeps the normal interactive TUI by default: Shogunate launches `codex` first, then delivers the bootstrap prompt through tmux. Set `MAS_CODEX_STARTUP_PROMPT_MODE=argv` only if you need the older `codex <bootstrap prompt>` launch style.
- The exact composer chrome, placeholder prompts, and footer are owned by the installed Codex CLI version. Shogunate does not restyle the Codex TUI; it only avoids the old positional bootstrap prompt that changed the startup state.
- `Claude` / `Copilot` / `Kimi` / `Gemini` / `OpenCode` / `Kilo` launch with `HOME` and XDG paths pointed at `.shogunate/cli-state/<cli>/agents/<agent>/home`. Known host auth files are symlinked into that pane-local home, but settings, model selections, caches, and history stay pane-local. Gemini also gets `GEMINI_DEFAULT_AUTH_TYPE=oauth-personal` by default so host OAuth credentials can be used without sharing the full user settings file.
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
  --shogun gemini \
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
- Gemini `thinking_level` / `thinking_budget`
- OpenCode / Kilo provider settings
- active ashigaru count

## Installation

### Recommended: Windows portable installer

If you want to place the system directly into any folder, this is the supported path.

1. Open this repo's **GitHub Releases**
2. Download `multi-agent-shognate-installer-<version>.bat`
3. Put it into the folder where you want the system installed
4. Run it

Important behavior:

- the installer downloads the source for the **same Release tag** it was downloaded from
- it installs into the **same folder where the installer itself is placed**
- if that folder already contains a portable Release install, it switches to in-place update mode
- in update mode, it preserves local state and personal files, then applies the newer Release snapshot
- it checks WSL2 / Ubuntu and, when possible, runs `first_setup.sh` automatically
- it initializes local update metadata for that portable install

This is the standard Windows install path for this fork.

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

### 2. Release installer / portable install

If you installed the system with `multi-agent-shognate-installer-<version>.bat`, that is the stable release channel.

Release tags use the format `android-v<upstream-version>.<fork-revision>`.
The first three numbers track the upstream Shogun version.
The fourth number is this fork's packaging/release revision.
Current upstream is `v4.6.0`, so the next aligned example is `android-v4.6.0.0`.
Installer asset names use only the version part, for example `v4.6.0.0`.

Use the Windows installer like this:

- `multi-agent-shognate-installer-<version>.bat`
  - first-time install into the folder where you place the installer
  - if an older portable Release install already exists there, it updates that copy in place
  - otherwise it performs a fresh install
  - downloads the matching Release snapshot
  - runs `first_setup.sh`
  - initializes Shogunate as a Release install

- install is pinned to the Release tag you downloaded
- rerunning a newer installer in the same folder updates that portable install while preserving local state
- that release install keeps using its own release metadata even if the folder lives inside another Git working tree

### Uninstalling a portable install

Portable installs include `Shogunate-Uninstaller.bat` inside the installed folder itself.

- run `Shogunate-Uninstaller.bat` from the installed folder
- it stops Shogunate tmux sessions if WSL is available
- it asks whether to preserve personal data outside the install folder or delete everything in the install
- it removes only Shogunate-managed files inside that folder
- unrelated files in the same folder are kept
- it keeps the parent folder itself
- after uninstall, you can clean-install again into the same folder

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

If an incoming tracked file collides with local edits, the installer/update flow keeps the local file in place and stores the incoming version under:

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

The launcher defaults to a clean start and then attaches to `goza-no-ma`. If a CLI needs login, follow the prompt in that CLI's tmux pane. Use `./Shogunate-Runtime.sh --resume` to keep existing runtime state, or `./Shogunate-Runtime.sh --no-attach` to start without attaching.

Role configuration can be opened before launch with `Shogunate-Configure-Roles.bat` on Windows, `./Shogunate-Configure-Roles.sh` on Linux / WSL, or `./Shogunate-Configure-Roles.command` on macOS.

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

It can also send commands into the Shogun pane when needed.

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
- place `multi-agent-shognate-installer-<version>.bat` there
- run it in place
- let it install the Shogunate into that folder

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
├── install.bat                # Windows installer / bootstrap entry
├── Shogunate-Runtime.bat      # Windows runtime launcher
├── Shogunate-Runtime.sh       # Linux / WSL runtime launcher
├── Shogunate-Runtime.command  # macOS Finder runtime launcher
├── Shogunate-Configure-Roles.bat      # Windows WSL role configurator launcher
├── Shogunate-Configure-Roles.sh       # Linux / WSL role configurator launcher
├── Shogunate-Configure-Roles.command  # macOS Finder role configurator launcher
├── updater.bat                # Legacy Windows updater script kept for compatibility
├── Shogunate-Uninstaller.bat  # Windows uninstaller included in installed copies
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

- portable installation into any folder
- the fork APK from GitHub Releases
- broader CLI support including Gemini / OpenCode / Kilo / localapi
- `goza-no-ma` as the runtime source of truth
- conservative defaults for stable operation

If you want upstream defaults and upstream distribution as-is, upstream is the more natural choice.

## Related Docs

- `android/README.md` - Android app details
- `docs/REQS.md` - normalized current requirements
- `docs/PUBLISHING.md` - privacy / cleanup policy before publication
- `docs/philosophy.md` - design philosophy
