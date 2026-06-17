show_departure_completion_summary() {
    local _agent=""

    log_info "🔍 陣容を確認中..."
    echo ""
    echo "  ┌──────────────────────────────────────────────────────────┐"
    echo "  │  📺 Tmux陣容 (Sessions)                                  │"
    echo "  └──────────────────────────────────────────────────────────┘"
    tmux list-sessions | sed 's/^/     /'
    echo ""
    echo "  ┌──────────────────────────────────────────────────────────┐"
    echo "  │  📋 布陣図 (Formation)                                   │"
    echo "  └──────────────────────────────────────────────────────────┘"
    echo ""
    echo "     【${GOZA_SESSION_NAME}:${GOZA_WINDOW_NAME}】御座の間 view"
    echo "     ┌────────────────────────────────────────────────────────────┐"
    echo "     │  Pane: shogun          ← 総大将・プロジェクト統括        │"
    echo "     │  Pane: gunkan          ← 独立監査・戦況記録              │"
    for _agent in "${KARO_AGENTS[@]}"; do
        if [ "$_agent" = "$LEAD_KARO" ]; then
            echo "     │  Pane: ${_agent}  ← 筆頭家老・統合/将軍報告             │"
        else
            echo "     │  Pane: ${_agent}  ← 家老・担当足軽統制                 │"
        fi
    done
    echo "     │  Pane: gunshi          ← 戦略・分析・助言                │"
    for _agent in "${ACTIVE_ASHIGARU[@]}"; do
        echo "     │  Pane: ${_agent}  ← 足軽                                 │"
    done
    echo "     └────────────────────────────────────────────────────────────┘"
    echo ""
    if is_android_compat_enabled; then
        echo "     【Android 互換 session】補助レイヤ"
        echo "     ┌────────────────────────────────────────────────────────────┐"
        echo "     │  shogun:main   ← 将軍 proxy                               │"
        echo "     │  gunkan:main   ← 軍監 proxy                               │"
        echo "     │  gunshi:main   ← 軍師 proxy                               │"
        echo "     │  multiagent:0  ← 家老・足軽 proxy                         │"
        echo "     └────────────────────────────────────────────────────────────┘"
        echo ""
    fi

    echo ""
    echo "  ╔══════════════════════════════════════════════════════════╗"
    echo "  ║  🏯 出陣準備完了！天下布武！                              ║"
    echo "  ╚══════════════════════════════════════════════════════════╝"
    echo ""

    if [ "$SETUP_ONLY" = true ]; then
        echo "  ⚠️  セットアップのみモード: CLIは未起動です"
        echo ""
        echo "  手動でCLIを起動するには:"
        echo "  ┌──────────────────────────────────────────────────────────┐"
        echo "  │  # 将軍を召喚                                            │"
        echo "  │  tmux send-keys -t ${SHOGUN_TARGET:-shogun:main} \\                         │"
        echo "  │    '$(build_cli_command_with_type "shogun" "${_shogun_cli_type:-$(resolve_cli_type_for_agent "shogun" 2>/dev/null || echo claude)}")' Enter  │"
        echo "  │                                                          │"
        echo "  │  # 軍師を召喚                                            │"
        echo "  │  tmux send-keys -t ${GUNSHI_TARGET:-gunshi:main} \\                         │"
        echo "  │    '$(build_cli_command_with_type "gunshi" "${_gunshi_cli_type:-$(resolve_cli_type_for_agent "gunshi" 2>/dev/null || echo claude)}")' Enter  │"
        echo "  │                                                          │"
        echo "  │  # 軍監を召喚                                            │"
        echo "  │  tmux send-keys -t ${GUNKAN_TARGET:-gunkan:main} \\                         │"
        echo "  │    '$(build_cli_command_with_type "gunkan" "${_gunkan_cli_type:-$(resolve_cli_type_for_agent "gunkan" 2>/dev/null || echo claude)}")' Enter  │"
        echo "  │                                                          │"
        echo "  │  # 家老・足軽は ${GOZA_SESSION_NAME}:${GOZA_WINDOW_NAME} pane 側で起動      │"
        echo "  │  cat queue/runtime/agent_cli.tsv                         │"
        echo "  └──────────────────────────────────────────────────────────┘"
        echo ""
    fi

    echo "  次のステップ:"
    echo "  ┌──────────────────────────────────────────────────────────┐"
    echo "  │  御座の間へアタッチして命令を開始:                        │"
    echo "  │     tmux attach-session -t ${GOZA_SESSION_NAME}                  │"
    echo "  │                                                          │"
    echo "  │  将軍 pane へ移動:                                        │"
    echo "  │     bash scripts/focus_agent_pane.sh shogun   (または: css) │"
    echo "  │                                                          │"
    echo "  │  軍師 pane へ移動:                                        │"
    echo "  │     bash scripts/focus_agent_pane.sh gunshi   (または: csg) │"
    echo "  │                                                          │"
    echo "  │  軍監 pane へ移動:                                        │"
    echo "  │     bash scripts/focus_agent_pane.sh gunkan   (または: cgn) │"
    echo "  │                                                          │"
    echo "  │  家老 pane へ移動:                                        │"
    echo "  │     bash scripts/focus_agent_pane.sh karo   (または: csm) │"
    echo "  │                                                          │"
    echo "  │  俯瞰ビューを開く:                                        │"
    echo "  │     bash scripts/goza_no_ma.sh            (または: cgo)  │"
    echo "  │                                                          │"
    echo "  │  alias が古い時の即時修復:                                │"
    echo "  │     source scripts/shell_aliases.sh                       │"
    echo "  │     永続化: bash scripts/install_shell_aliases.sh         │"
    echo "  │                                                          │"
    if is_android_compat_enabled; then
        echo "  │  Android アプリ互換の補助 session:                        │"
        echo "  │     shogun:main / gunkan:main / gunshi:main / multiagent:0│"
        echo "  │                                                          │"
    fi
    if [ "$SETUP_ONLY" = false ] && [ "${CURRENT_BOOTSTRAP_PENDING_COUNT:-0}" -gt 0 ]; then
        echo "  │  ※ 一部エージェントは認証待ちで初動命令が未配信です。     │"
        echo "  │    ログイン完了後は watcher が bootstrap を再試行します。 │"
    else
        echo "  │  ※ 各エージェントは指示書を読み込み済み。                 │"
        echo "  │    すぐに命令を開始できます。                             │"
    fi
    echo "  └──────────────────────────────────────────────────────────┘"
    echo ""
    finish_goza_startup_window
    echo "  ════════════════════════════════════════════════════════════"
    echo "   天下布武！勝利を掴め！ (Tenka Fubu! Seize victory!)"
    echo "  ════════════════════════════════════════════════════════════"
    echo ""
}

open_windows_terminal_tabs_if_requested() {
    [ "$OPEN_TERMINAL" = true ] || return 0

    log_info "📺 Windows Terminal でタブを展開中..."

    if command -v wt.exe &> /dev/null; then
        wt.exe -w 0 new-tab wsl.exe -e bash -c "tmux attach-session -t ${GOZA_SESSION_NAME}" \; new-tab wsl.exe -e bash -c "bash scripts/focus_agent_pane.sh shogun" \; new-tab wsl.exe -e bash -c "bash scripts/focus_agent_pane.sh gunkan" \; new-tab wsl.exe -e bash -c "bash scripts/focus_agent_pane.sh gunshi"
        log_success "  └─ ターミナルタブ展開完了"
    else
        log_info "  └─ wt.exe が見つかりません。手動でアタッチしてください。"
    fi
    echo ""
}
