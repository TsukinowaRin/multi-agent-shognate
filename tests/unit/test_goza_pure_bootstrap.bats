#!/usr/bin/env bats

setup_file() {
    export PROJECT_ROOT
    PROJECT_ROOT="$(cd "$(dirname "$BATS_TEST_FILENAME")/../.." && pwd)"
}

@test "pure zellij: 各ペインは dedicated runner と bootstrap file で自律起動する" {
    run rg -nF 'prepare_pure_zellij_bootstrap_files' "$PROJECT_ROOT/scripts/goza_no_ma.sh"
    [ "$status" -eq 0 ]
    run rg -nF 'goza_agent_bootstrap_file' "$PROJECT_ROOT/scripts/goza_no_ma.sh"
    [ "$status" -eq 0 ]
    run rg -nF 'scripts/zellij_agent_bootstrap.sh' "$PROJECT_ROOT/scripts/goza_no_ma.sh"
    [ "$status" -eq 0 ]
    run rg -nF 'build_cli_command_with_startup_prompt' "$PROJECT_ROOT/scripts/zellij_agent_bootstrap.sh"
    [ "$status" -eq 0 ]
}

@test "pure zellij: goza_attachでフォーカス巡回resumeを呼ばない" {
    run rg -nF 'zellij_resume_pure_goza_panes_background "$ZELLIJ_UI_SESSION"' "$PROJECT_ROOT/scripts/goza_no_ma.sh"
    [ "$status" -ne 0 ]
    run rg -nF 'zellij_schedule_resume_after_attach "$ZELLIJ_UI_SESSION"' "$PROJECT_ROOT/scripts/goza_no_ma.sh"
    [ "$status" -ne 0 ]
}

@test "pure zellij: レイアウトpaneは command=start_suspended=false で runner を直接起動する" {
    run rg -nF 'command="bash" start_suspended=false {' "$PROJECT_ROOT/scripts/goza_no_ma.sh"
    [ "$status" -eq 0 ]
    run rg -nF 'exec bash %q %q %q' "$PROJECT_ROOT/scripts/goza_no_ma.sh"
    [ "$status" -eq 0 ]
}

@test "pure zellij: run-id付き bootstrap ログを出力する" {
    run rg -n "GOZA_BOOTSTRAP_LOG|goza_bootstrap_\$\{GOZA_BOOTSTRAP_RUN_ID\}" "$PROJECT_ROOT/scripts/goza_no_ma.sh"
    [ "$status" -eq 0 ]
    run rg -nF 'goza_bootstrap_log "run start' "$PROJECT_ROOT/scripts/goza_no_ma.sh"
    [ "$status" -eq 0 ]
}

@test "pure zellij: bootstrap本文は外側send-lineではなくファイルとして保存する" {
    run rg -nF 'bootstrap prepared agent=$agent cli=$cli_type file=' "$PROJECT_ROOT/scripts/goza_no_ma.sh"
    [ "$status" -eq 0 ]
    run rg -nF 'bootstrap delivered agent=$agent cli=$cli_type mode=send-line' "$PROJECT_ROOT/scripts/goza_no_ma.sh"
    [ "$status" -ne 0 ]
}

@test "pure zellij: Gemini は interactive prompt フラグで初回命令を起動引数に載せる" {
    run rg -nF "printf '%s -i %q\\n'" "$PROJECT_ROOT/lib/cli_adapter.sh"
    [ "$status" -eq 0 ]
}

@test "pure zellij: Codex と Claude は初回命令を positional prompt で起動引数に載せる" {
    run rg -nF "printf '%s %q\\n' \"\$base_cmd\" \"\$prompt\"" "$PROJECT_ROOT/lib/cli_adapter.sh"
    [ "$status" -eq 0 ]
}
