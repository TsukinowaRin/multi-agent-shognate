#!/usr/bin/env bash
# Shared helpers for thin Shogunate runtime launchers.

shogunate_launcher_source_env() {
    local env_file="$SCRIPT_DIR/shogunate_mod/runtime/env.sh"
    [ -f "$env_file" ] && source "$env_file"
}

shogunate_launcher_init_colors() {
    if [[ -t 1 && -z "${NO_COLOR:-}" ]]; then
        C_RESET=$'\033[0m'
        C_BOLD=$'\033[1m'
        C_CYAN=$'\033[1;36m'
        C_YELLOW=$'\033[1;33m'
        C_GREEN=$'\033[1;32m'
        C_RED=$'\033[1;31m'
    else
        C_RESET=""
        C_BOLD=""
        C_CYAN=""
        C_YELLOW=""
        C_GREEN=""
        C_RED=""
    fi
}

info() { printf '  %s[INFO]%s %s\n' "$C_YELLOW" "$C_RESET" "$*"; }
ok() { printf '  %s[OK]%s %s\n' "$C_GREEN" "$C_RESET" "$*"; }
err() { printf '  %s[ERROR]%s %s\n' "$C_RED" "$C_RESET" "$*" >&2; }

shogunate_launcher_init_context() {
    local caller_dir="${1:-$(pwd -P)}"
    shogunate_launcher_source_env
    shogunate_launcher_init_colors
    if declare -F shogunate_mod_default_session_name >/dev/null 2>&1; then
        SHOGUNATE_SESSION_NAME="$(shogunate_mod_default_session_name)"
    else
        SHOGUNATE_SESSION_NAME="${SHOGUNATE_SESSION_NAME:-shogunate}"
    fi
    SHOGUNATE_PROJECT_DIR="${SHOGUNATE_PROJECT_DIR:-$caller_dir}"
}

shogunate_launcher_resolve_project_dir() {
    local dir="$1"
    local resolved=""
    if declare -F shogunate_mod_resolve_project_dir >/dev/null 2>&1; then
        resolved="$(shogunate_mod_resolve_project_dir "$dir")" || {
            err "Project directory not found: $dir"
            exit 64
        }
        printf '%s\n' "$resolved"
        return 0
    fi
    [[ -n "$dir" ]] || {
        err "--project must not be empty"
        exit 64
    }
    [[ -d "$dir" ]] || {
        err "Project directory not found: $dir"
        exit 64
    }
    (cd "$dir" && pwd -P)
}

shogunate_launcher_require_departure() {
    if [[ ! -f "shutsujin_departure.sh" ]]; then
        err "shutsujin_departure.sh not found."
        echo "          Run this launcher from the Shogunate folder." >&2
        exit 1
    fi
}

shogunate_launcher_require_tmux() {
    if ! command -v tmux >/dev/null 2>&1; then
        err "tmux is not installed or not on PATH."
        exit 1
    fi
}
