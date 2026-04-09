#!/usr/bin/env bats

source "$BATS_TEST_DIRNAME/../helpers/search_helper.bash"

setup_file() {
    export PROJECT_ROOT
    PROJECT_ROOT="$(cd "$(dirname "$BATS_TEST_FILENAME")/../.." && pwd)"
}

@test "tmux起動は inbox 正規化ヘルパーを利用する" {
    run bats_search "inbox_path\.sh|ensure_local_inbox_dir" "$PROJECT_ROOT/shutsujin_departure.sh"
    [ "$status" -eq 0 ]
}

@test "tmux起動は TMUX_TMPDIR が指定されていれば事前に作成する" {
    run bats_search 'ensure_tmux_tmpdir|mkdir -p "\$tmux_tmp"|chmod 700 "\$tmux_tmp"|TMUX_TMPDIR' "$PROJECT_ROOT/shutsujin_departure.sh"
    [ "$status" -eq 0 ]
}

@test "tmux起動入口は lock dir による二重起動ガードを持つ" {
    run bats_search 'acquire_startup_lock|mkdir "\$lock_dir"|shutsujin\.lock\.d|kill -0 "\$holder_pid"|別の shutsujin_departure\.sh が実行中' "$PROJECT_ROOT/shutsujin_departure.sh"
    [ "$status" -eq 0 ]
}

@test "tmux起動入口は shutsujin_departure.sh のみを使う" {
    run bats_search "Usage:|./shutsujin_departure\.sh|tmux attach-session|cgo" "$PROJECT_ROOT/shutsujin_departure.sh" "$PROJECT_ROOT/README.md"
    [ "$status" -eq 0 ]
}

@test "現役 scripts から zellij 導線が外れている" {
    run bats_search "shutsujin_zellij|zellij action|--mux zellij|--ui zellij" "$PROJECT_ROOT/scripts" "$PROJECT_ROOT/README.md" "$PROJECT_ROOT/first_setup.sh" "$PROJECT_ROOT/config/settings.yaml" "$PROJECT_ROOT/shutsujin_departure.sh"
    [ "$status" -ne 0 ]
}

@test "御座の間スクリプトと focus helper が現役で存在する" {
    run bats_search "goza_no_ma\.sh|focus_agent_pane\.sh|御座の間" "$PROJECT_ROOT/scripts/goza_no_ma.sh" "$PROJECT_ROOT/scripts/focus_agent_pane.sh" "$PROJECT_ROOT/README.md" "$PROJECT_ROOT/shutsujin_departure.sh"
    [ "$status" -eq 0 ]
}

@test "軍師 attach alias csg と御座の間 alias cgo を案内する" {
    run bats_search "shell_aliases\.sh|install_shell_aliases\.sh|alias csg='bash .*focus_agent_pane\.sh gunshi'|alias cgo='bash .*goza_no_ma\.sh'|または: csg|cgo" "$PROJECT_ROOT/scripts/shell_aliases.sh" "$PROJECT_ROOT/first_setup.sh" "$PROJECT_ROOT/shutsujin_departure.sh"
    [ "$status" -eq 0 ]
}

@test "御座の間は本体 session として構築する" {
    run bats_search 'GOZA_SESSION_NAME|new-session -d -x .* -s "\$GOZA_SESSION_NAME"|pane-border-format|build_ashigaru_grid|restore_goza_layout_if_available|start_goza_layout_autosave' "$PROJECT_ROOT/shutsujin_departure.sh"
    [ "$status" -eq 0 ]
}

@test "goza helper は goza-no-ma へ直接 attach/switch する" {
    run bats_search 'GOZA_SESSION|switch-client -t "\$GOZA_SESSION"|attach-session -t "\$GOZA_SESSION"|shutsujin_departure\.sh' "$PROJECT_ROOT/scripts/goza_no_ma.sh"
    [ "$status" -eq 0 ]
}

@test "Android 互換 session は proxy 経由で shogun gunshi multiagent を提供する" {
    run bats_search 'android_tmux_proxy\.py|new-session -d -s shogun -n main|new-session -d -s gunshi -n main|new-session -d -s multiagent -n agents|set-option -p -t shogun:main @agent_id|set-option -p -t gunshi:main @agent_id|multiagent:agents' "$PROJECT_ROOT/shutsujin_departure.sh" "$PROJECT_ROOT/scripts/android_tmux_proxy.py"
    [ "$status" -eq 0 ]
}

