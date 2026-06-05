# Shogun Android Companion

Companion app for [multi-agent-shogun](https://github.com/yohey-w/multi-agent-shogun) — monitor and control your AI agent army from your phone.

<p align="center">
  <img src="screenshots/01_shogun_terminal.png" alt="Shogun Terminal" width="230">
  <img src="screenshots/02_agents_grid.png" alt="Agents Grid" width="230">
  <img src="screenshots/03_dashboard.png" alt="Dashboard" width="230">
</p>

## Features

### 4-Tab Navigation

| Tab | Function |
|-----|----------|
| **Shogun** | Live SSH terminal to the Shogun pane. Send text/voice commands, view ANSI-colored output with special key bar (Enter, C-c, C-b, arrows, Tab, ESC, etc.) |
| **Agents** | 9-pane grid view (Karo + 7 Ashigaru + Gunshi). Tap to expand fullscreen. Send commands to individual agents. |
| **Dashboard** | Renders `dashboard.md` as HTML with full table text selection and copy support. |
| **Settings** | SSH connection config (host, port, user, key/password), project path, tmux session names. |

### Key Features

- **Voice Input** — Japanese speech recognition with continuous listening mode. Dictate commands hands-free.
- **BGM** — 3 built-in Sengoku-themed tracks (shogun / shogun-reiwa / shogun-ashigirls). Tap to cycle through tracks. Auto-ducks during voice input.
- **Rate Limit Monitor** — Tap the FAB button on the Agents tab to check Claude Max usage (5h/7d windows, Sonnet/Opus breakdown, session/message counts) with visual progress bars.
- **Screenshot Sharing** — Share screenshots from other apps directly to Shogun via Android share sheet. Files are SFTP-transferred to the server.
- **ANSI Color Support** — Terminal output rendered with 256-color ANSI escape code parsing.
- **Special Keys Bar** — Quick access to Enter, C-c, C-b, arrows, Tab, ESC, C-o, C-d for tmux/Claude Code workflow.
- **Auto-Refresh** — Shogun pane (3s), Agents grid (5s) with batched SSH for efficiency.
- **Text Selection** — Long-press to select and copy text in all screens.

<p align="center">
  <img src="screenshots/04_settings.png" alt="Settings" width="230">
  <img src="screenshots/05_ratelimit.png" alt="Rate Limit" width="230">
</p>

## Tech Stack

- **Language**: Kotlin
- **UI**: Jetpack Compose + Material 3
- **SSH**: JSch (mwiede fork) 0.2.21
- **Markdown→HTML**: commonmark-java (GFM tables) → WebView
- **Voice**: Android SpeechRecognizer API (ja-JP)
- **Min SDK**: 26 (Android 8.0) / Target: 34

## Install

Download the pre-built APK from [`release/multi-agent-shogun.apk`](release/multi-agent-shogun.apk) and sideload it.

Or build from source:

```bash
./gradlew assembleDebug
# APK: app/build/outputs/apk/debug/app-debug.apk
```

## Setup

1. Launch the app → **Settings** tab
2. On the host, run one of:
   - USB key pairing: `bash android/tools/setup_android_ssh.sh --pair-usb`
   - USB: `bash android/tools/setup_android_ssh.sh --usb`
   - Wireless: `bash android/tools/setup_android_ssh.sh --wireless`
   - Windows/WSL: double-click `android/tools/setup_android_ssh.bat`, or run the `.sh` from WSL
3. USB key pairing creates or reuses a dedicated SSH key after confirmation, authorizes the public key on the PC, transfers the private key into the Android app private storage, and sends a key-auth setup intent. USB setup automatically sends a `shogunate://setup` intent to the app when the APK is installed. Wireless setup prints a complete setup URI for each candidate IP and a terminal QR when `qrencode` is available.
4. For manual setup, tap **USB接続** or **無線接続**, then tap **標準値を入力**. When you have a setup URI, use **貼付** → **URI取込** in Settings to import host/port/user/project/tmux target.
5. Enter SSH connection info:
   - **Host**: USB uses `127.0.0.1`; wireless uses your Tailscale/LAN IP
   - **Port**: USB uses `2222`; wireless uses the SSH port printed by `setup_android_ssh.sh --wireless` (`22` by default, or another port such as `2223` when WSL is configured that way)
   - **User**: Your SSH username
   - **Key Path** or **Password**: Authentication method
   - **Project Path**: Server-side path to multi-agent-shogun (e.g., `/mnt/c/tools/multi-agent-shogun`)
   - **Shogun target**: default is `agent:shogun`, which auto-detects the pane with `@agent_id=shogun`
   - **Agents target**: default is `shogunate:goza`
6. Tap **接続診断** to save settings and verify SSH, `tmux`, project path, Shogun target, Agents target, and `dashboard.md`.
7. Once the check passes, switch to the **Shogun** tab → auto-connects to the Shogun pane only.

### Prerequisites

- SSH server running on the host machine
- tmux sessions already launched via `shutsujin_departure.sh`
- Network connectivity between phone and server: USB debugging + `adb reverse`, LAN, or Tailscale
- `adb` for USB setup
- USB key pairing uses debug / prerelease APK `run-as`. Release APK pairing should move to app-side key generation or a temporary pairing endpoint.

## Architecture

```
Android App
    │
    ├── ShogunScreen ──── ShogunViewModel ──┐
    ├── AgentsScreen ──── AgentsViewModel ──┤── SshManager (singleton)
    ├── DashboardScreen ─ DashboardViewModel┤      │
    └── SettingsScreen                      │   JSch SSH
                                            │      │
                                            └──────┤
                                                   ▼
                                            tmux (WSL2/Linux)
                                                   │
                                            ┌──────┴──────┐
                                            │  capture-pane │ (read)
                                            │  send-keys    │ (write)
                                            └──────────────┘
```

## License

MIT — Same as the parent project.
