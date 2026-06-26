#!/usr/bin/env bash
set -euo pipefail

REPO_OWNER="${SHOGUNATE_REPO_OWNER:-TsukinowaRin}"
REPO_NAME="${SHOGUNATE_REPO_NAME:-multi-agent-shognate}"
VERSION="latest"

if [ "${BASH_SOURCE+x}" = x ] && [ "${#BASH_SOURCE[@]}" -gt 0 ]; then
    SCRIPT_SOURCE="${BASH_SOURCE[0]}"
else
    SCRIPT_SOURCE=""
fi
SCRIPT_DIR="$(cd "$(dirname "$SCRIPT_SOURCE")" >/dev/null 2>&1 && pwd || true)"
if [ -n "$SCRIPT_DIR" ] && [ -f "$SCRIPT_DIR/../shogunate_mod/package/bootstrap.sh" ]; then
    exec bash "$SCRIPT_DIR/../shogunate_mod/package/bootstrap.sh" "$@"
fi

args=("$@")
idx=0
while [ "$idx" -lt "${#args[@]}" ]; do
    case "${args[$idx]}" in
        --version)
            next=$((idx + 1))
            if [ "$next" -lt "${#args[@]}" ]; then
                VERSION="${args[$next]}"
            fi
            idx=$((idx + 2))
            ;;
        --version=*)
            VERSION="${args[$idx]#--version=}"
            idx=$((idx + 1))
            ;;
        *)
            idx=$((idx + 1))
            ;;
    esac
done

if [ "$VERSION" = "latest" ]; then
    REF="${SHOGUNATE_BOOTSTRAP_REF:-main}"
else
    REF="$VERSION"
fi

command -v curl >/dev/null 2>&1 || {
    printf '[shogunate-package] ERROR: curl is required\n' >&2
    exit 1
}

MOD_BOOTSTRAP_URL="https://raw.githubusercontent.com/${REPO_OWNER}/${REPO_NAME}/${REF}/shogunate_mod/package/bootstrap.sh"
curl -fsSL "$MOD_BOOTSTRAP_URL" | bash -s -- "$@"
