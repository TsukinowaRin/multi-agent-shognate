#!/usr/bin/env bash
# Shogunate MOD runtime daemon helpers.

build_tmux_runtime_daemon_command() {
    local inner_cmd="$1"
    local cmd=""
    printf -v cmd 'cd %q && %s' "$SCRIPT_DIR" "$inner_cmd"
    printf '%s\n' "$cmd"
}

runtime_bash_command() {
    local candidate
    if [ -n "${SHOGUNATE_BASH:-}" ] && [ -x "$SHOGUNATE_BASH" ]; then
        printf '%s\n' "$SHOGUNATE_BASH"
        return 0
    fi
    for candidate in /opt/homebrew/bin/bash /usr/local/bin/bash bash /bin/bash; do
        if command -v "$candidate" >/dev/null 2>&1; then
            command -v "$candidate"
            return 0
        fi
        if [ -x "$candidate" ]; then
            printf '%s\n' "$candidate"
            return 0
        fi
    done
    printf 'bash\n'
}

runtime_file_watch_available() {
    if command -v file_watch_backend_available >/dev/null 2>&1; then
        file_watch_backend_available
        return $?
    fi
    command -v inotifywait >/dev/null 2>&1 || command -v fswatch >/dev/null 2>&1
}

build_runtime_session_env_args() {
    local shogunate_session="${SHOGUNATE_SESSION_NAME:-${GOZA_SESSION_NAME:-shogunate}}"
    local goza_session="${GOZA_SESSION_NAME:-$shogunate_session}"
    local legacy_session="${LEGACY_GOZA_SESSION_NAME:-goza-no-ma}"
    local goza_window="${GOZA_WINDOW_NAME:-goza}"
    local env_args=""

    printf -v env_args \
        'SHOGUNATE_SESSION_NAME=%q GOZA_SESSION_NAME=%q LEGACY_GOZA_SESSION_NAME=%q GOZA_WINDOW_NAME=%q' \
        "$shogunate_session" "$goza_session" "$legacy_session" "$goza_window"
    printf '%s\n' "$env_args"
}

initialize_runtime_daemon_session() {
    if command -v shogunate_mod_runtime_daemon_session >/dev/null 2>&1; then
        RUNTIME_DAEMON_SESSION="${RUNTIME_DAEMON_SESSION:-$(shogunate_mod_runtime_daemon_session "${SHOGUNATE_SESSION_NAME:-shogunate}")}"
    else
        RUNTIME_DAEMON_SESSION="${RUNTIME_DAEMON_SESSION:-goza-runtime-${SHOGUNATE_SESSION_NAME:-shogunate}}"
    fi
}

tmux_kill_runtime_daemon_session_exact() {
    local session_name="$1"
    tmux kill-session -t "=$session_name" 2>/dev/null
}

start_tmux_runtime_daemon_window() {
    local session_name="$1"
    local window_name="$2"
    local inner_cmd="$3"
    local shell_cmd=""

    shell_cmd="$(build_tmux_runtime_daemon_command "$inner_cmd")"
    if tmux has-session -t "$session_name" 2>/dev/null; then
        tmux new-window -d -t "$session_name" -n "$window_name" "$shell_cmd" >/dev/null 2>&1
    else
        tmux new-session -d -s "$session_name" -n "$window_name" "$shell_cmd" >/dev/null 2>&1
    fi
}

tmux_runtime_daemon_window_exists() {
    local session_name="$1"
    local window_name="$2"

    tmux list-windows -t "$session_name" -F '#{window_name}' 2>/dev/null | grep -Fxq "$window_name"
}

ensure_tmux_runtime_daemon_window() {
    local session_name="$1"
    local window_name="$2"
    local inner_cmd="$3"

    if ! tmux_runtime_daemon_window_exists "$session_name" "$window_name"; then
        start_tmux_runtime_daemon_window "$session_name" "$window_name" "$inner_cmd"
    fi
}

ensure_gunkan_light_watch_daemon_started() {
    local session_name="${1:-$RUNTIME_DAEMON_SESSION}"

    [ -f "$SCRIPT_DIR/shogunate_mod/gunkan/light_watch.py" ] || return 0
    mkdir -p "$SCRIPT_DIR/logs" "$SCRIPT_DIR/queue/runtime"
    ensure_tmux_runtime_daemon_window \
        "$session_name" \
        "gunkan-watch" \
        "env MAS_GUNKAN_WATCH_INTERVAL=\"${MAS_GUNKAN_WATCH_INTERVAL:-20}\" MAS_GUNKAN_WATCH_COOLDOWN=\"${MAS_GUNKAN_WATCH_COOLDOWN:-300}\" python3 \"$SCRIPT_DIR/shogunate_mod/gunkan/light_watch.py\" --daemon >> \"$SCRIPT_DIR/logs/gunkan_light_watch.log\" 2>&1"
}

