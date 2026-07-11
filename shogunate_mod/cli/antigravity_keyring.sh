#!/usr/bin/env bash
set -u

# Best-effort preflight for Agy's Linux Secret Service auth store.
# This script never reads token contents and never deletes or recreates keyrings.

if [ "${SHOGUNATE_ANTIGRAVITY_KEYRING_CHECK:-1}" = "0" ]; then
    exit 0
fi

if [ "$(uname -s 2>/dev/null || true)" != "Linux" ]; then
    exit 0
fi

warn() {
    printf '[WARN] Antigravity keyring: %s\n' "$*" >&2
}

has_secret_service() {
    command -v busctl >/dev/null 2>&1 || return 1
    busctl --user --list 2>/dev/null | grep -q 'org.freedesktop.secrets'
}

if ! command -v secret-tool >/dev/null 2>&1; then
    warn "secret-tool is not installed; agy may ask for login every time. Install libsecret-tools."
    exit 0
fi

if ! command -v gnome-keyring-daemon >/dev/null 2>&1; then
    warn "gnome-keyring-daemon is not installed; agy may ask for login every time. Install gnome-keyring."
    exit 0
fi

if [ -z "${DBUS_SESSION_BUS_ADDRESS:-}" ]; then
    warn "DBUS_SESSION_BUS_ADDRESS is not set; Secret Service may be unreachable."
    exit 0
fi

if ! has_secret_service; then
    gnome-keyring-daemon --start --components=secrets >/dev/null 2>&1 || true
fi

if ! has_secret_service; then
    # Empty stdin only unlocks already-empty keyrings or creates an empty login
    # collection in environments that do not have one yet. A passworded keyring
    # remains locked and the user must unlock it manually.
    printf '\n' | gnome-keyring-daemon --daemonize --login >/dev/null 2>&1 || true
fi

if ! has_secret_service; then
    warn "org.freedesktop.secrets is not available; agy may ask for login again."
    exit 0
fi

if command -v timeout >/dev/null 2>&1; then
    if ! timeout 3s secret-tool lookup service shogunate-keyring-probe account antigravity >/dev/null 2>&1; then
        status=$?
        if [ "$status" -eq 124 ]; then
            warn "Secret Service did not respond; the default keyring may be locked."
        fi
    fi
fi

exit 0
