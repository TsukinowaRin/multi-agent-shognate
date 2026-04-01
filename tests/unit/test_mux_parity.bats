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
    run bats_search "alias csg='bash .*focus_agent_pane\.sh gunshi'|alias cgo='bash .*goza_no_ma\.sh'|または: csg|cgo" "$PROJECT_ROOT/first_setup.sh" "$PROJECT_ROOT/shutsujin_departure.sh"
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

@test "tmux 起動は bootstrap 配信結果と auth-required を runtime log へ残す" {
    run bats_search 'GOZA_BOOTSTRAP_LOG|goza_bootstrap_\$\{GOZA_BOOTSTRAP_RUN_ID\}\.log|status=auth-required|status=bootstrap-delivered' "$PROJECT_ROOT/shutsujin_departure.sh"
    [ "$status" -eq 0 ]
}

@test "tmux 起動は bootstrap 未配信でも全体を abort しない" {
    run bats_search 'if ! deliver_bootstrap_tmux .*_bootstrap_failed=1|bootstrap 未配信のまま継続' "$PROJECT_ROOT/shutsujin_departure.sh"
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

@test "tmux 起動は Codex の rate-limit prompt も自動dismissする" {
    run bats_search "auto_dismiss_codex_rate_limit_prompt_tmux|Approaching rate limits|You've hit your usage limit|Keep current model \\(never show again\\)|mini へ自動切替" "$PROJECT_ROOT/shutsujin_departure.sh"
    [ "$status" -eq 0 ]
}
