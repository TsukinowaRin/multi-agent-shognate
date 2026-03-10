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
    run rg -nF 'interactive_agent_runner.py' "$PROJECT_ROOT/scripts/zellij_agent_bootstrap.sh"
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

@test "pure zellij: 既定レイアウト比率は右列を広めに確保する" {
    run rg -nF 'GOZA_PURE_LEFT_WIDTH:-38%' "$PROJECT_ROOT/scripts/goza_no_ma.sh"
    [ "$status" -eq 0 ]
    run rg -nF 'GOZA_PURE_MIDDLE_WIDTH:-22%' "$PROJECT_ROOT/scripts/goza_no_ma.sh"
    [ "$status" -eq 0 ]
    run rg -nF 'GOZA_PURE_RIGHT_WIDTH:-40%' "$PROJECT_ROOT/scripts/goza_no_ma.sh"
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

@test "pure zellij: runner は Codex update / Gemini preflight を pane 内で処理する" {
    run rg -n 'codex update skipped agent=|gemini trust accepted agent=|gemini keep_trying agent=' "$PROJECT_ROOT/scripts/interactive_agent_runner.py"
    [ "$status" -eq 0 ]
}

@test "pure zellij: runner は CLI ready 検出後に bootstrap を送信する" {
    run rg -n 'ready_pattern.search|bootstrap delivered agent=' "$PROJECT_ROOT/scripts/interactive_agent_runner.py"
    [ "$status" -eq 0 ]
}