@test "focus helper は goza 本体 pane へ移動する" {
    run bats_search 'GOZA_SESSION|show-options -p -t .*@agent_id|list-panes -t "\$\{GOZA_SESSION\}:\$\{GOZA_WINDOW\}"|select-window -t|select-pane -t' "$PROJECT_ROOT/scripts/focus_agent_pane.sh"
    [ "$status" -eq 0 ]
}

@test "watcher supervisor は goza 本体を正本に pane 解決する" {
    run bats_search 'has-session -t "goza-no-ma"|list-panes -s -t "goza-no-ma"|show-options -p -t .*@agent_id|ASW_PROCESS_TIMEOUT=1' "$PROJECT_ROOT/scripts/watcher_supervisor.sh"
    [ "$status" -eq 0 ]
}

@test "tmux 起動と watcher supervisor は clone 横断しない絶対pathで daemon を管理する" {
    run bats_search '\$SCRIPT_DIR/scripts/inbox_watcher\.sh |\$SCRIPT_DIR/scripts/watcher_supervisor\.sh|\$SCRIPT_DIR/scripts/shogun_to_karo_bridge_daemon\.sh|\$SCRIPT_DIR/scripts/karo_done_to_shogun_bridge_daemon\.sh|inotifywait\.\*\$\{SCRIPT_DIR\}/queue/inbox|\$SCRIPT_DIR/scripts/ntfy_listener\.sh|\$SCRIPT_DIR/scripts/goza_layout_autosave\.sh' "$PROJECT_ROOT/shutsujin_departure.sh" "$PROJECT_ROOT/scripts/watcher_supervisor.sh"
    [ "$status" -eq 0 ]
}

@test "runtime 同期は goza 本体を優先し Android 互換 target は fallback とする" {
    run bats_search 'has-session", "-t", "goza-no-ma"|list-panes", "-s", "-t", "goza-no-ma"|shogun:main|gunshi:main|multiagent:agents' "$PROJECT_ROOT/scripts/sync_runtime_cli_preferences.py"
    [ "$status" -eq 0 ]
}

@test "agent収集は shutsujin_departure が topology_adapter を利用する" {
    run bats_search "topology_adapter\.sh|topology_load_active_ashigaru|topology_resolve_karo_agents" "$PROJECT_ROOT/shutsujin_departure.sh"
    [ "$status" -eq 0 ]
}

@test "tmux 起動は ntfy_inbox.yaml を確保する" {
    run bats_search "ntfy_inbox\.yaml" "$PROJECT_ROOT/shutsujin_departure.sh"
    [ "$status" -eq 0 ]
}

@test "tmux clean start は shogun_to_karo の active queue を空に戻す" {
    run bats_search 'queue/shogun_to_karo\.yaml|commands: \[\]|pending cmd を再通知' "$PROJECT_ROOT/shutsujin_departure.sh"
    [ "$status" -eq 0 ]
}

@test "tmux clean start は bridge state を消して archive 側の旧完了を再配送させない" {
    run bats_search 'queue/runtime/shogun_to_karo_bridge\.tsv|queue/runtime/karo_done_to_shogun\.tsv|archive 側の旧 done を再配送させない' "$PROJECT_ROOT/shutsujin_departure.sh"
    [ "$status" -eq 0 ]
}

@test "tmux 起動は bootstrap 配信結果と auth-required を runtime log へ残す" {
    run bats_search 'GOZA_BOOTSTRAP_LOG|goza_bootstrap_\$\{GOZA_BOOTSTRAP_RUN_ID\}\.log|status=auth-required|status=bootstrap-delivered' "$PROJECT_ROOT/shutsujin_departure.sh"
    [ "$status" -eq 0 ]
}

@test "tmux 起動は prompt自動処理と bootstrap 配信で text+Enter の両方を確認する" {
    run bats_search 'tmux_send_text_and_enter|bootstrap-send-failed|Codex update prompt: Enter send failed|Codex workspace trust prompt|Codex rate-limit prompt|Gemini trust prompt' "$PROJECT_ROOT/shutsujin_departure.sh"
    [ "$status" -eq 0 ]
}

