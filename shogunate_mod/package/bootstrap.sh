#!/usr/bin/env bash
set -euo pipefail

REPO_OWNER="${SHOGUNATE_REPO_OWNER:-TsukinowaRin}"
REPO_NAME="${SHOGUNATE_REPO_NAME:-multi-agent-shognate}"
VERSION="latest"
PREFIX="${SHOGUNATE_HOME:-$HOME/.shogunate/shogunate}"
BIN_DIR="${SHOGUNATE_BIN_DIR:-$HOME/.local/bin}"
RUN_SETUP=1

usage() {
    cat <<'EOF'
Usage:
  curl -fsSL https://raw.githubusercontent.com/TsukinowaRin/multi-agent-shognate/main/scripts/shogunate_package_bootstrap.sh | bash
  curl -fsSL .../shogunate_package_bootstrap.sh | bash -s -- --version v5.2.0.4 --prefix ~/.shogunate/shogunate

Options:
  --version TAG    GitHub Release tag to install. Defaults to latest.
  --prefix DIR     Install/update directory. Defaults to $SHOGUNATE_HOME or ~/.shogunate/shogunate.
  --bin-dir DIR    Install the shogunate command here. Defaults to ~/.local/bin.
  --no-setup       Extract package but do not run first_setup.sh.
  -h, --help       Show this help.

Environment:
  SHOGUNATE_PACKAGE_URL  Override package URL for release-channel smoke tests.
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
        --bin-dir)
            [ "${2:-}" ] || fail "--bin-dir requires a directory"
            BIN_DIR="${2:-}"
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
[ -n "$BIN_DIR" ] || fail "--bin-dir must not be empty"
command -v curl >/dev/null 2>&1 || fail "curl is required"
command -v tar >/dev/null 2>&1 || fail "tar is required"

if [ "$VERSION" = "latest" ]; then
    PACKAGE_URL="https://github.com/${REPO_OWNER}/${REPO_NAME}/releases/latest/download/${REPO_NAME}-package.tar.gz"
    VERSION_LABEL="latest"
else
    PACKAGE_URL="https://github.com/${REPO_OWNER}/${REPO_NAME}/releases/download/${VERSION}/${REPO_NAME}-package.tar.gz"
    VERSION_LABEL="$VERSION"
fi
PACKAGE_URL="${SHOGUNATE_PACKAGE_URL:-$PACKAGE_URL}"

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

if command -v python3 >/dev/null 2>&1 && [ -f "$PREFIX/shogunate_mod/update/manager.py" ]; then
    if python3 -c "import yaml" >/dev/null 2>&1; then
        log "initialize package update metadata"
        (cd "$PREFIX" && python3 shogunate_mod/update/manager.py init \
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

if [ "${SHOGUNATE_SKIP_BIN:-0}" != "1" ]; then
    mkdir -p "$BIN_DIR"
    PREFIX_QUOTED="$(printf '%q' "$PREFIX")"
    cat > "$BIN_DIR/shogunate" <<EOF
#!/usr/bin/env bash
set -euo pipefail

SHOGUNATE_INSTALL_DIR=${PREFIX_QUOTED}

usage() {
    cat <<'USAGE'
Usage:
  cd <project> && shogunate  Start Shogunate for the current project
  shogunate run [args...]   Start Shogunate runtime with args
  shogunate clean           Clean start
  shogunate resume          Resume start
  shogunate attach          Attach to this project's tmux session
  shogunate pair [opts]     Pair Android app over USB auto + Tailscale/LAN
  shogunate configure       Open role/CLI configuration
  shogunate where           Show this project's engine/runtime/session paths
  shogunate status          Show package update status
  shogunate aliases         Print shell alias setup command
  shogunate install [opts]  Run package bootstrap again
  shogunate home            Open a shell in the installed Shogunate engine
  shogunate help            Show this help

Project options:
  --project DIR             Use DIR instead of the current directory

Pair options are forwarded to scripts/shogunate_pair_server.py.
Set SHOGUNATE_PAIR_PASSWORD to require a fixed local approval password.
Runtime args are forwarded to Shogunate-Runtime.sh.
USAGE
}

fail() {
    printf 'shogunate: ERROR: %s\n' "\$*" >&2
    exit 1
}

PROJECT_DIR="\$(pwd -P)"
RUNTIME_ARGS=()

parse_project_args() {
    RUNTIME_ARGS=()
    while [ "\$#" -gt 0 ]; do
        case "\$1" in
            --project)
                [ "\${2:-}" ] || fail "--project requires a directory"
                PROJECT_DIR="\$2"
                shift 2
                ;;
            --project=*)
                PROJECT_DIR="\${1#--project=}"
                shift
                ;;
            *)
                RUNTIME_ARGS+=("\$1")
                shift
                ;;
        esac
    done
}

