<div align="center">

# multi-agent-shognate

**A portable, multi-CLI fork of multi-agent-shogun for tmux-first coding and Android remote operation.**

[![GitHub Stars](https://img.shields.io/github/stars/TsukinowaRin/multi-agent-shognate?style=social)](https://github.com/TsukinowaRin/multi-agent-shognate)
[![License: MIT](https://img.shields.io/badge/License-MIT-yellow.svg)](https://opensource.org/licenses/MIT)
[![Shell](https://img.shields.io/badge/Shell%2FBash-100%25-green)]()

[English](README.md) | [日本語](README_ja.md)

</div>

<p align="center">
  <img src="images/screenshots/hero/latest-translucent-20260210-190453.png" alt="Shogun pane controlling multiple agents" width="940">
</p>

## What This Repository Is

`multi-agent-shognate` is a fork of [`multi-agent-shogun`](https://github.com/yohey-w/multi-agent-shogun) that keeps the upstream concept but changes the operational defaults.

This repository is optimized for:

- `tmux`-first operation
- portable installation into any workspace folder
- Android remote access through the fork APK
- broader multi-CLI coverage than upstream
- conservative default topology: all roles on `codex`, `model: auto`, and only `ashigaru1` / `ashigaru2` active by default

If you want the short version:

- install the system into the folder where you want to work
- launch `shutsujin_departure.sh`
- talk to the Shogun
- let Karo decide staffing and parallelism from intent

## What Is Different From Upstream

| Topic | Upstream | This fork |
|---|---|---|
| Runtime layout | Split tmux sessions are the main runtime | `goza-no-ma:overview` is the canonical runtime; `shogun` / `gunshi` / `multiagent` remain as Android-compatible proxy sessions |
| Default active workers | Historically described as a larger formation | Default active force is `ashigaru1` and `ashigaru2` only |
| Default CLI setup | Upstream defaults | Conservative `codex` defaults for all roles, `model: auto` |
| CLI coverage | Core upstream CLIs | Adds `Gemini CLI`, `OpenCode`, `Kilo`, `localapi`, plus local-provider sync for `Ollama` / `LM Studio` |
| Android app | Upstream Android app / APK | Fork APK is published in this repository's Releases and is the supported build here |
| Windows installer | Manual / repo-based flow | Portable `multi-agent-shognate-installer.bat` published in Releases; installs into the folder containing the installer |
| Karo behavior | User can guide team formation by intent | Karo is explicitly expected to infer decomposition, headcount, and parallelism autonomously from the lord's command |

## Core Model

The command chain is still the Shogun model:

```text
You
 -> Shogun
 -> Karo
 -> Ashigaru / Gunshi
```

The important operational rule in this fork is:

- current force size comes from `topology.active_ashigaru`
- historical mentions of `ashigaru1..8` are not treated as the live roster
- Karo should adapt staffing to the configured active force and the current task

## Supported CLIs And Vendors

This fork is intentionally not locked to one vendor.

### Supported agent CLI types

| CLI type | Typical vendor / backend | Notes |
|---|---|---|
| `codex` | OpenAI Codex CLI | Default in this fork |
| `claude` | Anthropic Claude Code | Supported like upstream |
| `copilot` | GitHub Copilot CLI | Supported like upstream |
| `kimi` | Kimi Code | Supported like upstream |
| `gemini` | Gemini CLI | Explicitly supported in this fork |
| `opencode` | OpenCode CLI | Added in this fork |
| `kilo` | Kilo CLI | Added in this fork |
| `localapi` | OpenAI-compatible local endpoint | For `Ollama`, `LM Studio`, llama.cpp server, or similar |

### Default permission / approval stance

All agent CLIs are configured to start in a no-approval-by-default mode in this fork.

| CLI type | Default unattended stance |
|---|---|
| `claude` | `--dangerously-skip-permissions` |
| `codex` | `--dangerously-bypass-approvals-and-sandbox` |
| `copilot` | `--yolo` |
| `kimi` | `--yolo` |
| `gemini` | `--yolo` |
| `opencode` | generated `opencode.json` sets `permission: allow` |
| `kilo` | generated `opencode.json` sets `permission: allow` |
| `localapi` | no separate approval layer; local REPL is launched directly |

For Codex specifically, this fork also isolates runtime state per agent by launching each role with its own repo-local `CODEX_HOME`. That keeps Shogun-side model or reasoning choices from leaking into VSCode Codex or unrelated Codex CLI sessions.

### Local-provider support

`localapi` is the bridge for local or self-hosted model providers. In practice this means:

- `Ollama`
- `LM Studio`
- llama.cpp server
- any OpenAI-compatible local endpoint

### Role-by-role configuration

Use this when you want to mix vendors or models per role:

```bash
bash scripts/configure_agents.sh
```

That script lets you set:

- CLI type per role
- model per role
- Codex reasoning effort
- Gemini thinking level / budget
- OpenCode / Kilo provider settings
- active Ashigaru count

## Installation

### Recommended: Windows portable installer

Use this when you want a self-contained install in a folder of your choice.

1. Open this repository's **GitHub Releases**.
2. Download `multi-agent-shognate-installer.bat`.
3. Put it in the folder where you want the Shogunate system to live.
4. Run it.

Important behavior:

- the installer downloads the **same tagged source version** as the Release you downloaded it from
- it installs into the **same folder that contains `install.bat`**
- it checks WSL2 / Ubuntu and runs `first_setup.sh` automatically when possible

This is the main portable workflow for this fork.

### Manual install from clone or ZIP

Use this when you want to manage the repo directly.

```bash
git clone https://github.com/TsukinowaRin/multi-agent-shognate
cd multi-agent-shognate
bash first_setup.sh
```

If you downloaded a ZIP instead of cloning, unpack it and run the same command from the repository root.

### What `first_setup.sh` does

`first_setup.sh` is expected to create local runtime configuration on first run.

That includes:

- local config generation such as `config/settings.yaml`
- dependency checks
- CLI bootstrap support
- tmux-oriented runtime preparation

`config/settings.yaml` is intentionally local-only in this fork. It is not part of the published Git tree.

## First Launch

After installation:

```bash
bash shutsujin_departure.sh
```

That brings up the runtime and the compatibility sessions.

Useful commands:

```bash
bash scripts/goza_no_ma.sh
bash scripts/focus_agent_pane.sh shogun
bash scripts/focus_agent_pane.sh karo
bash scripts/focus_agent_pane.sh gunshi
```

### Canonical and compatibility sessions

This matters because the Android app depends on it.

| Session | Purpose |
|---|---|
| `goza-no-ma:overview` | Canonical runtime in this fork |
| `shogun:main` | Android-compatible Shogun target |
| `gunshi:main` | Android-compatible Gunshi target |
| `multiagent:agents` | Android-compatible Karo / Ashigaru target |

## Android App And APK

This repository ships its **own** Android app build.

Do not use the upstream APK here.

### Supported APK for this fork

Download the APK from this repository's **GitHub Releases**.

Use the asset named like:

- `multi-agent-shognate-android-*.apk`

This fork APK is the supported Android app for this repository.

### What the Android app does

The APK is a remote control and monitoring client.

It connects to a running Shogunate host over SSH and then reads:

- the `shogun` tmux session
- the `multiagent` tmux session
- `dashboard.md`

It can also send commands to the Shogun pane.

### Android connection model

The app is SSH-based. It does not require a specific VPN product, but the phone must be able to reach the host over SSH.

You need:

- reachable SSH host or hostname
- SSH port
- Linux username on the host
- password or key for that Linux user
- project path on the host
- session names

Typical values for this fork:

| Field | Value |
|---|---|
| Shogun session | `shogun` |
| Agents session | `multiagent` |
| Project path | the repository root on the host |

Notes:

- initial Android settings are intentionally blank or non-identifying
- SSH settings are not baked with personal hostnames, IPs, or topics
- the APK also has an `ntfy` topic field for app-side notification subscription

## Notifications (`ntfy`)

This fork supports `ntfy`, but keep the roles clear:

- server-side Shogunate notifications use local config such as `config/settings.yaml`
- the Android app can subscribe directly to an `ntfy` topic for phone-side notifications

Local topics and other personal values are treated as private and should stay out of the published tree.

## Portable Workspace Usage

This system is intended to be portable.

If you want the Shogunate system to work inside another workspace, the recommended pattern is:

- create or choose the target workspace folder
- place `multi-agent-shognate-installer.bat` there
- run it there
- let the system install into that same folder

That keeps these runtime artifacts local to that workspace:

- `queue/`
- `logs/`
- `dashboard.md`
- `config/settings.yaml`
- tmux runtime state

## Recommended Defaults In This Fork

Current default stance:

- all roles start on `codex`
- `model: auto`
- `ashigaru1` and `ashigaru2` active by default
- Karo decides staffing autonomously from intent

If you want to expand the force, change the active topology rather than assuming historical worker slots are live.

## Key Commands

```bash
bash first_setup.sh
bash shutsujin_departure.sh
bash scripts/configure_agents.sh
bash scripts/goza_no_ma.sh
bash scripts/focus_agent_pane.sh shogun
bash scripts/focus_agent_pane.sh karo
bash scripts/prepublish_check.sh
```

## Repository Layout

```text
multi-agent-shognate/
├── android/                   # Fork Android app source
├── config/                    # Local/runtime configuration templates
├── docs/                      # Requirements, plans, publishing policy
├── instructions/              # Shared and generated CLI instructions
├── lib/                       # Shell helper libraries
├── scripts/                   # Runtime, bootstrap, bridge, watcher scripts
├── tests/                     # Unit and smoke tests
├── install.bat                # Windows installer / bootstrap entry point
├── first_setup.sh             # First-time setup
└── shutsujin_departure.sh     # Runtime launcher
```

## Publish Hygiene

This fork treats some files as local-only by design.

Examples:

- `config/settings.yaml`
- runtime queue state
- local logs
- private notification topics
- local hostnames, paths, and IPs

Before publishing, run:

```bash
bash scripts/prepublish_check.sh
```

## When To Choose This Fork

Choose this fork if you want:

- portable installation into arbitrary workspace folders
- a maintained fork APK in Releases
- explicit multi-CLI coverage including Gemini / OpenCode / Kilo / localapi
- tmux-first operation with `goza-no-ma` as the real runtime
- conservative defaults and fewer surprises in published state

Choose upstream if you want the original project with its original defaults and release story.

## Related Documents

- `android/README.md` - Android app details
- `docs/REQS.md` - normalized current requirements
- `docs/PUBLISHING.md` - publish-time privacy and cleanup policy
- `docs/philosophy.md` - design philosophy