ensure_runtime_sync_daemon_started() {
    local session_name="${1:-$RUNTIME_DAEMON_SESSION}"

    [ -f "$SCRIPT_DIR/shogunate_mod/runtime/sync_state.py" ] || return 0
    mkdir -p "$SCRIPT_DIR/logs" "$SCRIPT_DIR/queue/runtime"
    ensure_tmux_runtime_daemon_window \
        "$session_name" \
        "runtime-sync" \
        "env MAS_RUNTIME_SYNC_INTERVAL=\"${MAS_RUNTIME_SYNC_INTERVAL:-5}\" python3 \"$SCRIPT_DIR/shogunate_mod/runtime/sync_state.py\" --daemon >> \"$SCRIPT_DIR/logs/runtime_sync.log\" 2>&1"
}

ensure_role_failover_daemon_started() {
    local session_name="${1:-$RUNTIME_DAEMON_SESSION}"
    local runner="$SCRIPT_DIR/shogunate_mod/runtime/role_failover_runner.sh"
    [ -f "$runner" ] || return 0
    mkdir -p "$SCRIPT_DIR/logs" "$SCRIPT_DIR/queue/runtime"
    ensure_tmux_runtime_daemon_window \
        "$session_name" \
        "role-failover" \
        "env SHOGUNATE_RUNTIME_DIR=\"$SCRIPT_DIR\" SHOGUNATE_NO_PROGRESS_INTERVAL_SECONDS=\"${SHOGUNATE_NO_PROGRESS_INTERVAL_SECONDS:-30}\" bash \"$runner\" daemon >> \"$SCRIPT_DIR/logs/role_failover.log\" 2>&1"
}

restart_tmux_runtime_daemon_session() {
    local session_name="${1:-$RUNTIME_DAEMON_SESSION}"
    local session_env=""
    local runtime_bash=""
    local started=0

    tmux_kill_runtime_daemon_session_exact "$session_name" || true
    session_env="$(build_runtime_session_env_args)"
    runtime_bash="$(runtime_bash_command)"

    if runtime_file_watch_available; then
        start_tmux_runtime_daemon_window \
            "$session_name" \
            "watcher" \
            "while true; do env $session_env WATCHER_SUPERVISOR_ONCE=1 WATCHER_RUNTIME_SESSION=\"$session_name\" MUX_TYPE=tmux \"$runtime_bash\" \"$SCRIPT_DIR/shogunate_mod/watcher/supervisor.sh\" >> \"$SCRIPT_DIR/logs/watcher_supervisor.log\" 2>&1 || true; sleep \"${WATCHER_SUPERVISOR_INTERVAL:-5}\"; done"
        started=1
    fi

    if [ -x "$SCRIPT_DIR/shogunate_mod/runtime/shogun_to_karo_bridge_daemon.sh" ]; then
        start_tmux_runtime_daemon_window \
            "$session_name" \
            "shogun-to-karo" \
            "env MAS_SHOGUN_TO_KARO_BRIDGE_INTERVAL=\"${MAS_SHOGUN_TO_KARO_BRIDGE_INTERVAL:-2}\" bash \"$SCRIPT_DIR/shogunate_mod/runtime/shogun_to_karo_bridge_daemon.sh\" >> \"$SCRIPT_DIR/logs/shogun_to_karo_bridge.log\" 2>&1"
        started=1
    fi

    if [ -x "$SCRIPT_DIR/shogunate_mod/runtime/karo_done_to_shogun_bridge_daemon.sh" ]; then
        start_tmux_runtime_daemon_window \
            "$session_name" \
            "karo-to-shogun" \
            "env MAS_KARO_DONE_TO_SHOGUN_INTERVAL=\"${MAS_KARO_DONE_TO_SHOGUN_INTERVAL:-2}\" bash \"$SCRIPT_DIR/shogunate_mod/runtime/karo_done_to_shogun_bridge_daemon.sh\" >> \"$SCRIPT_DIR/logs/karo_done_to_shogun_bridge.log\" 2>&1"
        started=1
    fi

    if [ -x "$SCRIPT_DIR/shogunate_mod/runtime/cli_pref_daemon.sh" ]; then
        start_tmux_runtime_daemon_window \
            "$session_name" \
            "runtime-pref" \
            "env MAS_RUNTIME_PREF_SYNC_INTERVAL=\"${MAS_RUNTIME_PREF_SYNC_INTERVAL:-1}\" MAS_RUNTIME_PREF_SYNC_LOG=\"$SCRIPT_DIR/logs/runtime_cli_pref_sync.log\" bash \"$SCRIPT_DIR/shogunate_mod/runtime/cli_pref_daemon.sh\" >> \"$SCRIPT_DIR/logs/runtime_cli_pref_sync.log\" 2>&1"
        started=1
    fi

    if [ -f "$SCRIPT_DIR/shogunate_mod/gunkan/light_watch.py" ]; then
        ensure_gunkan_light_watch_daemon_started "$session_name"
        started=1
    fi

    if [ -f "$SCRIPT_DIR/shogunate_mod/runtime/sync_state.py" ]; then
        ensure_runtime_sync_daemon_started "$session_name"
        started=1
    fi

    if [ -f "$SCRIPT_DIR/shogunate_mod/runtime/role_failover_runner.sh" ]; then
        ensure_role_failover_daemon_started "$session_name"
        started=1
    fi

    [ "$started" -eq 1 ]
}

