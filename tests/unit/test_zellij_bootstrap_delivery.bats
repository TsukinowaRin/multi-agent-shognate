#!/usr/bin/env bats

setup_file() {
    export PROJECT_ROOT
    PROJECT_ROOT="$(cd "$(dirname "$BATS_TEST_FILENAME")/../.." && pwd)"
}

@test "zellij: 起動と初動送信はエージェント単位で順次実行" {
    run rg -n "初動命令をエージェント単位で順次配信" "$PROJECT_ROOT/scripts/shutsujin_zellij.sh"
    [ "$status" -eq 0 ]
    run rg -nF 'wait_for_cli_ready "$agent" "$cli_type" 25' "$PROJECT_ROOT/scripts/shutsujin_zellij.sh"
    [ "$status" -eq 0 ]
    run rg -nF 'deliver_bootstrap_zellij "$agent" "$cli_type"' "$PROJECT_ROOT/scripts/shutsujin_zellij.sh"
    [ "$status" -eq 0 ]
}

@test "zellij: ready判定はCLI種別パターンを利用" {
    run rg -n "case \"\\$cli_type\" in|ready_pattern='" "$PROJECT_ROOT/scripts/shutsujin_zellij.sh"
    [ "$status" -eq 0 ]
    run rg -nF 'grep -qiE "$ready_pattern"' "$PROJECT_ROOT/scripts/shutsujin_zellij.sh"
    [ "$status" -eq 0 ]
}

@test "zellij: エージェント間ギャップ設定がある" {
    run rg -n "MAS_ZELLIJ_BOOTSTRAP_GAP|BOOTSTRAP_AGENT_GAP" "$PROJECT_ROOT/scripts/shutsujin_zellij.sh"
    [ "$status" -eq 0 ]
}
