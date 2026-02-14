#!/usr/bin/env bats

setup_file() {
    export PROJECT_ROOT
    PROJECT_ROOT="$(cd "$(dirname "$BATS_TEST_FILENAME")/../.." && pwd)"
    export SCRIPT
    SCRIPT="$PROJECT_ROOT/scripts/mux_parity_smoke.sh"
}

@test "mux_parity_smoke: --dry-run で tmux/zellij 両コマンドを表示する" {
    run bash "$SCRIPT" --dry-run
    [ "$status" -eq 0 ]
    [[ "$output" =~ "MAS_MULTIPLEXER=tmux bash shutsujin_departure.sh -s" ]]
    [[ "$output" =~ "MAS_MULTIPLEXER=zellij bash shutsujin_departure.sh -s" ]]
}

@test "mux_parity_smoke: --tmux-only --dry-run は tmux のみ表示する" {
    run bash "$SCRIPT" --tmux-only --dry-run
    [ "$status" -eq 0 ]
    [[ "$output" =~ "MAS_MULTIPLEXER=tmux bash shutsujin_departure.sh -s" ]]
    [[ ! "$output" =~ "MAS_MULTIPLEXER=zellij bash shutsujin_departure.sh -s" ]]
}