project_hash() {
    if command -v sha1sum >/dev/null 2>&1; then
        printf '%s' "\$1" | sha1sum | awk '{print substr(\$1,1,8)}'
    elif command -v shasum >/dev/null 2>&1; then
        printf '%s' "\$1" | shasum | awk '{print substr(\$1,1,8)}'
    else
        printf '%s' "\$1" | cksum | awk '{print \$1}'
    fi
}

project_slug() {
    local base slug
    base="\$(basename "\$1")"
    slug="\$(printf '%s' "\$base" | tr '[:upper:]' '[:lower:]' | tr -c 'a-z0-9_.-' '-' | sed 's/^-*//; s/-*\$//; s/--*/-/g')"
    [ -n "\$slug" ] || slug="project"
    printf '%.32s' "\$slug"
}

resolve_project_dir() {
    [ -n "\$PROJECT_DIR" ] || fail "project directory is empty"
    [ -d "\$PROJECT_DIR" ] || fail "project directory not found: \$PROJECT_DIR"
    (cd "\$PROJECT_DIR" && pwd -P)
}

prepare_project_runtime() {
    local project slug hash workspace_home runtime_dir
    project="\$(resolve_project_dir)"
    slug="\$(project_slug "\$project")"
    hash="\$(project_hash "\$project")"
    workspace_home="\${SHOGUNATE_WORKSPACE_HOME:-\$HOME/.shogunate/workspaces}"
    runtime_dir="\$workspace_home/\${slug}-\${hash}"
    mkdir -p "\$runtime_dir"
    if command -v rsync >/dev/null 2>&1; then
        rsync -a --delete \
            --exclude '/.git/' \
            --exclude '/.venv/' \
            --exclude '/config/settings.yaml' \
            --exclude '/config/projects.yaml' \
            --exclude '/logs/' \
            --exclude '/queue/' \
            "\$SHOGUNATE_INSTALL_DIR"/ "\$runtime_dir"/
    else
        (cd "\$SHOGUNATE_INSTALL_DIR" && tar \
            --exclude='./.git' \
            --exclude='./.venv' \
            --exclude='./config/settings.yaml' \
            --exclude='./config/projects.yaml' \
            --exclude='./logs' \
            --exclude='./queue' \
            -cf - .) | (cd "\$runtime_dir" && tar -xf -)
    fi
    mkdir -p "\$runtime_dir/config"
    if [ ! -f "\$runtime_dir/config/settings.yaml" ] && [ -f "\$SHOGUNATE_INSTALL_DIR/config/settings.yaml" ]; then
        cp "\$SHOGUNATE_INSTALL_DIR/config/settings.yaml" "\$runtime_dir/config/settings.yaml"
    fi
    if [ ! -f "\$runtime_dir/config/projects.yaml" ] && [ -f "\$SHOGUNATE_INSTALL_DIR/config/projects.yaml" ]; then
        cp "\$SHOGUNATE_INSTALL_DIR/config/projects.yaml" "\$runtime_dir/config/projects.yaml"
    fi
    if [ -d "\$SHOGUNATE_INSTALL_DIR/.venv" ] && [ ! -e "\$runtime_dir/.venv" ]; then
        ln -s "\$SHOGUNATE_INSTALL_DIR/.venv" "\$runtime_dir/.venv" 2>/dev/null || true
    fi
    mkdir -p "\$runtime_dir/queue/runtime"
    printf '%s\n' "\$project" > "\$runtime_dir/queue/runtime/target_project"
    printf '%s\n' "\$SHOGUNATE_INSTALL_DIR" > "\$runtime_dir/queue/runtime/engine_dir"
    printf '%s\n' "\$runtime_dir"
}

default_session_name() {
    local project slug hash
    project="\$(resolve_project_dir)"
    slug="\$(project_slug "\$project")"
    hash="\$(project_hash "\$project")"
    printf 'shogunate-%s-%s' "\$slug" "\$hash"
}

