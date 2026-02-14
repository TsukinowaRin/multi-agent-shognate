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