@test "tmux 起動は pane shell prep と CLI launch でも text+Enter を厳密確認する" {
    run bats_search 'tmux_send_text_and_enter_or_die|pane shell prep|shogun CLI launch|gunshi CLI launch|CLI launch' "$PROJECT_ROOT/shutsujin_departure.sh"
    [ "$status" -eq 0 ]
}

@test "tmux 起動は bootstrap 未配信でも全体を abort しない" {
    run bats_search 'if ! deliver_bootstrap_tmux .*_bootstrap_failed=1|bootstrap 未配信のまま継続' "$PROJECT_ROOT/shutsujin_departure.sh"
    [ "$status" -eq 0 ]
}

@test "tmux 起動は bootstrap pending marker を作り、auth 後の watcher 再配信を前提にする" {
    run bats_search 'pending_file=.*bootstrap_|deliver_pending_bootstrap_if_ready|watcher が bootstrap を再試行' "$PROJECT_ROOT/shutsujin_departure.sh" "$PROJECT_ROOT/scripts/inbox_watcher.sh"
    [ "$status" -eq 0 ]
}

@test "tmux 起動は watcher が先に配信した bootstrap を二重送信しない" {
    run bats_search 'if \[ ! -f "\$pending_file" \ ]; then|already-delivered|pending cleared before startup delivery|pending cleared during startup wait' "$PROJECT_ROOT/shutsujin_departure.sh"
    [ "$status" -eq 0 ]
}

@test "tmux 起動は Codex bootstrap 後に pasted content が残っていたら追い Enter する" {
    run bats_search 'codex_pasted_content_pending_tmux|confirm_codex_pasted_content_tmux|pasted content still pending|Confirming Codex pasted content' "$PROJECT_ROOT/shutsujin_departure.sh" "$PROJECT_ROOT/scripts/inbox_watcher.sh"
    [ "$status" -eq 0 ]
}

@test "tmux 起動は Codex workspace trust prompt を update prompt と分離して自動承認する" {
    run bats_search 'auto_accept_codex_workspace_trust_prompt_tmux|Do you trust the contents of this directory|1\\. Yes, continue|Would you like to update' "$PROJECT_ROOT/shutsujin_departure.sh"
    [ "$status" -eq 0 ]
}

@test "tmux 起動は役職別の初動最適化 directive を bootstrap に含める" {
    run bats_search 'startup_fastpath_directive|初動最適化: 起動直後は自inboxだけ確認|repo 名で即 cmd 起票|report YAML を正本として|cmd close を最優先|bridge/ntfy/streaks/sample は異常時以外読むな|自inbox/task だけ確認' "$PROJECT_ROOT/shutsujin_departure.sh"
    [ "$status" -eq 0 ]
}

@test "tmux 起動は generated instruction を正本として読み比べ diff を要求しない" {
    run bats_search '正本指示として即適用せよ|比較・diff・読み比べは不要' "$PROJECT_ROOT/shutsujin_departure.sh"
    [ "$status" -eq 0 ]
    [[ "$output" != *'差分を適用せよ'* ]]
}

@test "tmux 起動は Codex の rate-limit prompt も自動dismissする" {
    run bats_search "auto_dismiss_codex_rate_limit_prompt_tmux|Approaching rate limits|You've hit your usage limit|Keep current model \\(never show again\\)|gpt-5\\.1-codex-mini|hard usage-limit prompt|mini へ自動切替" "$PROJECT_ROOT/shutsujin_departure.sh"
    [ "$status" -eq 0 ]
}

@test "tmux 起動と watcher は折返し usage-limit prompt を compact 判定で拾う" {
    run bats_search 'codex_prompt_compact_text|codex_usage_limit_prompt_detected|codex_usage_limit_switchable|codex_prompt_compact_text_tmux|codex_usage_limit_prompt_detected_tmux|codex_usage_limit_switchable_tmux' "$PROJECT_ROOT/scripts/inbox_watcher.sh" "$PROJECT_ROOT/shutsujin_departure.sh"
    [ "$status" -eq 0 ]
}

@test "tmux 起動と watcher は Codex 起動コマンド行を ready と誤認しない" {
    run bats_search 'codex_ready_prompt_detected|codex_ready_prompt_detected_tmux|/model to change|ready-pending|watcher retry will deliver' "$PROJECT_ROOT/scripts/inbox_watcher.sh" "$PROJECT_ROOT/shutsujin_departure.sh"
    [ "$status" -eq 0 ]
}

