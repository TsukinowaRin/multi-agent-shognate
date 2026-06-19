#!/usr/bin/env bash

run_shutsujin_departure() {
    initialize_shogunate_project_dir
    initialize_runtime_daemon_session

    ensure_tmux_tmpdir
    acquire_startup_lock

    load_runtime_language_shell_settings
    detect_early_help_request "$@"
    select_runtime_python_or_die

    if [ -f "$SCRIPT_DIR/shogunate_mod/cli/adapter.sh" ]; then
        # shellcheck source=/dev/null
        source "$SCRIPT_DIR/shogunate_mod/cli/adapter.sh"
        CLI_ADAPTER_LOADED=true
    else
        CLI_ADAPTER_LOADED=false
    fi

    TOPOLOGY_ADAPTER_LOADED=false
    if [ -f "$SCRIPT_DIR/shogunate_mod/topology/adapter.sh" ]; then
        # shellcheck source=/dev/null
        source "$SCRIPT_DIR/shogunate_mod/topology/adapter.sh"
        TOPOLOGY_ADAPTER_LOADED=true
    fi

    if [ -f "$SCRIPT_DIR/shogunate_mod/inbox/path.sh" ]; then
        # shellcheck source=/dev/null
        source "$SCRIPT_DIR/shogunate_mod/inbox/path.sh"
    fi

    run_pending_update_request "$@"
    run_startup_update_check "$@"

    initialize_goza_runtime_vars
    parse_runtime_options "$@"

    ensure_generated_instructions
    sync_opencode_like_workspace_settings
    initialize_runtime_topology

    show_battle_cry

    echo -e "  \033[1;33m天下布武！陣立てを開始いたす\033[0m (Setting up the battlefield)"
    echo ""

    cleanup_existing_runtime_sessions
    backup_previous_records_if_clean
    ensure_runtime_queue_dirs
    reset_or_keep_runtime_queue
    write_runtime_coordination_state
    initialize_dashboard_if_clean

    if ! command -v tmux &> /dev/null; then
        echo ""
        echo "  ╔════════════════════════════════════════════════════════╗"
        echo "  ║  [ERROR] tmux not found!                              ║"
        echo "  ║  tmux が見つかりません                                 ║"
        echo "  ╠════════════════════════════════════════════════════════╣"
        echo "  ║  Run first_setup.sh first:                            ║"
        echo "  ║  まず first_setup.sh を実行してください:               ║"
        echo "  ║     ./first_setup.sh                                  ║"
        echo "  ╚════════════════════════════════════════════════════════╝"
        echo ""
        exit 1
    fi

    create_goza_runtime_session

    initialize_runtime_cli_metadata
    start_pre_cli_runtime_watchers

    if [ "$SETUP_ONLY" = false ]; then
        launch_all_agent_clis_tmux

        log_war "📜 各エージェントに指示書を読み込ませ中..."
        echo ""

        show_startup_bootstrap_banner
        run_startup_bootstrap_delivery_flow
        start_runtime_watchers_and_bridges
        run_post_bootstrap_runtime_tasks
    fi

    update_current_bootstrap_pending_count
    start_ntfy_listener_if_configured
    show_departure_completion_summary
    open_windows_terminal_tabs_if_requested
}
