#!/usr/bin/env bats

setup_file() {
    export PROJECT_ROOT
    PROJECT_ROOT="$(cd "$(dirname "$BATS_TEST_FILENAME")/../.." && pwd)"
}

@test "pure zellij: 各ペインでTTY自律注入を使う" {
    run rg -nF 'tty_path="$(tty)"' "$PROJECT_ROOT/scripts/goza_no_ma.sh"
    [ "$status" -eq 0 ]
    run rg -nF 'bootstrap_file=' "$PROJECT_ROOT/scripts/goza_no_ma.sh"
    [ "$status" -eq 0 ]
    run rg -nF 'printf "%%s\\r" "$_line" >"$tty_path"' "$PROJECT_ROOT/scripts/goza_no_ma.sh"
    [ "$status" -eq 0 ]
}

@test "pure zellij: goza_attachでフォーカス移動注入を呼ばない" {
    run rg -nF 'zellij_bootstrap_pure_goza_background "$ZELLIJ_UI_SESSION"' "$PROJECT_ROOT/scripts/goza_no_ma.sh"
    [ "$status" -ne 0 ]
}

@test "pure zellij: command pane の Waiting to run を Enter で自動解除する" {
    run rg -nF 'zellij_resume_pure_goza_panes_background' "$PROJECT_ROOT/scripts/goza_no_ma.sh"
    [ "$status" -eq 0 ]
    run rg -nF 'action write 13' "$PROJECT_ROOT/scripts/goza_no_ma.sh"
    [ "$status" -eq 0 ]
}

@test "pure zellij: attachブロッキング前にresume予約を行う" {
    run rg -nF 'zellij_schedule_resume_after_attach "$ZELLIJ_UI_SESSION"' "$PROJECT_ROOT/scripts/goza_no_ma.sh"
    [ "$status" -eq 0 ]
}
