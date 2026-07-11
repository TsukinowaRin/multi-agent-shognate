#!/usr/bin/env bats

setup_file() {
    export PROJECT_ROOT
    PROJECT_ROOT="$(cd "$(dirname "$BATS_TEST_FILENAME")/../.." && pwd)"
    export SCRIPT
    SCRIPT="$PROJECT_ROOT/scripts/mux_parity_smoke.sh"
}

@test "mux_parity_smoke: --dry-run で tmux コマンドのみ表示する" {
    run bash "$SCRIPT" --dry-run
    [ "$status" -eq 0 ]
    [[ "$output" =~ "MAS_MULTIPLEXER=tmux bash shogunate_mod/runtime/entrypoint.sh -s" ]]
}

@test "mux_parity_smoke: --tmux-only --dry-run は tmux のみ表示する" {
    run bash "$SCRIPT" --tmux-only --dry-run
    [ "$status" -eq 0 ]
    [[ "$output" =~ "MAS_MULTIPLEXER=tmux bash shogunate_mod/runtime/entrypoint.sh -s" ]]
    [[ ! "$output" =~ "MAS_MULTIPLEXER=zellij bash shogunate_mod/runtime/entrypoint.sh -s" ]]
}

@test "mux_parity_smoke: tmux setup 成功時は exit 0 で完了する" {
    local fake_bin real_bash
    fake_bin="$BATS_TEST_TMPDIR/bin"
    real_bash="$(command -v bash)"
    mkdir -p "$fake_bin"

    cat > "$fake_bin/tmux" <<'SH'
#!/usr/bin/env sh
exit 0
SH
    cat > "$fake_bin/bash" <<SH
#!/usr/bin/env sh
if [ "\$1" = "shogunate_mod/runtime/entrypoint.sh" ]; then
  mkdir -p queue/inbox queue/runtime
  : > queue/ntfy_inbox.yaml
  printf 'ashigaru1\tkaro\n' > queue/runtime/ashigaru_owner.tsv
  exit 0
fi
exec "$real_bash" "\$@"
SH
    chmod +x "$fake_bin/tmux" "$fake_bin/bash"

    PATH="$fake_bin:$PATH" run bash "$SCRIPT" --tmux-only
    [ "$status" -eq 0 ]
    [[ "$output" =~ "[OK] tmux smoke test passed" ]]
}
