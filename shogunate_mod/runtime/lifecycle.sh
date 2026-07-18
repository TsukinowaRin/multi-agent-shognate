#!/usr/bin/env bash
initialize_runtime_cli_metadata() {
    local _agent=""

    mkdir -p "$SCRIPT_DIR/queue/runtime"
    : > "$SCRIPT_DIR/queue/runtime/agent_cli.tsv"
    for _agent in "${BACKEND_AGENT_IDS[@]}"; do
        _emit_runtime_cli_entry "$_agent"
    done
    create_android_compat_sessions
}

start_pre_cli_runtime_watchers() {
    [ "$SETUP_ONLY" = false ] || return 0

    ensure_gunkan_light_watch_daemon_started "$RUNTIME_DAEMON_SESSION" || true
    log_success "  └─ 軍監軽量監査 watcher 先行起動完了（tmux daemon session: ${RUNTIME_DAEMON_SESSION}）"
}

update_current_bootstrap_pending_count() {
    local _agent=""

    CURRENT_BOOTSTRAP_PENDING_COUNT=0
    if [ "$SETUP_ONLY" = false ]; then
        for _agent in shogun gunkan gunshi "${MULTIAGENT_IDS[@]}"; do
            [ -f "$SCRIPT_DIR/queue/runtime/bootstrap_${_agent}.pending" ] || continue
            CURRENT_BOOTSTRAP_PENDING_COUNT=$((CURRENT_BOOTSTRAP_PENDING_COUNT + 1))
        done
    fi
}

start_ntfy_listener_if_configured() {
    local ntfy_topic=""

    ntfy_topic=$(grep 'ntfy_topic:' ./config/settings.yaml 2>/dev/null | awk '{print $2}' | tr -d '"' || true)
    if [ -n "$ntfy_topic" ]; then
        pkill -f "$SCRIPT_DIR/scripts/ntfy_listener.sh" 2>/dev/null || true
        pkill -f "$SCRIPT_DIR/shogunate_mod/notify/listener.sh" 2>/dev/null || true
        [ ! -f ./queue/ntfy_inbox.yaml ] && echo "inbox:" > ./queue/ntfy_inbox.yaml
        nohup bash "$SCRIPT_DIR/shogunate_mod/notify/listener.sh" 9>&- &>/dev/null &
        disown
        log_info "📱 ntfy入力リスナー起動 (topic: $ntfy_topic)"
    else
        log_info "📱 ntfy未設定のためリスナーはスキップ"
    fi
    echo ""
}

run_post_bootstrap_runtime_tasks() {
    log_info "📜 指示書読み込みは各エージェントが自律実行（CLAUDE.md Session Start）"
    if [ -x "$SCRIPT_DIR/shogunate_mod/queue/history_book.sh" ]; then
        bash "$SCRIPT_DIR/shogunate_mod/queue/history_book.sh" >/dev/null 2>&1 || true
    fi
    create_android_compat_sessions
    if is_android_compat_enabled; then
        log_success "  └─ Android 互換 session を更新完了"
    fi
    notify_pending_merge_candidates

    if [ -x "$SCRIPT_DIR/shogunate_mod/runtime/mcp_health_check.sh" ]; then
        log_info "🔎 MCP ヘルスチェックを実行中..."
        if bash "$SCRIPT_DIR/shogunate_mod/runtime/mcp_health_check.sh" 2>&1 | tee -a "$SCRIPT_DIR/logs/mcp_health.log" >/dev/null; then
            log_success "  └─ MCP ヘルスチェック完了"
        else
            log_error "  └─ ⚠️ MCP 初期化失敗を検知。logs/mcp_health.log を確認してください"
        fi
    fi
    echo ""
}