ensure_runtime_daemons_for_bootstrap() {
    [ "$SETUP_ONLY" = false ] || return 0
    log_info "🛡️  bootstrap中断に備えて runtime daemon を先行起動中..."
    if restart_tmux_runtime_daemon_session "$RUNTIME_DAEMON_SESSION"; then
        log_success "  └─ runtime daemon 先行起動完了（tmux daemon session: ${RUNTIME_DAEMON_SESSION}）"
    else
        log_info "⚠️  runtime daemon 先行起動に失敗しました。bootstrap後に再試行します"
    fi
}

start_runtime_watchers_and_bridges() {
    local agent=""
    local runtime_bash=""
    local _watcher_total=0

    log_info "📬 メールボックス監視を起動中..."
    runtime_bash="$(runtime_bash_command)"

    mkdir -p "$SCRIPT_DIR/logs"
    for agent in shogun gunkan gunshi "${KARO_AGENTS[@]}" "${ACTIVE_ASHIGARU[@]}"; do
        [ -f "$SCRIPT_DIR/queue/inbox/${agent}.yaml" ] || echo "messages: []" > "$SCRIPT_DIR/queue/inbox/${agent}.yaml"
    done

    pkill -f "$SCRIPT_DIR/scripts/inbox_watcher.sh " 2>/dev/null || true
    pkill -f "$SCRIPT_DIR/shogunate_mod/watcher/inbox_watcher.sh " 2>/dev/null || true
    pkill -f "$SCRIPT_DIR/scripts/watcher_supervisor.sh" 2>/dev/null || true
    pkill -f "$SCRIPT_DIR/shogunate_mod/watcher/supervisor.sh" 2>/dev/null || true
    pkill -f "$SCRIPT_DIR/scripts/shogun_to_karo_bridge_daemon.sh" 2>/dev/null || true
    pkill -f "$SCRIPT_DIR/shogunate_mod/runtime/shogun_to_karo_bridge_daemon.sh" 2>/dev/null || true
    pkill -f "$SCRIPT_DIR/scripts/karo_done_to_shogun_bridge_daemon.sh" 2>/dev/null || true
    pkill -f "$SCRIPT_DIR/shogunate_mod/runtime/karo_done_to_shogun_bridge_daemon.sh" 2>/dev/null || true
    pkill -f "$SCRIPT_DIR/scripts/runtime_cli_pref_daemon.sh" 2>/dev/null || true
    pkill -f "$SCRIPT_DIR/shogunate_mod/runtime/cli_pref_daemon.sh" 2>/dev/null || true
    pkill -f "$SCRIPT_DIR/scripts/gunkan_light_watch.py" 2>/dev/null || true
    pkill -f "$SCRIPT_DIR/shogunate_mod/gunkan/light_watch.py" 2>/dev/null || true
    pkill -f "$SCRIPT_DIR/shogunate_mod/runtime/sync_state.py" 2>/dev/null || true
    tmux_kill_runtime_daemon_session_exact "$RUNTIME_DAEMON_SESSION" || true
    pkill -f "inotifywait.*${SCRIPT_DIR}/queue/inbox" 2>/dev/null || true
    pkill -f "fswatch.*${SCRIPT_DIR}/queue/inbox" 2>/dev/null || true
    sleep 1

    if runtime_file_watch_available; then
        env $(build_runtime_session_env_args) WATCHER_SUPERVISOR_ONCE=1 MUX_TYPE=tmux "$runtime_bash" "$SCRIPT_DIR/shogunate_mod/watcher/supervisor.sh" \
            >> "$SCRIPT_DIR/logs/watcher_supervisor.log" 2>&1 || true
        restart_tmux_runtime_daemon_session "$RUNTIME_DAEMON_SESSION" || true
        env $(build_runtime_session_env_args) WATCHER_SUPERVISOR_ONCE=1 WATCHER_RUNTIME_SESSION="$RUNTIME_DAEMON_SESSION" MUX_TYPE=tmux \
            "$runtime_bash" "$SCRIPT_DIR/shogunate_mod/watcher/supervisor.sh" \
            >> "$SCRIPT_DIR/logs/watcher_supervisor.log" 2>&1 || true
        if [ -x "$SCRIPT_DIR/shogunate_mod/runtime/cli_pref_daemon.sh" ]; then
            sleep 1
            ensure_tmux_runtime_daemon_window \
                "$RUNTIME_DAEMON_SESSION" \
                "runtime-pref" \
                "env MAS_RUNTIME_PREF_SYNC_INTERVAL=\"${MAS_RUNTIME_PREF_SYNC_INTERVAL:-1}\" MAS_RUNTIME_PREF_SYNC_LOG=\"$SCRIPT_DIR/logs/runtime_cli_pref_sync.log\" bash \"$SCRIPT_DIR/shogunate_mod/runtime/cli_pref_daemon.sh\" >> \"$SCRIPT_DIR/logs/runtime_cli_pref_sync.log\" 2>&1"
        fi
        if [ -f "$SCRIPT_DIR/shogunate_mod/gunkan/light_watch.py" ]; then
            ensure_tmux_runtime_daemon_window \
                "$RUNTIME_DAEMON_SESSION" \
                "gunkan-watch" \
                "env MAS_GUNKAN_WATCH_INTERVAL=\"${MAS_GUNKAN_WATCH_INTERVAL:-20}\" MAS_GUNKAN_WATCH_COOLDOWN=\"${MAS_GUNKAN_WATCH_COOLDOWN:-300}\" python3 \"$SCRIPT_DIR/shogunate_mod/gunkan/light_watch.py\" --daemon >> \"$SCRIPT_DIR/logs/gunkan_light_watch.log\" 2>&1"
        fi
        if [ -f "$SCRIPT_DIR/shogunate_mod/runtime/sync_state.py" ]; then
            ensure_runtime_sync_daemon_started "$RUNTIME_DAEMON_SESSION"
        fi
        ensure_role_failover_daemon_started "$RUNTIME_DAEMON_SESSION"
        _watcher_total=$((2 + ${#MULTIAGENT_IDS[@]}))
        log_success "  └─ ${_watcher_total}エージェント分のinbox_watcher起動完了"
        log_success "  └─ watcher_supervisor 起動完了（tmux daemon session: ${RUNTIME_DAEMON_SESSION}）"
    else
        log_info "⚠️  file watcher 未導入のため inbox_watcher はスキップ（macOS: brew install fswatch / Linux: sudo apt install -y inotify-tools）"
    fi

    if [ -x "$SCRIPT_DIR/shogunate_mod/runtime/shogun_to_karo_bridge_daemon.sh" ]; then
        log_info "📨 将軍→家老 命令ブリッジを起動中..."
        log_success "  └─ shogun_to_karo_bridge_daemon 起動完了（tmux daemon session）"
    fi

    if [ -x "$SCRIPT_DIR/shogunate_mod/runtime/karo_done_to_shogun_bridge_daemon.sh" ]; then
        log_info "📨 家老→将軍 完了報告ブリッジを起動中..."
        log_success "  └─ karo_done_to_shogun_bridge_daemon 起動完了（tmux daemon session）"
    fi

    if [ -x "$SCRIPT_DIR/shogunate_mod/runtime/cli_pref_daemon.sh" ]; then
        log_info "💾 live CLI設定の自動同期を起動中..."
        log_success "  └─ runtime_cli_pref_daemon 起動完了（tmux daemon session）"
    fi

    if [ -f "$SCRIPT_DIR/shogunate_mod/runtime/sync_state.py" ]; then
        log_info "🔄 runtime状態同期を起動中..."
        log_success "  └─ runtime_sync 起動完了（tmux daemon session）"
    fi
}
