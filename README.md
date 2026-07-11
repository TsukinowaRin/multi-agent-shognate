<div align="center">

# Shogunate

**Package-installable multi-agent runtime for AI coding CLIs.**

Run a Shogun, Karo managers, Ashigaru workers, Gunshi strategist, and Gunkan auditor in visible `tmux` panes, backed by plain YAML queues and release-packaged installers.

[![Release](https://img.shields.io/github/v/release/TsukinowaRin/multi-agent-shognate?style=flat-square)](https://github.com/TsukinowaRin/multi-agent-shognate/releases/latest)
[![License: MIT](https://img.shields.io/badge/License-MIT-yellow.svg)](LICENSE)

[English](README.md) | [日本語](README_ja.md)

</div>

## Overview

Shogunate is a local-first multi-agent runtime for AI coding CLIs. It turns one repository workspace into a visible `tmux` command center where a Shogun receives work, Karo managers plan and integrate, Ashigaru workers execute tasks, Gunshi reviews strategy, and Gunkan audits completion.

This repository contains the packaged runtime, role instructions, shell orchestration, queue-based agent messaging, Android pairing support, and release installers needed to run that system on Linux, macOS, or Windows with WSL2.

Shogunate is designed for developers who want:

- Multi-agent coding workflows without a hosted control plane
- Plain-file coordination through `queue/`, `dashboard.md`, and runtime metadata
- Role-specific CLI assignment across Codex, Claude Code, Copilot CLI, OpenCode, Kimi, Cursor, and Antigravity
- A cURL-installable runtime that can be updated or unpacked into a predictable local directory

## Installation

Install the latest release channel with cURL:

```bash
curl -fsSL https://raw.githubusercontent.com/TsukinowaRin/multi-agent-shognate/main/scripts/shogunate_package_bootstrap.sh | bash
```

Then move to the project you want Shogunate to work on and start it:

```bash
cd /path/to/your-project
shogunate
```

The installer downloads the latest GitHub Release package, expands the engine to `~/.shogunate/shogunate`, and registers `~/.local/bin/shogunate`. When you run `shogunate` from a project directory, it creates a project-specific runtime under `~/.shogunate/workspaces/`, so queues, logs, dashboard state, and `tmux` sessions do not mix across projects.

If the command is not found, reload your shell or add this to your shell profile:

```bash
export PATH="$HOME/.local/bin:$PATH"
```

If an older install left stale `css()` / `csm()` functions in `~/.bashrc`, rerun the latest release channel and then reload your shell:

```bash
curl -fsSL https://raw.githubusercontent.com/TsukinowaRin/multi-agent-shognate/main/scripts/shogunate_package_bootstrap.sh | bash
source ~/.bashrc
```

## Requirements

- Linux, macOS, or Windows with WSL2
- `bash`, `curl`, `tar`, `tmux`, `python3`
- At least one supported AI coding CLI:
  - OpenAI Codex
  - Claude Code
  - GitHub Copilot CLI
  - OpenCode
  - Kimi Code
  - Cursor
  - Antigravity (`agy`)

Authenticate the CLI in your normal shell before assigning it to a role:

```bash
codex
claude
opencode
agy
```

You only need to authenticate the CLIs you actually use.

## Common Commands

```bash
shogunate                 # start runtime for the current directory
shogunate clean           # clean start for the current directory
shogunate resume          # resume this project's runtime state
shogunate attach          # attach to this project's tmux session
shogunate configure       # choose CLI per role for this project
shogunate where           # show project/runtime/engine/session paths
shogunate projects        # list registered projects
shogunate battlefield     # list/start/stop registered project runtimes
shogunate app             # JSON API for mobile and desktop apps
shogunate status          # show package/update metadata
shogunate aliases         # print shell alias source command
shogunate help            # show command help
```

Target another project explicitly:

```bash
shogunate --project /path/to/another-project
shogunate attach --project /path/to/another-project
```

Register projects you open often and select them by name:

```bash
shogunate projects add /path/to/your-project --name myapp --select
shogunate projects
shogunate --project @myapp resume
shogunate open myapp
```

The registry is stored at `~/.shogunate/projects.json` by default. Running `shogunate` from a directory automatically remembers that directory, and the Android Battlefield tab also syncs opened remote projects into the same registry when the installed host command supports it.

Apps should use the battlefield API instead of guessing SSH shell commands or tmux pane names:

```bash
shogunate app capabilities --json
shogunate battlefield list --json
shogunate battlefield status myapp --json
shogunate battlefield start myapp --resume
shogunate battlefield start myapp --new
shogunate battlefield stop myapp
shogunate battlefield send myapp --role shogun "Implement the next task"
shogunate battlefield send myapp --role shogun --start "Implement the next task"
shogunate battlefield outbox myapp --json
shogunate battlefield roles myapp --json
shogunate battlefield sessions myapp --json
shogunate battlefield transcript myapp --json
```

This gives mobile and desktop clients the intended hierarchy: host connection, registered project battlefield, app chat session, and role chat target.
The list, sessions, transcript, and outbox commands work even when the Shogunate runtime is stopped. If an app sends a role message while the runtime is stopped, Shogunate stores it as a pending message; `start` or `send --start` resumes the project and attempts delivery to the role inbox.

Parallel Shogunate is supported. Start Shogunate from two different project directories and each project gets its own runtime copy and `tmux` session name.

Useful view aliases after sourcing the alias file:

```bash
eval "$(shogunate aliases)"

cgo   # Goza overview
csg   # Shogun
cgn   # Gunkan auditor
csk   # Karo
csa   # Ashigaru
cma   # multi-agent view
```

## Install Options

Install into explicit directories:

```bash
curl -fsSL https://raw.githubusercontent.com/TsukinowaRin/multi-agent-shognate/main/scripts/shogunate_package_bootstrap.sh | bash -s -- --prefix "$HOME/.shogunate/shogunate" --bin-dir "$HOME/.local/bin"
```

Update or unpack without running setup:

```bash
curl -fsSL https://raw.githubusercontent.com/TsukinowaRin/multi-agent-shognate/main/scripts/shogunate_package_bootstrap.sh | bash -s -- --no-setup
```

Pin an exact release only when you need reproducible installs:

```bash
curl -fsSL https://raw.githubusercontent.com/TsukinowaRin/multi-agent-shognate/v5.2.0.9/scripts/shogunate_package_bootstrap.sh | bash -s -- --version v5.2.0.9
```

Each GitHub Release page includes the version-pinned cURL command for that tag.

Use the same installed bootstrap later:

```bash
shogunate install --no-setup
```

The npm wrapper calls the same bootstrap:

```bash
npx @tsukinowarin/shogunate install
```

## What Shogunate Runs

Shogunate launches a visible `tmux` runtime:

```text
You
  |
  v
Shogun     command intake and delegation
  |
  v
Karo       planning, splitting, integration
  |
  +-- Ashigaru workers
  +-- Gunshi strategist / high-level review
  +-- Gunkan independent auditor
```

Agents communicate through files under `queue/`, `dashboard.md`, and runtime metadata. The coordination layer is local shell + `tmux`; model calls are made only by the CLI agents doing the work.

## Repository Structure

Shogunate is being organized as an upstream Shogun core plus a Shogunate MOD layer:

```text
upstream-facing compatibility surface
  AGENTS.md, instructions/, lib/, scripts/, top-level launchers
  kept for existing tools and release cURL URLs

Shogunate MOD canonical sources
  shogunate_mod/
    battlefield/ app-facing host/project/session/role API
    gunkan/    independent auditor and CoDD helpers
    package/   cURL package install and cwd-first workspace management
    pair/      Android Pair server
    projects/  registered project registry for CLI and app launchers
    runtime/   cwd/project/session helpers used by thin runtime entrypoints
    shell/     Shogunate view aliases
    status/    agent and rate-limit status commands
    watcher/   inbox/file-watch supervisors
    view/      Goza attach/focus helpers

stable compatibility entrypoints
  legacy scripts/*, lib/*, and top-level launchers delegate into shogunate_mod/
```

The wrapper paths stay stable for existing installs and release cURL commands. New Shogunate-only behavior should live under `shogunate_mod/` first, so upstream runtime updates remain easier to review.

## Role Configuration

Open the role/CLI selector:

```bash
shogunate configure
```

Typical setup:

```text
shogun   codex
karo     codex
gunshi   codex
gunkan   codex
ashigaru opencode / codex / claude / agy
```

Shogunate keeps role-local CLI state where needed while reusing your host authentication, so each role can have its own runtime settings without forcing repeated login.

## Gunkan Audit Role

`gunkan` is an independent audit role under Shogun, parallel to Karo. It checks requirements, reports, dashboard state, task completion, risky changes, and release coherence.

Gunkan does not assign normal work to Ashigaru and does not replace Karo. It writes audit output to:

```text
queue/reports/gunkan_report.yaml
```

Focus the Gunkan pane:

```bash
cgn
```

## Android Companion

The release page includes an Android APK when published:

```text
shogunate-android-<version>.apk
```

The Android app connects to the host runtime over SSH and targets the Shogun pane by default. First-time setup uses Shogunate Pair: the app keeps its private key, and the PC registers only the approved public key.

```bash
cd /path/to/your-project
shogunate pair        # USB auto + Tailscale / LAN for this project
```

Then open the Android app, choose USB or enter the Tailscale/LAN IP, and press Connect. The PC terminal shows the device name; approve it by entering the local Pair Password prompt. After pairing succeeds, the terminal prints `Pairing complete`, Shogunate starts in resume mode for that project, and Pair stops automatically. The app saves the project-specific `tmux` targets returned by Pair, so parallel Shogunate sessions do not cross-connect. Later connections use the saved SSH key without re-pairing.

For USB, the app should connect to `127.0.0.1`; `adb reverse` maps Android `127.0.0.1:2222` to the host SSH service. For wireless/Tailscale/LAN, the app should use the PC address that can actually reach SSH. The Pair terminal prints the exact returned destination as `returning SSH destination: user@host:port`.

To pair several devices in one session, run `shogunate pair --keep-running`.

For source checkout compatibility helpers:

```bash
bash android/tools/setup_android_ssh.sh --pair-usb
bash android/tools/setup_android_ssh.sh --pair-wireless
```

Runtime package archives intentionally do not include Android source; the APK is distributed as a release asset.

## Development Checkout

Use source checkout only when developing Shogunate itself:

```bash
git clone https://github.com/TsukinowaRin/multi-agent-shognate
cd multi-agent-shognate
bash shogunate_mod/package/first_setup.sh
bash shogunate_mod/runtime/entrypoint.sh
```

Run the main checks before shipping:

```bash
make package-check
```

Android build check:

```bash
cd android
./gradlew --no-daemon testDebugUnitTest assembleDebug
```

## Troubleshooting

`shogunate: command not found`

```bash
export PATH="$HOME/.local/bin:$PATH"
```

No TUI color:

```bash
echo "TERM=$TERM"
tput colors
printf '\033[31mRED\033[0m \033[32mGREEN\033[0m \033[34mBLUE\033[0m\n'
```

If `tput colors` is less than `256`, use a 256-color terminal or tmux profile.

Antigravity (`agy`) asks for login repeatedly:

```bash
bash ~/.shogunate/shogunate/shogunate_mod/cli/antigravity_keyring.sh
```

Generated instruction warning after package install:

```bash
bash ~/.shogunate/shogunate/shogunate_mod/instructions/ensure_generated.sh
```

## Release Versioning

Shogunate release tags use normal version tags such as:

```text
v5.0.0.0
v5.0.0.12
v5.2.0.1
v5.2.0.2
v5.2.0.3
v5.2.0.4
v5.2.0.5
v5.2.0.6
v5.2.0.7
v5.2.0.8
v5.2.0.9
```

Each release may include:

- `multi-agent-shognate-package.tar.gz`
- `multi-agent-shognate-package.zip`
- `shogunate-android-<version>.apk`

## License

MIT. See [LICENSE](LICENSE).