run_in_project_runtime() {
    local runtime_dir project session
    runtime_dir="\$(prepare_project_runtime)"
    project="\$(resolve_project_dir)"
    session="\${SHOGUNATE_SESSION_NAME:-\$(default_session_name)}"
    cd "\$runtime_dir"
    export SHOGUNATE_ENGINE_DIR="\$SHOGUNATE_INSTALL_DIR"
    export SHOGUNATE_PROJECT_DIR="\$project"
    export SHOGUNATE_WORKSPACE_DIR="\$runtime_dir"
    export SHOGUNATE_SESSION_NAME="\$session"
    export GOZA_SESSION_NAME="\${GOZA_SESSION_NAME:-\$session}"
    printf '%s\n' "\$SHOGUNATE_SESSION_NAME" > "\$runtime_dir/queue/runtime/session_name"
}

print_project_info() {
    local runtime_dir project session
    runtime_dir="\$(prepare_project_runtime)"
    project="\$(resolve_project_dir)"
    session="\${SHOGUNATE_SESSION_NAME:-\$(default_session_name)}"
    printf 'Shogunate project runtime\n'
    printf '  Project:  %s\n' "\$project"
    printf '  Runtime:  %s\n' "\$runtime_dir"
    printf '  Engine:   %s\n' "\$SHOGUNATE_INSTALL_DIR"
    printf '  Session:  %s\n' "\$session"
    printf '  Attach:   shogunate attach --project %q\n' "\$project"
}

if [ "\${1:-}" = "--project" ]; then
    [ "\${2:-}" ] || fail "--project requires a directory"
    PROJECT_DIR="\$2"
    shift 2
elif [[ "\${1:-}" == --project=* ]]; then
    PROJECT_DIR="\${1#--project=}"
    shift
fi

command_name="\${1:-run}"
case "\$command_name" in
    -h|--help|help)
        usage
        ;;
    run)
        shift || true
        parse_project_args "\$@"
        run_in_project_runtime
        exec ./Shogunate-Runtime.sh "\${RUNTIME_ARGS[@]}"
        ;;
    clean)
        shift || true
        parse_project_args "\$@"
        run_in_project_runtime
        exec ./Shogunate-Runtime.sh --clean "\${RUNTIME_ARGS[@]}"
        ;;
    resume)
        shift || true
        parse_project_args "\$@"
        run_in_project_runtime
        exec ./Shogunate-Runtime.sh --resume "\${RUNTIME_ARGS[@]}"
        ;;
    attach)
        shift || true
        parse_project_args "\$@"
        exec tmux attach -t "\${SHOGUNATE_SESSION_NAME:-\$(default_session_name)}" "\${RUNTIME_ARGS[@]}"
        ;;
    pair)
        shift || true
        parse_project_args "\$@"
        run_in_project_runtime
        exec python3 scripts/shogunate_pair_server.py --project-root "\$SHOGUNATE_WORKSPACE_DIR" --target-project "\$SHOGUNATE_PROJECT_DIR" "\${RUNTIME_ARGS[@]}"
        ;;
    configure)
        shift || true
        parse_project_args "\$@"
        run_in_project_runtime
        exec ./Shogunate-Configure-Roles.sh "\${RUNTIME_ARGS[@]}"
        ;;
    where)
        shift || true
        parse_project_args "\$@"
        print_project_info
        ;;
    status)
        shift || true
        cd "\$SHOGUNATE_INSTALL_DIR"
        exec python3 shogunate_mod/update/manager.py status "\$@"
        ;;
    aliases)
        shift || true
        parse_project_args "\$@"
        run_in_project_runtime
        printf 'source %q/scripts/shell_aliases.sh\n' "\$SHOGUNATE_WORKSPACE_DIR"
        ;;
    install)
        shift || true
        exec bash "\$SHOGUNATE_INSTALL_DIR/scripts/shogunate_package_bootstrap.sh" "\$@"
        ;;
    home)
        shift || true
        cd "\$SHOGUNATE_INSTALL_DIR"
        exec "\${SHELL:-bash}" -i
        ;;
    *)
        parse_project_args "\$@"
        run_in_project_runtime
        exec ./Shogunate-Runtime.sh "\${RUNTIME_ARGS[@]}"
        ;;
esac
EOF
    chmod +x "$BIN_DIR/shogunate"
    log "command installed: $BIN_DIR/shogunate"
fi

if [ "$RUN_SETUP" = "1" ]; then
    if [ -f "$PREFIX/shogunate_mod/package/first_setup.sh" ]; then
        log "run shogunate_mod/package/first_setup.sh"
        (cd "$PREFIX" && bash shogunate_mod/package/first_setup.sh)
    elif [ -f "$PREFIX/first_setup.sh" ]; then
        log "run first_setup.sh"
        (cd "$PREFIX" && bash first_setup.sh)
    else
        log "first_setup.sh not found; skipped"
    fi
fi

log "done"
log "run: shogunate"
