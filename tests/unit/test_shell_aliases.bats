#!/usr/bin/env bats

setup_file() {
    export PROJECT_ROOT
    PROJECT_ROOT="$(cd "$(dirname "$BATS_TEST_FILENAME")/../.." && pwd)"
}

@test "shell_aliases は source で repo-local alias を定義する" {
    run bash -lc "source '$PROJECT_ROOT/scripts/shell_aliases.sh'; alias cgo; alias css; alias csg; alias csm; alias csst"
    [ "$status" -eq 0 ]
    [[ "$output" == *"alias cgo='bash $PROJECT_ROOT/scripts/goza_no_ma.sh'"* ]]
    [[ "$output" == *"alias css='bash $PROJECT_ROOT/scripts/focus_agent_pane.sh shogun'"* ]]
    [[ "$output" == *"alias csg='bash $PROJECT_ROOT/scripts/focus_agent_pane.sh gunshi'"* ]]
    [[ "$output" == *"alias csm='bash $PROJECT_ROOT/scripts/focus_agent_pane.sh karo'"* ]]
    [[ "$output" == *"alias csst='cd $PROJECT_ROOT && ./shutsujin_departure.sh'"* ]]
}

@test "install_shell_aliases は stale alias を repo-local source block へ置き換える" {
    rc_file="$BATS_TEST_TMPDIR/bashrc"
    cat > "$rc_file" <<'EOF'
alias cgo='bash /mnt/d/Git_WorkSpace/Human-Emulator/scripts/goza_no_ma.sh'
export SAMPLE_FLAG=1
EOF

    run bash "$PROJECT_ROOT/scripts/install_shell_aliases.sh" "$rc_file"
    [ "$status" -eq 0 ]

    grep -qF '# >>> multi-agent-shognate aliases >>>' "$rc_file"
    grep -qF "source \"$PROJECT_ROOT/scripts/shell_aliases.sh\"" "$rc_file"
    grep -qF '# <<< multi-agent-shognate aliases <<<' "$rc_file"
    grep -qF 'export SAMPLE_FLAG=1' "$rc_file"
    ! grep -qF 'Human-Emulator/scripts/goza_no_ma.sh' "$rc_file"
}

@test "install_shell_aliases は idempotent に managed block を 1 つだけ保つ" {
    rc_file="$BATS_TEST_TMPDIR/bashrc"
    printf 'export SAMPLE_FLAG=1\n' > "$rc_file"

    run bash "$PROJECT_ROOT/scripts/install_shell_aliases.sh" "$rc_file"
    [ "$status" -eq 0 ]
    run bash "$PROJECT_ROOT/scripts/install_shell_aliases.sh" "$rc_file"
    [ "$status" -eq 0 ]

    [ "$(grep -c '^# >>> multi-agent-shognate aliases >>>$' "$rc_file")" -eq 1 ]
    [ "$(grep -c '^# <<< multi-agent-shognate aliases <<<$' "$rc_file")" -eq 1 ]
    [ "$(grep -cF "source \"$PROJECT_ROOT/scripts/shell_aliases.sh\"" "$rc_file")" -eq 1 ]
}
