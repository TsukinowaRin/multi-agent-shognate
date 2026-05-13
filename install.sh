#!/usr/bin/env bash
set -euo pipefail

REPO_OWNER="TsukinowaRin"
REPO_NAME="multi-agent-shognate"
REPO_REF="main"
REPO_REF_KIND="heads"
REPO_VERSION_LABEL="main"
DOWNLOAD_URL="https://github.com/${REPO_OWNER}/${REPO_NAME}/archive/refs/${REPO_REF_KIND}/${REPO_REF}.zip"

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
INSTALL_DIR="$SCRIPT_DIR"
TEMP_ROOT="${TMPDIR:-/tmp}/${REPO_NAME}-installer-$$"
ZIP_PATH="${TEMP_ROOT}/${REPO_NAME}-${REPO_REF}.zip"
EXTRACT_ROOT="${TEMP_ROOT}/extract"
EXTRACTED_DIR=""
INSTALL_MODE="download"
REPO_DIR="$INSTALL_DIR"

cleanup() {
    rm -rf "$TEMP_ROOT"
}
trap cleanup EXIT

log() {
    printf '  %s\n' "$*"
}

fail() {
    printf '  [ERROR] %s\n' "$*" >&2
    exit 1
}

shell_quote() {
    printf "'%s'" "$(printf '%s' "$1" | sed "s/'/'\\\\''/g")"
}

download_file() {
    local url="$1"
    local out="$2"
    if command -v curl >/dev/null 2>&1; then
        curl -fL "$url" -o "$out"
    elif command -v wget >/dev/null 2>&1; then
        wget -O "$out" "$url"
    else
        fail "curl or wget is required to download release source."
    fi
}

extract_zip() {
    local zip="$1"
    local dest="$2"
    mkdir -p "$dest"
    if command -v unzip >/dev/null 2>&1; then
        unzip -q "$zip" -d "$dest"
    elif command -v bsdtar >/dev/null 2>&1; then
        bsdtar -xf "$zip" -C "$dest"
    elif command -v python3 >/dev/null 2>&1; then
        python3 - "$zip" "$dest" <<'PY'
from pathlib import Path
from zipfile import ZipFile
import sys

zip_path = Path(sys.argv[1])
dest = Path(sys.argv[2])
with ZipFile(zip_path) as zf:
    zf.extractall(dest)
PY
    else
        fail "unzip, bsdtar, or python3 is required to extract release source."
    fi
}

sync_tree() {
    local src="$1"
    local dst="$2"
    mkdir -p "$dst"
    if command -v rsync >/dev/null 2>&1; then
        rsync -a "$src"/ "$dst"/
    else
        (cd "$src" && tar cf - .) | (cd "$dst" && tar xf -)
    fi
}

require_python3() {
    command -v python3 >/dev/null 2>&1 || fail "python3 is required for release update metadata. Install python3 and re-run."
}

printf '\n'
printf '  +============================================================+\n'
printf '  |  [SHOGUN] multi-agent-shognate - Unix Installer            |\n'
printf '  |      Linux / macOS fresh install or in-place update        |\n'
printf '  +============================================================+\n'
printf '\n'

case "$(uname -s 2>/dev/null || echo unknown)" in
    Darwin) log "OS: macOS" ;;
    Linux) log "OS: Linux" ;;
    *) log "OS: $(uname -s 2>/dev/null || echo unknown)" ;;
esac

if [ -f "$SCRIPT_DIR/first_setup.sh" ]; then
    if [ -f "$SCRIPT_DIR/.shogunate/install_state.json" ]; then
        INSTALL_MODE="release-update"
        REPO_DIR="$SCRIPT_DIR"
    elif [ ! -d "$SCRIPT_DIR/.git" ] && [ -f "$SCRIPT_DIR/config/settings.yaml" ]; then
        INSTALL_MODE="release-update"
        REPO_DIR="$SCRIPT_DIR"
    else
        INSTALL_MODE="local"
        REPO_DIR="$SCRIPT_DIR"
    fi
fi

case "$INSTALL_MODE" in
    local)
        log "Mode: local repository"
        log "Repository: $REPO_DIR"
        ;;
    release-update)
        log "Mode: existing portable install update"
        log "Target: $REPO_DIR"
        log "Source ref: $REPO_VERSION_LABEL"
        ;;
    *)
        log "Mode: standalone release bootstrap"
        log "Source ref: $REPO_VERSION_LABEL"
        log "Download source: $DOWNLOAD_URL"
        log "Install target: $INSTALL_DIR"
        ;;
esac
printf '\n'

if [ "$INSTALL_MODE" != "local" ]; then
    mkdir -p "$TEMP_ROOT" "$EXTRACT_ROOT" "$INSTALL_DIR"
    log "[1/4] Downloading release source..."
    download_file "$DOWNLOAD_URL" "$ZIP_PATH"

    log "[2/4] Extracting release source..."
    extract_zip "$ZIP_PATH" "$EXTRACT_ROOT"
    EXTRACTED_DIR="$(find "$EXTRACT_ROOT" -mindepth 1 -maxdepth 1 -type d | head -n1)"
    [ -n "$EXTRACTED_DIR" ] && [ -f "$EXTRACTED_DIR/first_setup.sh" ] || fail "Extracted archive is missing first_setup.sh"

    if [ "$INSTALL_MODE" = "release-update" ]; then
        require_python3
        log "[3/4] Applying release update while preserving local state..."
        (
            cd "$REPO_DIR"
            python3 scripts/update_manager.py apply-source-release \
                --source-root "$EXTRACTED_DIR" \
                --ref "$REPO_REF" \
                --ref-kind "$REPO_REF_KIND" \
                --version-label "$REPO_VERSION_LABEL"
        )
    else
        log "[3/4] Syncing files into install target..."
        sync_tree "$EXTRACTED_DIR" "$INSTALL_DIR"
        REPO_DIR="$INSTALL_DIR"
    fi
else
    log "[1/4] Using local repository source..."
fi

log "[4/4] Running first_setup.sh..."
(
    cd "$REPO_DIR"
    bash first_setup.sh
)

if command -v python3 >/dev/null 2>&1; then
    UPDATE_INIT_CMD=(python3 scripts/update_manager.py init)
    if [ "$INSTALL_MODE" = "download" ]; then
        UPDATE_INIT_CMD+=(--install-mode release --ref "$REPO_REF" --ref-kind "$REPO_REF_KIND" --version-label "$REPO_VERSION_LABEL" --source-root "$EXTRACTED_DIR")
    fi
    (
        cd "$REPO_DIR"
        "${UPDATE_INIT_CMD[@]}" || true
    )
else
    log "[WARN] python3 not found; skipped update metadata initialization."
fi

printf '\n'
printf '  +============================================================+\n'
printf '  |  [OK] Install / update complete!                           |\n'
printf '  +============================================================+\n'
printf '\n'
log "Repository location: $REPO_DIR"
log "Daily startup:"
log "  cd $(shell_quote "$REPO_DIR") && ./Shogunate-Runtime.sh"
printf '\n'
