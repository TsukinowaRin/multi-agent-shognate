<div align="center">

# Shogunate

**Package-installable multi-agent runtime for AI coding CLIs.**

Run a Shogun, Karo managers, Ashigaru workers, Gunshi strategist, and Gunkan auditor in visible `tmux` panes, backed by plain YAML queues and release-packaged installers.

[![Release](https://img.shields.io/badge/release-v5.2.0.3-ff6600?style=flat-square)](https://github.com/TsukinowaRin/multi-agent-shognate/releases/tag/v5.2.0.3)
[![License: MIT](https://img.shields.io/badge/License-MIT-yellow.svg)](LICENSE)

[English](README.md) | [日本語](README_ja.md)

</div>

<p align="center">
  <img src="images/screenshots/hero/latest-translucent-20260210-190453.png" alt="Shogunate tmux runtime" width="940">
</p>

## Quick Start

Install the fixed release package with cURL:

```bash
curl -fsSL https://raw.githubusercontent.com/TsukinowaRin/multi-agent-shognate/v5.2.0.3/scripts/shogunate_package_bootstrap.sh \
  | bash -s -- --version v5.2.0.3
```

Start Shogunate:

```bash
shogunate
```

The installer expands the runtime to `~/.shogunate/shogunate` and registers `~/.local/bin/shogunate`.

If the command is not found, reload your shell or add this to your shell profile:

```bash
export PATH="$HOME/.local/bin:$PATH"
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
shogunate                 # start runtime
shogunate clean           # clean start
shogunate resume          # resume previous runtime state
shogunate attach          # attach to tmux session shogunate
shogunate configure       # choose CLI per role
shogunate status          # show package/update metadata
shogunate aliases         # print shell alias source command
shogunate help            # show command help
```

Useful view aliases after sourcing the alias file:

```bash
source ~/.shogunate/shogunate/scripts/shell_aliases.sh

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
curl -fsSL https://raw.githubusercontent.com/TsukinowaRin/multi-agent-shognate/v5.2.0.3/scripts/shogunate_package_bootstrap.sh \
  | bash -s -- --version v5.2.0.3 \
      --prefix "$HOME/.shogunate/shogunate" \
      --bin-dir "$HOME/.local/bin"
```

Update or unpack without running setup:

```bash
curl -fsSL https://raw.githubusercontent.com/TsukinowaRin/multi-agent-shognate/v5.2.0.3/scripts/shogunate_package_bootstrap.sh \
  | bash -s -- --version v5.2.0.3 --no-setup
```

Use the same installed bootstrap later:

```bash
shogunate install --version v5.2.0.3 --no-setup
```

After this branch is published on `main`, the moving latest channel is:

```bash
curl -fsSL https://raw.githubusercontent.com/TsukinowaRin/multi-agent-shognate/main/scripts/shogunate_package_bootstrap.sh | bash
```

The npm wrapper calls the same bootstrap:

```bash
npx @tsukinowarin/shogunate install -- --version v5.2.0.3
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
shogunate-android-v5.2.0.3.apk
```

The Android app connects to the host runtime over SSH and targets the Shogun pane by default. First-time setup uses Shogunate Pair: the app keeps its private key, and the PC registers only the approved public key.

```bash
shogunate pair        # USB auto + Tailscale / LAN
```

Then open the Android app, choose USB or enter the Tailscale/LAN IP, and press Connect. The PC terminal shows the device name; approve it by entering the local Pair Password prompt. After pairing succeeds, Shogunate starts in resume mode and later connections use the saved SSH key without re-pairing.

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
bash first_setup.sh
bash shutsujin_departure.sh
```

Run the main checks before shipping:

```bash
bash -n scripts/shogunate_package_bootstrap.sh shutsujin_departure.sh
python3 -m unittest tests.unit.test_package_distribution
git diff --check
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
bash ~/.shogunate/shogunate/scripts/ensure_antigravity_keyring.sh
```

Generated instruction warning after package install:

```bash
bash ~/.shogunate/shogunate/scripts/ensure_generated_instructions.sh
```

## Release Versioning

Shogunate release tags use normal version tags such as:

```text
v5.0.0.0
v5.0.0.12
v5.2.0.1
v5.2.0.2
v5.2.0.3
```

Each release may include:

- `multi-agent-shognate-package.tar.gz`
- `multi-agent-shognate-package.zip`
- `shogunate-android-<version>.apk`

## License

MIT. See [LICENSE](LICENSE).
