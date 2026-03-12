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
    run rg -n "goza_no_ma\\.sh|goza_mirror_pane\\.sh|goza_layout_autosave\\.sh|御座の間" "$PROJECT_ROOT/scripts/goza_no_ma.sh" "$PROJECT_ROOT/scripts/goza_mirror_pane.sh" "$PROJECT_ROOT/scripts/goza_layout_autosave.sh" "$PROJECT_ROOT/README.md" "$PROJECT_ROOT/shutsujin_departure.sh"
    [ "$status" -eq 0 ]
}

@test "軍師 attach alias csg と御座の間 alias cgo を案内する" {
    run rg -n "alias csg=|alias cgo='bash .*goza_no_ma\\.sh'|または: csg|cgo\\s+→" "$PROJECT_ROOT/first_setup.sh" "$PROJECT_ROOT/shutsujin_departure.sh"
    [ "$status" -eq 0 ]
}

@test "御座の間導線は既存backend再利用を優先する" {
    run rg -n "VIEW_ONLY=true|--ensure-backend|--refresh|既存の御座の間 session を再利用|既存 session だけで御座の間" "$PROJECT_ROOT/scripts/goza_no_ma.sh" "$PROJECT_ROOT/README.md" "$PROJECT_ROOT/README_ja.md"
    [ "$status" -eq 0 ]
}

@test "御座の間は将軍 > 家老 > 軍師 > 足軽の順で独立mirror paneを作る" {
    run rg -n "mirror_cmd .*shogun:main|mirror_cmd .*gunshi:main|discover_karo_target|discover_ashigaru_targets|split-window -h -l|split-window -v -l|show-options -p -t .*@agent_id" "$PROJECT_ROOT/scripts/goza_no_ma.sh"
    [ "$status" -eq 0 ]
}

@test "御座の間は手動リサイズ後の tmux window_layout を保存して次回復元する" {
    run rg -n "GOZA_LAYOUT_FILE|save_goza_layout|restore_goza_layout_if_available|start_goza_layout_autosave|goza_layout_autosave\\.sh|window_layout|select-layout -t .*saved_layout" "$PROJECT_ROOT/scripts/goza_no_ma.sh" "$PROJECT_ROOT/scripts/goza_layout_autosave.sh"
    [ "$status" -eq 0 ]
}

@test "agent収集は shutsujin_departure が topology_adapter を利用する" {
    run rg -n "topology_adapter\\.sh|topology_load_active_ashigaru|topology_resolve_karo_agents" "$PROJECT_ROOT/shutsujin_departure.sh"
    [ "$status" -eq 0 ]
}

@test "tmux bootstrap と watcher は multiagent pane を agent_id から解決する" {
    run rg -n "resolve_multiagent_pane_target|list-panes -t \"multiagent:agents\" -F .*pane_index|show-options -p -t .*@agent_id" \
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
