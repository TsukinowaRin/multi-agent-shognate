#!/usr/bin/env bash
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
MODE="auto"
SSH_PORT="${SSH_PORT:-22}"
ANDROID_PORT="${ANDROID_PORT:-2222}"
PROJECT_PATH="$SCRIPT_DIR"
SHOGUN_SESSION="${SHOGUN_SESSION:-shogun}"
AGENTS_SESSION="${AGENTS_SESSION:-multiagent}"

usage() {
    cat <<'EOF'
Usage:
  scripts/android_pairing_profile.sh [--mode auto|tailscale|usb] [--ssh-port PORT] [--android-port PORT] [--project PATH]

Prints a Shogunate Android connection profile JSON.

Security model:
  - Does not print passwords, private keys, tokens, or host secrets.
  - USB mode only runs adb reverse after the Android device is already trusted.
  - Tailscale mode only uses the local tailnet IP reported by tailscale.
EOF
}

json_escape() {
    local value="$1"
    value="${value//\\/\\\\}"
    value="${value//\"/\\\"}"
    value="${value//$'\n'/\\n}"
    printf '%s' "$value"
}

detect_tailscale_host() {
    command -v tailscale >/dev/null 2>&1 || return 1
    tailscale ip -4 2>/dev/null | head -n1
}

setup_usb_reverse() {
    command -v adb >/dev/null 2>&1 || {
        printf 'adb command not found. Install Android platform-tools first.\n' >&2
        return 1
    }
    adb reverse "tcp:${ANDROID_PORT}" "tcp:${SSH_PORT}" >/dev/null
    printf '127.0.0.1'
}

parse_args() {
    while [ "$#" -gt 0 ]; do
        case "$1" in
            --mode)
                MODE="${2:-}"
                shift 2
                ;;
            --ssh-port)
                SSH_PORT="${2:-}"
                shift 2
                ;;
            --android-port)
                ANDROID_PORT="${2:-}"
                shift 2
                ;;
            --project)
                PROJECT_PATH="${2:-}"
                shift 2
                ;;
            -h|--help)
                usage
                exit 0
                ;;
            *)
                usage >&2
                exit 64
                ;;
        esac
    done
}

main() {
    parse_args "$@"

    local host=""
    local port="$SSH_PORT"
    local mode_used="$MODE"

    case "$MODE" in
        tailscale)
            host="$(detect_tailscale_host)" || {
                printf 'tailscale IP not found. Is Tailscale running?\n' >&2
                return 1
            }
            ;;
        usb)
            host="$(setup_usb_reverse)"
            port="$ANDROID_PORT"
            ;;
        auto)
            if host="$(detect_tailscale_host)"; then
                mode_used="tailscale"
            elif command -v adb >/dev/null 2>&1; then
                host="$(setup_usb_reverse)"
                port="$ANDROID_PORT"
                mode_used="usb"
            else
                printf 'No Tailscale IP or adb command found. Use --mode tailscale or --mode usb after setup.\n' >&2
                return 1
            fi
            ;;
        *)
            usage >&2
            return 64
            ;;
    esac

    cat <<EOF
{
  "type": "shogunate-android-connection-profile",
  "mode": "$(json_escape "$mode_used")",
  "host": "$(json_escape "$host")",
  "port": "$port",
  "user": "$(json_escape "$(id -un)")",
  "projectPath": "$(json_escape "$PROJECT_PATH")",
  "shogunSession": "$(json_escape "$SHOGUN_SESSION")",
  "agentsSession": "$(json_escape "$AGENTS_SESSION")"
}
EOF
}

main "$@"
