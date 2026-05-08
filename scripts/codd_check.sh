#!/usr/bin/env bash
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PROJECT_ROOT="$(cd "${SCRIPT_DIR}/.." && pwd)"

CODD_PACKAGE="${CODD_PACKAGE:-codd-dev}"
CODD_DEVELOPMENT_VERSION="${CODD_DEVELOPMENT_VERSION:-1.34.0}"
CODD_VERSION_SPEC="${CODD_VERSION_SPEC:-}"
CODD_FALLBACK_VERSION="${CODD_FALLBACK_VERSION:-${CODD_DEVELOPMENT_VERSION}}"
CODD_VENV="${CODD_VENV:-${PROJECT_ROOT}/.shogunate/codd-venv}"
CODD_AUTO_INSTALL="${CODD_AUTO_INSTALL:-0}"
CODD_DIFF_TARGET="${CODD_DIFF_TARGET:-HEAD}"

usage() {
    cat <<'EOF'
Usage: scripts/codd_check.sh [command]

Commands:
  install        Install/update codd-dev into .shogunate/codd-venv
  version        Show codd version and project requirement status
  build          Build .codd/dag.json
  verify         Run codd dag verify (default)
  audit          Run codd audit --skip-review when the optional CoDD bridge supports it
  help           Show this help

Environment:
  CODD_AUTO_INSTALL=1       Install codd-dev automatically if codd is missing
  CODD_VERSION_SPEC=>=1.34  Optional version spec; empty means latest release
  CODD_FALLBACK_VERSION=... Fallback version when latest/spec install fails
  CODD_VENV=.shogunate/...  Virtualenv path for local install
  CODD_DIFF_TARGET=HEAD     Diff target for audit
EOF
}

codd_cmd=()

find_codd() {
    if command -v codd >/dev/null 2>&1; then
        codd_cmd=("$(command -v codd)")
        return 0
    fi
    if [ -x "${CODD_VENV}/bin/codd" ]; then
        codd_cmd=("${CODD_VENV}/bin/codd")
        return 0
    fi
    if [ -x "${CODD_VENV}/bin/python" ] && "${CODD_VENV}/bin/python" -c 'import codd' >/dev/null 2>&1; then
        codd_cmd=("${CODD_VENV}/bin/python" -m codd)
        return 0
    fi
    if python3 -c 'import codd' >/dev/null 2>&1; then
        codd_cmd=(python3 -m codd)
        return 0
    fi
    return 1
}

python_missing_error() {
    cat >&2 <<'EOF'
Python3 or python3-venv is not ready.
CoDD is integrated by default and needs Python inside the WSL/Linux/macOS terminal.

Ubuntu / Debian:
  sudo apt update
  sudo apt install -y python3 python3-venv python3-pip

macOS:
  brew install python
EOF
}

ensure_python() {
    if ! command -v python3 >/dev/null 2>&1; then
        python_missing_error
        return 127
    fi
    if ! python3 -m venv --help >/dev/null 2>&1; then
        python_missing_error
        return 127
    fi
}

pip_install_codd() {
    local package_spec
    package_spec="${CODD_PACKAGE}${CODD_VERSION_SPEC}"
    echo "[codd] Installing latest compatible ${package_spec} into ${CODD_VENV}"
    if "${CODD_VENV}/bin/python" -m pip install --upgrade "${package_spec}"; then
        return 0
    fi

    echo "[codd] Latest/spec install failed; falling back to ${CODD_PACKAGE}==${CODD_FALLBACK_VERSION}" >&2
    "${CODD_VENV}/bin/python" -m pip install --upgrade "${CODD_PACKAGE}==${CODD_FALLBACK_VERSION}"
}

install_codd() {
    ensure_python
    mkdir -p "$(dirname "${CODD_VENV}")"
    if [ ! -x "${CODD_VENV}/bin/python" ]; then
        if ! python3 -m venv "${CODD_VENV}"; then
            python_missing_error
            return 127
        fi
    fi
    "${CODD_VENV}/bin/python" -m pip install --upgrade pip >/dev/null
    pip_install_codd
    if ! find_codd; then
        echo "CoDD package installed, but no runnable codd entrypoint was found." >&2
        return 127
    fi
}

run_codd() {
    "${codd_cmd[@]}" "$@"
}

ensure_codd() {
    if find_codd; then
        return 0
    fi
    if [ "${CODD_AUTO_INSTALL}" = "1" ]; then
        install_codd
        return 0
    fi
    cat >&2 <<EOF
CoDD CLI not found.
Run:
  scripts/codd_check.sh install
or:
  CODD_AUTO_INSTALL=1 scripts/codd_check.sh verify
EOF
    return 127
}

command_name="${1:-verify}"

case "${command_name}" in
    help|-h|--help)
        usage
        ;;
    install)
        install_codd
        run_codd version --check --path "${PROJECT_ROOT}" || true
        ;;
    version)
        ensure_codd
        run_codd version --check --path "${PROJECT_ROOT}"
        ;;
    build)
        ensure_codd
        run_codd dag build --path "${PROJECT_ROOT}"
        ;;
    verify)
        ensure_codd
        run_codd dag verify --path "${PROJECT_ROOT}"
        ;;
    audit)
        ensure_codd
        run_codd audit --path "${PROJECT_ROOT}" --diff "${CODD_DIFF_TARGET}" --skip-review
        ;;
    *)
        echo "Unknown command: ${command_name}" >&2
        usage >&2
        exit 2
        ;;
esac
