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

@test "zellij起動は inbox 正規化ヘルパーを利用する" {
    run rg -n "inbox_path\\.sh" "$PROJECT_ROOT/scripts/shutsujin_zellij.sh"
    [ "$status" -eq 0 ]
    run rg -n "ensure_local_inbox_dir" "$PROJECT_ROOT/scripts/shutsujin_zellij.sh"
    [ "$status" -eq 0 ]
}

@test "goza起動も inbox 正規化ヘルパーを利用する" {
    run rg -n "inbox_path\\.sh" "$PROJECT_ROOT/scripts/goza_no_ma.sh"
    [ "$status" -eq 0 ]
    run rg -n "ensure_local_inbox_dir" "$PROJECT_ROOT/scripts/goza_no_ma.sh"
    [ "$status" -eq 0 ]
}

@test "gozaのagent収集はtopology_adapterを利用できる" {
    run rg -n "topology_adapter\\.sh|topology_load_active_ashigaru|topology_resolve_karo_agents" "$PROJECT_ROOT/scripts/goza_no_ma.sh"
    [ "$status" -eq 0 ]
}

@test "gozaの役職判定は複数家老IDに対応" {
    run rg -n "karo\\|karo\\[1-9\\]\\*\\|karo_gashira" "$PROJECT_ROOT/scripts/goza_no_ma.sh"
    [ "$status" -eq 0 ]
}

@test "tmux/zellij ともに ntfy_inbox.yaml を確保する" {
    run rg -n "ntfy_inbox\\.yaml" "$PROJECT_ROOT/shutsujin_departure.sh"
    [ "$status" -eq 0 ]
    run rg -n "ntfy_inbox\\.yaml" "$PROJECT_ROOT/scripts/shutsujin_zellij.sh"
    [ "$status" -eq 0 ]
}
