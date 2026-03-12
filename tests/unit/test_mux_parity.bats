#!/usr/bin/env bats

setup_file() {
    export PROJECT_ROOT
    PROJECT_ROOT="$(cd "$(dirname "$BATS_TEST_FILENAME")/../.." && pwd)"
}

@test "tmux起動は inbox 正規化ヘルパーを利用する" {
    run rg -n "inbox_path\\.sh" "$PROJECT_ROOT/shutsujin_departure.sh"
    [ "$status" -eq 0 ]
    run rg -n "ensure_local_inbox_dir" "$PROJECT_ROOT/shutsujin_departure.sh"
    [ "$status" -eq 0 ]
}

@test "tmux起動入口は shutsujin_departure.sh のみを使う" {
    run rg -n "Usage:|./shutsujin_departure\\.sh|tmux attach-session" "$PROJECT_ROOT/shutsujin_departure.sh" "$PROJECT_ROOT/README.md"
    [ "$status" -eq 0 ]
}

@test "現役 scripts から zellij 導線が外れている" {
    run rg -n "shutsujin_zellij|zellij action|--mux zellij|--ui zellij" "$PROJECT_ROOT/scripts" "$PROJECT_ROOT/README.md" "$PROJECT_ROOT/first_setup.sh" "$PROJECT_ROOT/config/settings.yaml" "$PROJECT_ROOT/shutsujin_departure.sh"
    [ "$status" -ne 0 ]
}

@test "御座の間スクリプトが現役で存在する" {
    run rg -n "goza_no_ma\\.sh|goza_layout_autosave\\.sh|focus_agent_pane\\.sh|御座の間" "$PROJECT_ROOT/scripts/goza_no_ma.sh" "$PROJECT_ROOT/scripts/goza_layout_autosave.sh" "$PROJECT_ROOT/scripts/focus_agent_pane.sh" "$PROJECT_ROOT/README.md" "$PROJECT_ROOT/shutsujin_departure.sh"
    [ "$status" -eq 0 ]
}

@test "軍師 attach alias csg と御座の間 alias cgo を案内する" {
    run rg -n "alias csg='bash .*focus_agent_pane\\.sh gunshi'|alias cgo='bash .*goza_no_ma\\.sh'|または: csg|cgo\\s+→" "$PROJECT_ROOT/first_setup.sh" "$PROJECT_ROOT/shutsujin_departure.sh"
    [ "$status" -eq 0 ]
}

@test "御座の間導線は既存backend再利用を優先する" {
    run rg -n -- "--ensure-backend|--refresh|switch-client -t|attach-session -t \\$GOZA_SESSION|attach-session -t \\$GOZA_SESSION_NAME|focus_agent_pane" "$PROJECT_ROOT/scripts/goza_no_ma.sh" "$PROJECT_ROOT/README.md" "$PROJECT_ROOT/README_ja.md" "$PROJECT_ROOT/first_setup.sh"
    [ "$status" -eq 0 ]
}

@test "出陣本体は御座の間 session に実 pane を構築する" {
    run rg -n "GOZA_SESSION_NAME|GOZA_WINDOW_NAME|new-session -d -x .* -s .*goza-no-ma|split-window -h -l|split-window -v -l|AGENT_PANES|restore_goza_layout_if_available|start_goza_layout_autosave" "$PROJECT_ROOT/shutsujin_departure.sh"
    [ "$status" -eq 0 ]
}

@test "focus helper で御座の間内の agent pane へ移動できる" {
    run rg -n "focus_agent_pane\\.sh|switch-client -t|attach-session -t \\$SESSION|show-options -p -t .*@agent_id" \
      "$PROJECT_ROOT/scripts/focus_agent_pane.sh" "$PROJECT_ROOT/first_setup.sh" "$PROJECT_ROOT/shutsujin_departure.sh"
    [ "$status" -eq 0 ]
}

@test "御座の間は手動リサイズ後の tmux window_layout を保存して次回復元する" {
    run rg -n "GOZA_LAYOUT_FILE|save_goza_layout|restore_goza_layout_if_available|start_goza_layout_autosave|goza_layout_autosave\\.sh|window_layout|select-layout -t .*saved_layout" "$PROJECT_ROOT/shutsujin_departure.sh" "$PROJECT_ROOT/scripts/goza_layout_autosave.sh"
    [ "$status" -eq 0 ]
}

@test "agent収集は shutsujin_departure が topology_adapter を利用する" {
    run rg -n "topology_adapter\\.sh|topology_load_active_ashigaru|topology_resolve_karo_agents" "$PROJECT_ROOT/shutsujin_departure.sh"
    [ "$status" -eq 0 ]
}

@test "tmux bootstrap と watcher は backend pane を agent_id から解決する" {
    run rg -n "resolve_agent_pane_target|list_backend_pane_targets|show-options -p -t .*@agent_id" \
        "$PROJECT_ROOT/shutsujin_departure.sh" "$PROJECT_ROOT/scripts/watcher_supervisor.sh"
    [ "$status" -eq 0 ]
}

@test "役職判定は複数家老IDに対応" {
    run rg -n "karo\\|karo\\[1-9\\]\\*\\|karo_gashira" "$PROJECT_ROOT/shutsujin_departure.sh"
    [ "$status" -eq 0 ]
}

@test "tmux 起動は ntfy_inbox.yaml を確保する" {
    run rg -n "ntfy_inbox\\.yaml" "$PROJECT_ROOT/shutsujin_departure.sh"
    [ "$status" -eq 0 ]
}