@test "tmux 起動は Codex bootstrap の ready 待機を短くして watcher 再試行へ渡す" {
    run bats_search 'MAS_CODEX_BOOTSTRAP_READY_WAIT|ready_wait=30|ready_wait="\$\{MAS_CODEX_BOOTSTRAP_READY_WAIT:-5\}"|watcher retry will deliver' "$PROJECT_ROOT/shutsujin_departure.sh"
    [ "$status" -eq 0 ]
}

@test "tmux 起動は hard usage-limit を dashboard blocked notice に記録する" {
    run bats_search 'record_runtime_blocker_notice_tmux|runtime_blocker_notice\.py|codex-hard-usage-limit|dashboard に記録' "$PROJECT_ROOT/shutsujin_departure.sh"
    [ "$status" -eq 0 ]
}

@test "tmux 起動は hard usage-limit 解消後に dashboard blocked notice を除去する" {
    run bats_search 'clear_runtime_blocker_notice_tmux|--action "\$action"|dashboard から除去|codex-hard-usage-limit' "$PROJECT_ROOT/shutsujin_departure.sh"
    [ "$status" -eq 0 ]
}

@test "tmux 起動は Codex auth-required を dashboard blocked notice に記録して除去する" {
    run bats_search 'record_runtime_blocker_notice_tmux|clear_runtime_blocker_notice_tmux|codex-auth-required|dashboard に記録|dashboard から除去|Login server error: Login cancelled|failed to start login server' "$PROJECT_ROOT/shutsujin_departure.sh"
    [ "$status" -eq 0 ]
}

@test "tmux 起動は runtime blocked を shogun inbox へ relay する" {
    run bats_search 'notify_shogun_runtime_blocked_tmux|runtime_blocked_relay_marker_path_tmux|runtime_blocked|startup_guard|dashboard\.md の runtime-blocked/' "$PROJECT_ROOT/shutsujin_departure.sh"
    [ "$status" -eq 0 ]
}

@test "tmux 起動は Codex process が node でない間は bootstrap を保留する" {
    run bats_search 'codex_process_running_tmux|pane_current_command|cli-not-running|Keeping bootstrap pending' "$PROJECT_ROOT/shutsujin_departure.sh"
    [ "$status" -eq 0 ]
}

@test "watcher は shell に戻った Codex pane を restart command で再起動する" {
    run bats_search 'recover_shell_returned_codex_if_needed|LAST_CLI_RESTART_TS|CLI_STARTUP_GRACE_SECONDS|@cli_launch_epoch|Codex CLI restart|restarted shell-returned Codex pane' "$PROJECT_ROOT/scripts/inbox_watcher.sh" "$PROJECT_ROOT/scripts/watcher_supervisor.sh"
    [ "$status" -eq 0 ]
}

@test "tmux 起動は CLI launch 時刻を記録し、起動直後の shell-return recovery を抑止する" {
    run bats_search 'mark_cli_launch_attempt_tmux|@cli_launch_epoch|CLI_STARTUP_GRACE_SECONDS|runtime_start_epoch|RUNTIME_STARTUP_RECOVERY_GRACE_SECONDS' "$PROJECT_ROOT/shutsujin_departure.sh" "$PROJECT_ROOT/scripts/inbox_watcher.sh" "$PROJECT_ROOT/scripts/watcher_supervisor.sh"
    [ "$status" -eq 0 ]
}

@test "tmux 起動は watcher_supervisor を one-shot 初期tickしてから常駐化する" {
    run bats_search 'WATCHER_SUPERVISOR_ONCE=1|watcher_supervisor\.sh' "$PROJECT_ROOT/shutsujin_departure.sh"
    [ "$status" -eq 0 ]
}

@test "tmux 起動は daemon session 起動後にも watcher one-shot seed を再実行する" {
    run bats_search 'restart_tmux_runtime_daemon_session|WATCHER_RUNTIME_SESSION="\$RUNTIME_DAEMON_SESSION"|WATCHER_SUPERVISOR_ONCE=1' "$PROJECT_ROOT/shutsujin_departure.sh"
    [ "$status" -eq 0 ]
}

