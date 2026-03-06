#!/usr/bin/env bats

setup_file() {
    export PROJECT_ROOT
    PROJECT_ROOT="$(cd "$(dirname "$BATS_TEST_FILENAME")/../.." && pwd)"
}

@test "pure zellij: 各ペインは transcript を取りつつ明示送信でブートストラップ注入する" {
    # TTY直書き方式（旧実装）は使わない
    run rg -nF 'tty_path="$(tty)"' "$PROJECT_ROOT/scripts/goza_no_ma.sh"
    [ "$status" -ne 0 ]
    run rg -nF 'printf "%%s\\r" "$_line" >"$tty_path"' "$PROJECT_ROOT/scripts/goza_no_ma.sh"
    [ "$status" -ne 0 ]
    # CLI は先に起動し、script transcript に記録したうえで send-line 注入する
    run rg -nF 'goza_agent_transcript_file' "$PROJECT_ROOT/scripts/goza_no_ma.sh"
    [ "$status" -eq 0 ]
    run rg -nF 'script -qefc' "$PROJECT_ROOT/scripts/goza_no_ma.sh"
    [ "$status" -eq 0 ]
    run rg -nF 'bootstrap delivered agent=$agent cli=$cli_type mode=send-line' "$PROJECT_ROOT/scripts/goza_no_ma.sh"
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

@test "pure zellij: run-id付き bootstrap ログを出力する" {
    run rg -n "GOZA_BOOTSTRAP_LOG|goza_bootstrap_\$\{GOZA_BOOTSTRAP_RUN_ID\}" "$PROJECT_ROOT/scripts/goza_no_ma.sh"
    [ "$status" -eq 0 ]
    run rg -nF 'goza_bootstrap_log "run start' "$PROJECT_ROOT/scripts/goza_no_ma.sh"
    [ "$status" -eq 0 ]
}

@test "pure zellij: ready ACK(ready:agent) を確認し未検出時は再送する" {
    run rg -n "zellij_wait_ready_ack_current_pane|ready:\$\{agent\}|goza_agent_transcript_file" "$PROJECT_ROOT/scripts/goza_no_ma.sh"
    [ "$status" -eq 0 ]
    run rg -nF 'ready ack missing first_try agent=$agent' "$PROJECT_ROOT/scripts/goza_no_ma.sh"
    [ "$status" -eq 0 ]
    run rg -nF 'bootstrap retry sent agent=$agent' "$PROJECT_ROOT/scripts/goza_no_ma.sh"
    [ "$status" -eq 0 ]
}

@test "pure zellij: Gemini preflight の trust/high-demand を transcript ベースで処理する" {
    run rg -n "zellij_handle_gemini_preflight_current_pane|gemini trust accepted|gemini keep_trying" "$PROJECT_ROOT/scripts/goza_no_ma.sh"
    [ "$status" -eq 0 ]
}
