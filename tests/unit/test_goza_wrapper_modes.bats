#!/usr/bin/env bats

setup_file() {
    export PROJECT_ROOT
    PROJECT_ROOT="$(cd "$(dirname "$BATS_TEST_FILENAME")/../.." && pwd)"
}

@test "goza_zellij は安定版として zellij UI + tmux backend を呼ぶ" {
    run rg -nF -- '--mux tmux --ui zellij' "$PROJECT_ROOT/scripts/goza_zellij.sh"
    [ "$status" -eq 0 ]
}

@test "goza_zellij_pure は純正 zellij 経路を明示コマンドで残す" {
    run rg -nF -- '--mux zellij --ui zellij' "$PROJECT_ROOT/scripts/goza_zellij_pure.sh"
    [ "$status" -eq 0 ]
    run rg -nF 'MAS_ENABLE_PURE_ZELLIJ=1' "$PROJECT_ROOT/scripts/goza_zellij_pure.sh"
    [ "$status" -eq 0 ]
}

@test "goza_no_ma は明示opt-inなしでは pure zellij goza_room を stable 側へフォールバックする" {
    run rg -nF 'PURE_ZELLIJ_REQUESTED=0' "$PROJECT_ROOT/scripts/goza_no_ma.sh"
    [ "$status" -eq 0 ]
    run rg -nF 'MAS_ENABLE_PURE_ZELLIJ' "$PROJECT_ROOT/scripts/goza_no_ma.sh"
    [ "$status" -eq 0 ]
    run rg -nF 'zellij UI + tmux backend へフォールバック' "$PROJECT_ROOT/scripts/goza_no_ma.sh"
    [ "$status" -eq 0 ]
}
