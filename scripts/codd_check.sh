#!/usr/bin/env bash
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PROJECT_ROOT="$(cd "${SCRIPT_DIR}/.." && pwd)"

CODD_PACKAGE="${CODD_PACKAGE:-codd-dev}"
CODD_VERSION_SPEC="${CODD_VERSION_SPEC:-}"
CODD_FALLBACK_VERSION="${CODD_FALLBACK_VERSION:-1.34.0}"
CODD_VENV="${CODD_VENV:-${PROJECT_ROOT}/.shogunate/codd-venv}"
CODD_AUTO_INSTALL="${CODD_AUTO_INSTALL:-0}"

usage() {
    cat <<'EOF'
Usage: scripts/codd_check.sh [command]

Commands:
  install    Install/update codd-dev into .shogunate/codd-venv
  version    Show codd version when supported
  scan       Run codd scan --path .
  impact     Run codd impact
  validate   Run codd validate
  gunkan     Run scripts/gunkan_codd_audit.py --scope manual
  help       Show this help

Environment:
  CODD_AUTO_INSTALL=1       Install codd-dev automatically if codd is missing
  CODD_VERSION_SPEC=>=1.34  Optional pip version spec
  CODD_FALLBACK_VERSION=... Fallback version when latest/spec install fails
  CODD_VENV=.shogunate/...  Virtualenv path for local install
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
    if [ -x "${CODD_VENV}/Scripts/codd.exe" ]; then
        codd_cmd=("${CODD_VENV}/Scripts/codd.exe")
        return 0
    fi
    return 1
}

python_missing_error() {
    cat >&2 <<'EOF'
Python3 or python3-venv is not ready.

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

install_codd() {
    ensure_python
    mkdir -p "$(dirname "${CODD_VENV}")"
    if [ ! -x "${CODD_VENV}/bin/python" ]; then
        python3 -m venv "${CODD_VENV}" || {
            python_missing_error
            return 127
        }
    fi
    "${CODD_VENV}/bin/python" -m pip install --upgrade pip >/dev/null
    local package_spec="${CODD_PACKAGE}${CODD_VERSION_SPEC}"
    echo "[codd] Installing ${package_spec} into ${CODD_VENV}"
    if ! "${CODD_VENV}/bin/python" -m pip install --upgrade "${package_spec}"; then
        echo "[codd] Latest/spec install failed; falling back to ${CODD_PACKAGE}==${CODD_FALLBACK_VERSION}" >&2
        "${CODD_VENV}/bin/python" -m pip install --upgrade "${CODD_PACKAGE}==${CODD_FALLBACK_VERSION}"
    fi
}

ensure_codd() {
    if find_codd; then
        return 0
    fi
    if [ "${CODD_AUTO_INSTALL}" = "1" ]; then
        install_codd
        find_codd
        return 0
    fi
    cat >&2 <<EOF
CoDD CLI not found.
Run:
  scripts/codd_check.sh install
or:
  CODD_AUTO_INSTALL=1 scripts/codd_check.sh scan
EOF
    return 127
}

run_codd() {
    "${codd_cmd[@]}" "$@"
}

command_name="${1:-validate}"
case "${command_name}" in
    help|-h|--help)
        usage
        ;;
    install)
        install_codd
        find_codd
        run_codd --help >/dev/null
        ;;
    version)
        ensure_codd
        run_codd version --check --path "${PROJECT_ROOT}" || run_codd --version || run_codd --help
        ;;
    scan)
        ensure_codd
        run_codd scan --path "${PROJECT_ROOT}"
        ;;
    impact)
        ensure_codd
        (cd "${PROJECT_ROOT}" && run_codd impact)
        ;;
    validate)
        ensure_codd
        (cd "${PROJECT_ROOT}" && run_codd validate)
        ;;
    gunkan)
        python3 "${PROJECT_ROOT}/scripts/gunkan_codd_audit.py" --project-root "${PROJECT_ROOT}" --scope manual
        ;;
    *)
        usage >&2
        exit 2
        ;;
esac