@test "tmux watcher daemon window は one-shot tick を5秒ごとに回す" {
    run bats_search 'while true; do env WATCHER_SUPERVISOR_ONCE=1|WATCHER_SUPERVISOR_INTERVAL' "$PROJECT_ROOT/shutsujin_departure.sh"
    [ "$status" -eq 0 ]
}

@test "tmux 起動は switch-only Codex confirm prompt を Enter で確定する" {
    run bats_search 'codex_switch_confirm_prompt_detected_tmux|Codex switch-confirm prompt|tmux_send_enter_only' "$PROJECT_ROOT/shutsujin_departure.sh"
    [ "$status" -eq 0 ]
}

@test "tmux 起動は折返しされた Codex Keep current model prompt も compact 判定で dismiss する" {
    run bats_search 'codex_rate_limit_prompt_detected_tmux|codex_prompt_compact_text_tmux|hidefutureratelimit|keepcurrentmodel' "$PROJECT_ROOT/shutsujin_departure.sh"
    [ "$status" -eq 0 ]
}

@test "tmux 起動の event_driven_directive は backtick を command substitution しない" {
    run env PROJECT_ROOT="$PROJECT_ROOT" bash -lc '
        eval "$(sed -n "/^event_driven_directive() {/,/^}/p" "$PROJECT_ROOT/shutsujin_departure.sh")"
        out="$(event_driven_directive shogun)"
        [[ "$out" == *"`cmd_done`"* ]]
    '
    [ "$status" -eq 0 ]
}

@test "tmux 起動は runtime daemon を tmux session で常駐化する" {
    run bats_search 'RUNTIME_DAEMON_SESSION|restart_tmux_runtime_daemon_session|start_tmux_runtime_daemon_window|ensure_tmux_runtime_daemon_window|tmux new-session -d -s "\$session_name"|tmux new-window -d -t "\$session_name"|tmux kill-session -t "\$RUNTIME_DAEMON_SESSION"' "$PROJECT_ROOT/shutsujin_departure.sh"
    [ "$status" -eq 0 ]
}

@test "tmux 起動は runtime_cli_pref_daemon を起動後に自己killしない" {
    run rg -n 'pkill -f "\$SCRIPT_DIR/scripts/runtime_cli_pref_daemon.sh"|log_info "💾 live CLI設定の自動同期を起動中..."' "$PROJECT_ROOT/shutsujin_departure.sh"
    [ "$status" -eq 0 ]
    [[ "$output" == *'pkill -f "$SCRIPT_DIR/scripts/runtime_cli_pref_daemon.sh"'* ]]
    [[ "$output" == *'log_info "💾 live CLI設定の自動同期を起動中..."'* ]]
    [[ "$output" != *$'log_info "💾 live CLI設定の自動同期を起動中..."\n        pkill -f "$SCRIPT_DIR/scripts/runtime_cli_pref_daemon.sh" 2>/dev/null || true'* ]]
}

@test "tmux 起動は runtime-pref window 欠落時に ensure で再補充する" {
    run bats_search 'ensure_tmux_runtime_daemon_window|runtime-pref|MAS_RUNTIME_PREF_SYNC_INTERVAL|sleep 1' "$PROJECT_ROOT/shutsujin_departure.sh"
    [ "$status" -eq 0 ]
}

@test "tmux 起動は watcher/bridge/runtime sync を nohup 常駐へ戻さない" {
    run bats_search 'nohup env MUX_TYPE=tmux bash "\$SCRIPT_DIR/scripts/watcher_supervisor\.sh"|nohup env MAS_SHOGUN_TO_KARO_BRIDGE_INTERVAL|nohup env MAS_KARO_DONE_TO_SHOGUN_INTERVAL|nohup env MAS_RUNTIME_PREF_SYNC_INTERVAL' "$PROJECT_ROOT/shutsujin_departure.sh"
    [ "$status" -ne 0 ]
}

@test "watcher supervisor は inbox watcher も tmux window で常駐化する" {
    run bats_search 'WATCHER_RUNTIME_SESSION|watcher_window_name|tmux new-window -d -t "\$WATCHER_RUNTIME_SESSION"' "$PROJECT_ROOT/scripts/watcher_supervisor.sh"
    [ "$status" -eq 0 ]
}
