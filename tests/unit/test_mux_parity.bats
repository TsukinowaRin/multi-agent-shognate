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
    run rg -n "goza_no_ma\\.sh|御座の間" "$PROJECT_ROOT/scripts/goza_no_ma.sh" "$PROJECT_ROOT/README.md" "$PROJECT_ROOT/shutsujin_departure.sh"
    [ "$status" -eq 0 ]
}

@test "軍師 attach alias csg と御座の間 alias cgo を案内する" {
    run rg -n "alias csg=|alias cgo='bash .*goza_no_ma\\.sh --view-only'|または: csg|cgo\\s+→.*--view-only" "$PROJECT_ROOT/first_setup.sh" "$PROJECT_ROOT/shutsujin_departure.sh"
    [ "$status" -eq 0 ]
}

@test "御座の間導線は既存backend再利用を優先する" {
    run rg -n "goza_no_ma\\.sh --view-only|backend session が不足しているため" "$PROJECT_ROOT/scripts/goza_no_ma.sh" "$PROJECT_ROOT/README.md" "$PROJECT_ROOT/README_ja.md"
    [ "$status" -eq 0 ]
}

@test "agent収集は shutsujin_departure が topology_adapter を利用する" {
    run rg -n "topology_adapter\\.sh|topology_load_active_ashigaru|topology_resolve_karo_agents" "$PROJECT_ROOT/shutsujin_departure.sh"
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
