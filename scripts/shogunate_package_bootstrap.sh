#!/usr/bin/env bash
set -euo pipefail

REPO_OWNER="${SHOGUNATE_REPO_OWNER:-TsukinowaRin}"
REPO_NAME="${SHOGUNATE_REPO_NAME:-multi-agent-shognate}"
VERSION="latest"
PREFIX="${SHOGUNATE_HOME:-$HOME/.shogunate/shogunate}"
RUN_SETUP=1

usage() {
    cat <<'EOF'
Usage:
  curl -fsSL https://raw.githubusercontent.com/TsukinowaRin/multi-agent-shognate/main/scripts/shogunate_package_bootstrap.sh | bash
  curl -fsSL .../shogunate_package_bootstrap.sh | bash -s -- --version v4.6.0.12 --prefix ~/.shogunate/shogunate

Options:
  --version TAG    GitHub Release tag to install. Defaults to latest.
  --prefix DIR     Install/update directory. Defaults to $SHOGUNATE_HOME or ~/.shogunate/shogunate.
  --no-setup       Extract package but do not run first_setup.sh.
  -h, --help       Show this help.
EOF
}

log() {
    printf '[shogunate-package] %s\n' "$*"
}

fail() {
    printf '[shogunate-package] ERROR: %s\n' "$*" >&2
    exit 1
}

while [ "$#" -gt 0 ]; do
    case "$1" in
        --version)
            [ "${2:-}" ] || fail "--version requires a tag"
            VERSION="${2:-}"
            shift 2
            ;;
        --prefix)
            [ "${2:-}" ] || fail "--prefix requires a directory"
            PREFIX="${2:-}"
            shift 2
            ;;
        --no-setup)
            RUN_SETUP=0
            shift
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

[ -n "$PREFIX" ] || fail "--prefix must not be empty"
command -v curl >/dev/null 2>&1 || fail "curl is required"
command -v tar >/dev/null 2>&1 || fail "tar is required"

if [ "$VERSION" = "latest" ]; then
    PACKAGE_URL="https://github.com/${REPO_OWNER}/${REPO_NAME}/releases/latest/download/${REPO_NAME}-package.tar.gz"
    VERSION_LABEL="latest"
else
    PACKAGE_URL="https://github.com/${REPO_OWNER}/${REPO_NAME}/releases/download/${VERSION}/${REPO_NAME}-package.tar.gz"
    VERSION_LABEL="$VERSION"
fi

TMP_DIR="$(mktemp -d "${TMPDIR:-/tmp}/${REPO_NAME}-package.XXXXXX")"
cleanup() {
    rm -rf "$TMP_DIR"
}
trap cleanup EXIT

PACKAGE_PATH="$TMP_DIR/package.tar.gz"

log "download: $PACKAGE_URL"
curl -fL "$PACKAGE_URL" -o "$PACKAGE_PATH"

mkdir -p "$PREFIX"
log "extract: $PREFIX"
tar -xzf "$PACKAGE_PATH" -C "$PREFIX" --strip-components=1

# Remove deprecated installer files from older installs. Runtime launchers remain.
rm -f \
    "$PREFIX/install.bat" \
    "$PREFIX/install.sh" \
    "$PREFIX/install.command" \
    "$PREFIX/Shogunate-Uninstaller.bat"

if [ "$RUN_SETUP" = "1" ]; then
    if [ -f "$PREFIX/first_setup.sh" ]; then
        log "run first_setup.sh"
        (cd "$PREFIX" && bash first_setup.sh)
    else
        log "first_setup.sh not found; skipped"
    fi
fi

if command -v python3 >/dev/null 2>&1 && [ -f "$PREFIX/scripts/update_manager.py" ]; then
    if python3 -c "import yaml" >/dev/null 2>&1; then
        log "initialize package update metadata"
        (cd "$PREFIX" && python3 scripts/update_manager.py init \
            --install-mode release \
            --ref "$VERSION_LABEL" \
            --ref-kind tags \
            --version-label "$VERSION_LABEL" \
            --source-root "$PREFIX" \
            --auto-update false) || true
    else
        log "PyYAML not available; update metadata initialization skipped"
    fi
fi

log "done"
log "run: cd $PREFIX && ./Shogunate-Runtime.sh"
