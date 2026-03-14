#!/usr/bin/env bats

setup_file() {
    export PROJECT_ROOT
    PROJECT_ROOT="$(cd "$(dirname "$BATS_TEST_FILENAME")/../.." && pwd)"
}

@test "tmux起動は inbox 正規化ヘルパーを利用する" {
    run rg -n "inbox_path\.sh|ensure_local_inbox_dir" "$PROJECT_ROOT/shutsujin_departure.sh"
    [ "$status" -eq 0 ]
}

@test "tmux起動入口は shutsujin_departure.sh のみを使う" {
    run rg -n "Usage:|./shutsujin_departure\.sh|tmux attach-session" "$PROJECT_ROOT/shutsujin_departure.sh" "$PROJECT_ROOT/README.md"
    [ "$status" -eq 0 ]
}

@test "現役 scripts から zellij 導線が外れている" {
    run rg -n "shutsujin_zellij|zellij action|--mux zellij|--ui zellij" "$PROJECT_ROOT/scripts" "$PROJECT_ROOT/README.md" "$PROJECT_ROOT/first_setup.sh" "$PROJECT_ROOT/config/settings.yaml" "$PROJECT_ROOT/shutsujin_departure.sh"
    [ "$status" -ne 0 ]
}

@test "御座の間スクリプトと focus helper が現役で存在する" {
    run rg -n "goza_no_ma\.sh|focus_agent_pane\.sh|御座の間" "$PROJECT_ROOT/scripts/goza_no_ma.sh" "$PROJECT_ROOT/scripts/focus_agent_pane.sh" "$PROJECT_ROOT/README.md" "$PROJECT_ROOT/shutsujin_departure.sh"
    [ "$status" -eq 0 ]
}

@test "軍師 attach alias csg と御座の間 alias cgo を案内する" {
    run rg -n "alias csg='bash .*focus_agent_pane\.sh gunshi'|alias cgo='bash .*goza_no_ma\.sh'|または: csg|cgo" "$PROJECT_ROOT/first_setup.sh" "$PROJECT_ROOT/shutsujin_departure.sh"
    [ "$status" -eq 0 ]
}

@test "御座の間は split runtime を俯瞰する view session として構築する" {
    run rg -n "attach-session -t shogun|attach-session -t multiagent|attach-session -t gunshi|main-vertical|main-pane-width" "$PROJECT_ROOT/scripts/goza_no_ma.sh"
    [ "$status" -eq 0 ]
}

@test "出陣本体は Android 互換の split session を構築する" {
    run rg -n "new-session -d -s shogun -n main|new-session -d -s gunshi -n main|new-session -d -s multiagent -n \"agents\"|multiagent:agents|shogun:main|gunshi:main" "$PROJECT_ROOT/shutsujin_departure.sh"
    [ "$status" -eq 0 ]
}

@test "multiagent pane には agent_id と model_name を付与する" {
    run rg -n "set-option -p -t \"multiagent:agents\.\$\{p\}\" @agent_id|set-option -p -t \"multiagent:agents\.\$\{p\}\" @model_name|pane-border-format" "$PROJECT_ROOT/shutsujin_departure.sh"
    [ "$status" -eq 0 ]
}

@test "focus helper は split session の実 pane へ移動する" {
    run rg -n "attach-session -t shogun|attach-session -t gunshi|attach-session -t multiagent|list-panes -t multiagent:agents|show-options -p -t .*@agent_id" "$PROJECT_ROOT/scripts/focus_agent_pane.sh"
    [ "$status" -eq 0 ]
}

@test "watcher supervisor は split session を正本に pane 解決する" {
    run rg -n "has-session -t \"shogun\"|has-session -t \"gunshi\"|has-session -t \"multiagent\"|list-panes -t \"multiagent:agents\"|show-options -p -t .*@agent_id|ASW_PROCESS_TIMEOUT=1" "$PROJECT_ROOT/scripts/watcher_supervisor.sh"
    [ "$status" -eq 0 ]
}

@test "runtime 同期は split session を優先し Android 互換 target を読める" {
    run rg -n "shogun:main|gunshi:main|multiagent:agents|goza-no-ma" "$PROJECT_ROOT/scripts/sync_runtime_cli_preferences.py"
    [ "$status" -eq 0 ]
}

@test "agent収集は shutsujin_departure が topology_adapter を利用する" {
    run rg -n "topology_adapter\.sh|topology_load_active_ashigaru|topology_resolve_karo_agents" "$PROJECT_ROOT/shutsujin_departure.sh"
    [ "$status" -eq 0 ]
}

@test "tmux 起動は ntfy_inbox.yaml を確保する" {
    run rg -n "ntfy_inbox\.yaml" "$PROJECT_ROOT/shutsujin_departure.sh"
    [ "$status" -eq 0 ]
}
