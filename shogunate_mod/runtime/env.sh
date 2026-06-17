#!/usr/bin/env bash
# Shared Shogunate MOD runtime helpers.

shogunate_mod_default_session_name() {
    printf '%s\n' "${SHOGUNATE_SESSION_NAME:-shogunate}"
}

shogunate_mod_default_goza_session_name() {
    local shogunate_session="${SHOGUNATE_SESSION_NAME:-${GOZA_SESSION_NAME:-shogunate}}"
    printf '%s\n' "${GOZA_SESSION_NAME:-$shogunate_session}"
}

shogunate_mod_runtime_daemon_session() {
    local shogunate_session="${1:-${SHOGUNATE_SESSION_NAME:-shogunate}}"
    printf 'goza-runtime-%s\n' "$shogunate_session"
}

shogunate_mod_resolve_project_dir() {
    local dir="$1"
    [ -n "$dir" ] || return 64
    [ -d "$dir" ] || return 66
    (cd "$dir" && pwd -P)
}

initialize_shogunate_project_dir() {
    SHOGUNATE_PROJECT_DIR="${SHOGUNATE_PROJECT_DIR:-$SCRIPT_DIR}"
    if command -v shogunate_mod_resolve_project_dir >/dev/null 2>&1; then
        RESOLVED_SHOGUNATE_PROJECT_DIR="$(shogunate_mod_resolve_project_dir "$SHOGUNATE_PROJECT_DIR" 2>/dev/null || true)"
        if [ -n "$RESOLVED_SHOGUNATE_PROJECT_DIR" ]; then
            SHOGUNATE_PROJECT_DIR="$RESOLVED_SHOGUNATE_PROJECT_DIR"
        else
            echo "[WARN] SHOGUNATE_PROJECT_DIR が見つかりません: $SHOGUNATE_PROJECT_DIR" >&2
            SHOGUNATE_PROJECT_DIR="$SCRIPT_DIR"
        fi
        unset RESOLVED_SHOGUNATE_PROJECT_DIR
    elif [ -d "$SHOGUNATE_PROJECT_DIR" ]; then
        SHOGUNATE_PROJECT_DIR="$(cd "$SHOGUNATE_PROJECT_DIR" && pwd -P)"
    else
        echo "[WARN] SHOGUNATE_PROJECT_DIR が見つかりません: $SHOGUNATE_PROJECT_DIR" >&2
        SHOGUNATE_PROJECT_DIR="$SCRIPT_DIR"
    fi
}

initialize_goza_runtime_vars() {
    SHOGUNATE_SESSION_NAME="${SHOGUNATE_SESSION_NAME:-shogunate}"
    LEGACY_GOZA_SESSION_NAME="${LEGACY_GOZA_SESSION_NAME:-goza-no-ma}"
    GOZA_SESSION_NAME="${GOZA_SESSION_NAME:-$SHOGUNATE_SESSION_NAME}"
    GOZA_WINDOW_NAME="${GOZA_WINDOW_NAME:-goza}"
    GOZA_STARTUP_WINDOW_NAME="${GOZA_STARTUP_WINDOW_NAME:-startup}"
    log_info "Target project: $SHOGUNATE_PROJECT_DIR"
    log_info "Runtime root: $SCRIPT_DIR"
    log_info "tmux session: $GOZA_SESSION_NAME"
    GOZA_LAYOUT_FILE="${GOZA_LAYOUT_FILE:-$SCRIPT_DIR/queue/runtime/goza_layout.tsv}"
    GOZA_SIGNATURE_FILE="${GOZA_SIGNATURE_FILE:-$SCRIPT_DIR/queue/runtime/goza_signature.tsv}"
    GOZA_BOOTSTRAP_RUN_ID="${GOZA_BOOTSTRAP_RUN_ID:-$(date +%Y%m%d_%H%M%S)}"
    GOZA_BOOTSTRAP_LOG="${GOZA_BOOTSTRAP_LOG:-$SCRIPT_DIR/queue/runtime/goza_bootstrap_${GOZA_BOOTSTRAP_RUN_ID}.log}"
    GOZA_VIEW_WIDTH="${GOZA_VIEW_WIDTH:-220}"
    GOZA_VIEW_HEIGHT="${GOZA_VIEW_HEIGHT:-60}"
    GOZA_MIN_RESTORE_PANE_WIDTH="${GOZA_MIN_RESTORE_PANE_WIDTH:-20}"
    GOZA_MIN_RESTORE_PANE_HEIGHT="${GOZA_MIN_RESTORE_PANE_HEIGHT:-6}"
}

shogunate_mod_shell_aliases_path() {
    local runtime_root="$1"
    printf '%s/scripts/shell_aliases.sh\n' "$runtime_root"
}
