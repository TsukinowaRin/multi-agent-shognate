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

@test "旧 zellij ラッパーは tmux 本体へ委譲する" {
    run rg -n "goza_tmux\\.sh|shutsujin_departure\\.sh" \
        "$PROJECT_ROOT/scripts/goza_zellij.sh" \
        "$PROJECT_ROOT/scripts/goza_zellij_pure.sh" \
        "$PROJECT_ROOT/scripts/goza_hybrid.sh" \
        "$PROJECT_ROOT/scripts/shutsujin_zellij.sh"
    [ "$status" -eq 0 ]
}

@test "goza起動は tmux フロントエンドとして起動する" {
    run rg -n "MAS_MULTIPLEXER=tmux|tmux attach|tmux new-session" "$PROJECT_ROOT/scripts/goza_no_ma.sh"
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
