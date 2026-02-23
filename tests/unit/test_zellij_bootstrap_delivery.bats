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

@test "tmux: wait_for_cli_ready_tmux はスクリーン内容ベースで判定する" {
    run rg -nF 'wait_for_cli_ready_tmux' "$PROJECT_ROOT/shutsujin_departure.sh"
    [ "$status" -eq 0 ]
    run rg -nF 'tmux capture-pane -p' "$PROJECT_ROOT/shutsujin_departure.sh"
    [ "$status" -eq 0 ]
    # コード行（コメントでない行）に pane_current_command が残っていないことを確認
    # ^[^#]* でコメント行を除外（行頭 # 以外の行にパターンがあれば non-zero 以外で返す）
    run rg -n '^[^#]*pane_current_command' "$PROJECT_ROOT/shutsujin_departure.sh"
    [ "$status" -ne 0 ]
}

@test "tmux: deliver_bootstrap_tmux はcli_typeを受け取り個別にready待機する" {
    run rg -nF 'wait_for_cli_ready_tmux "$pane_target" "$cli_type"' "$PROJECT_ROOT/shutsujin_departure.sh"
    [ "$status" -eq 0 ]
    run rg -nF 'deliver_bootstrap_tmux "shogun:main" "shogun" "$_shogun_cli_type"' "$PROJECT_ROOT/shutsujin_departure.sh"
    [ "$status" -eq 0 ]
    run rg -nF 'deliver_bootstrap_tmux "gunshi:main" "gunshi" "$_gunshi_cli_type"' "$PROJECT_ROOT/shutsujin_departure.sh"
    [ "$status" -eq 0 ]
}

@test "tmux: deliver_bootstrap_tmux は -l フラグでリテラル送信し Enter で確定する" {
    # -l フラグ（リテラル送信）が使われていること
    run rg -nF 'tmux send-keys -l -t "$pane_target" "$msg"' "$PROJECT_ROOT/shutsujin_departure.sh"
    [ "$status" -eq 0 ]
    # ブートストラップ確定は Enter（名前付きキー）で行うこと
    run rg -nF 'tmux send-keys -t "$pane_target" Enter' "$PROJECT_ROOT/shutsujin_departure.sh"
    [ "$status" -eq 0 ]
}

@test "pure zellij: レイアウトに gunshi ペインが含まれる" {
    run rg -nF 'gunshi_agent' "$PROJECT_ROOT/scripts/goza_no_ma.sh"
    [ "$status" -eq 0 ]
    run rg -nF '"$gunshi_agent"' "$PROJECT_ROOT/scripts/goza_no_ma.sh"
    [ "$status" -eq 0 ]
}
