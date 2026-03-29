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
