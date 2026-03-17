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
- conservative defaults: every role uses `codex`, `model: auto`, and the initial active ashigaru are only `ashigaru1` and `ashigaru2`

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
| default CLI | upstream defaults | all roles default to `codex` with `model: auto` |
| CLI coverage | core upstream CLIs | adds `Gemini CLI`, `OpenCode`, `Kilo`, `localapi`, and local-provider bridges such as `Ollama` / `LM Studio` |
| Android distribution | upstream Android app / APK | the fork APK in this repo's Releases is the supported distribution |
| Windows installer | repo-oriented setup flow | Release installer `multi-agent-shognate-installer.bat` installs portably into the folder where you place it |
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
| `codex` | `--dangerously-bypass-approvals-and-sandbox` |
| `copilot` | `--yolo` |
| `kimi` | `--yolo` |
| `gemini` | `--yolo` |
| `opencode` | generated `opencode.json` sets `permission: allow` |
| `kilo` | generated `opencode.json` sets `permission: allow` |
| `localapi` | launches the local REPL directly without a separate approval layer |

For Codex specifically, each role launches with its own repo-local `CODEX_HOME`. That keeps Shogun-side model or `reasoning_effort` choices from leaking into VSCode Codex or unrelated Codex CLI sessions.

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

### Per-role CLI and model settings

Use this when you want different CLIs or models per role:

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
2. Download `multi-agent-shognate-installer.bat`
3. Put it into the folder where you want the system installed
4. Run it

Important behavior:

- the installer downloads the source for the **same Release tag** it was downloaded from
- it installs into the **same folder where the installer itself is placed**
- it checks WSL2 / Ubuntu and, when possible, runs `first_setup.sh` automatically

This is the standard Windows install path for this fork.

### Manual install from clone or ZIP

If you want to manage the repo directly:

```bash
git clone https://github.com/TsukinowaRin/multi-agent-shognate
cd multi-agent-shognate
bash first_setup.sh
```

The same applies if you unpack a ZIP and run from the repo root.

### What `first_setup.sh` does

`first_setup.sh` is responsible for local bootstrap. It typically:

- creates local config files such as `config/settings.yaml`
- checks dependencies
- helps bootstrap CLIs
- prepares the tmux runtime

In this fork, `config/settings.yaml` is local-only and is not part of the published Git tree.

## First Launch

After installation:

```bash
bash shutsujin_departure.sh
```

Useful commands after startup:

```bash
bash scripts/goza_no_ma.sh
bash scripts/focus_agent_pane.sh shogun
bash scripts/focus_agent_pane.sh karo
bash scripts/focus_agent_pane.sh gunshi
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

## Notifications (`ntfy`)

`ntfy` is supported, but it is safer to think of server-side and Android-side usage separately.

- server-side Shogunate notifications use local config such as `config/settings.yaml`
- the Android app can subscribe to an `ntfy` topic itself

Local values such as `ntfy_topic` are treated as private and are not published in the repo tree.

## Portable Use In Another Workspace

This system can be used portably.

If you want it in a different workspace, the intended flow is:

- create or choose the target folder
- place `multi-agent-shognate-installer.bat` there
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
- `model: auto`
- initial active ashigaru are `ashigaru1` and `ashigaru2`
- Karo is expected to infer staffing from the task intent

If you want more ashigaru, change the active topology instead of relying on historical 1-8 references.

## Common Commands

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
├── android/                   # fork Android app
├── config/                    # local/runtime config templates
├── docs/                      # requirements, plans, publishing policy
├── instructions/              # shared and generated CLI instructions
├── lib/                       # shell helper library
├── scripts/                   # runtime, bootstrap, bridge, watcher
├── tests/                     # unit and smoke tests
├── install.bat                # Windows installer / bootstrap entry
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
