#!/usr/bin/env bats

setup_file() {
    export PROJECT_ROOT
    PROJECT_ROOT="$(cd "$(dirname "$BATS_TEST_FILENAME")/../.." && pwd)"
}

@test "shell_aliases は source で repo-local alias を定義する" {
    run bash -lc "source '$PROJECT_ROOT/scripts/shell_aliases.sh'; alias cgo; alias css; alias cgn; alias csg; alias csk; alias ckr; alias csm; alias csst; alias csa; alias cma; alias CGO; alias CSS; alias CGN; alias CSG; alias CSK; alias CKR; alias CSM; alias CSST; alias CSA; alias CMA"
    [ "$status" -eq 0 ]
    [[ "$output" == *"alias cgo='bash $PROJECT_ROOT/scripts/goza_no_ma.sh'"* ]]
    [[ "$output" == *"alias css='bash $PROJECT_ROOT/scripts/focus_agent_pane.sh shogun'"* ]]
    [[ "$output" == *"alias cgn='bash $PROJECT_ROOT/scripts/focus_agent_pane.sh gunkan'"* ]]
    [[ "$output" == *"alias csg='bash $PROJECT_ROOT/scripts/focus_agent_pane.sh gunshi'"* ]]
    [[ "$output" == *"alias csk='bash $PROJECT_ROOT/scripts/focus_agent_pane.sh karo'"* ]]
    [[ "$output" == *"alias ckr='bash $PROJECT_ROOT/scripts/focus_agent_pane.sh karo'"* ]]
    [[ "$output" == *"alias csm='bash $PROJECT_ROOT/scripts/goza_no_ma.sh -t multiagent'"* ]]
    [[ "$output" == *"alias csst='cd $PROJECT_ROOT && ./shutsujin_departure.sh'"* ]]
    [[ "$output" == *"alias csa='bash $PROJECT_ROOT/scripts/goza_no_ma.sh -t ashigaru'"* ]]
    [[ "$output" == *"alias cma='bash $PROJECT_ROOT/scripts/goza_no_ma.sh -t multiagent'"* ]]
    [[ "$output" == *"alias CGO='bash $PROJECT_ROOT/scripts/goza_no_ma.sh'"* ]]
    [[ "$output" == *"alias CGN='bash $PROJECT_ROOT/scripts/focus_agent_pane.sh gunkan'"* ]]
    [[ "$output" == *"alias CSA='bash $PROJECT_ROOT/scripts/goza_no_ma.sh -t ashigaru'"* ]]
    [[ "$output" == *"alias CSM='bash $PROJECT_ROOT/scripts/goza_no_ma.sh -t multiagent'"* ]]
    [[ "$output" == *"alias CSK='bash $PROJECT_ROOT/scripts/focus_agent_pane.sh karo'"* ]]
    [[ "$output" == *"alias CKR='bash $PROJECT_ROOT/scripts/focus_agent_pane.sh karo'"* ]]
}

@test "install_shell_aliases は stale alias を repo-local source block へ置き換える" {
    rc_file="$BATS_TEST_TMPDIR/bashrc"
    cat > "$rc_file" <<'EOF'
alias cgo='bash /opt/old-human-emulator/scripts/goza_no_ma.sh'
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
