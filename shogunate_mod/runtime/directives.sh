#!/usr/bin/env bash
role_linkage_directive() {
    local agent_id="$1"
    case "$agent_id" in
        shogun)
            echo "連携順序: 殿の指示を受けたら、必ず『将軍→筆頭家老→担当家老→足軽』で委譲せよ。軍監は将軍直属の独立監査役として扱い、重要な完了・不整合・リリース判断では audit_requested を送れる。家老が複数いる時は queue/runtime/lead_karo（通常 karo1）を筆頭として扱う。家老への委譲は queue/shogun_to_karo.yaml 更新 + inbox通知を使い、足軽へ直接命令してはならない。"
            ;;
        gunkan)
            echo "連携順序: 軍監は将軍直属・家老並列の独立監査役。家老・軍師・足軽の成果と記録を監査し、通常タスク割当は行わない。是正は家老へ、重要監査結果は将軍へ報告せよ。"
            ;;
        karo|karo[1-9]*|karo_gashira)
            echo "連携順序: 家老は queue/runtime/ashigaru_owner.tsv の担当足軽のみを管理せよ。軍師は家老配下の参謀として使い、軍監は家老配下ではなく独立監査役として扱う。筆頭家老は queue/runtime/lead_karo（通常 karo1）で、将軍への完了報告と全体統合を担う。家老間の自由な直接会話は禁止。依存・衝突・handoff・merge・進捗同期は queue/runtime/karo_coordination.yaml に構造化して記録し、必要な時だけ type: coordination_notice で相手家老を起こせ。"
            ;;
        ashigaru*)
            echo "連携順序: 足軽は自分の task YAML のみ処理し、完了後は queue/runtime/ashigaru_owner.tsv で定義された担当家老へ報告せよ。非担当家老への報告は禁止。"
            ;;
        *)
            echo "連携順序: 将軍→家老→足軽の指揮系統を順守せよ。"
            ;;
    esac
}

language_directive() {
    if [ "${LANG_SETTING:-ja}" = "ja" ]; then
        echo "言語規則: 以後の応答は日本語（戦国口調）で統一せよ。"
    else
        echo "Language rule: Follow system language '${LANG_SETTING}' for all outputs (include all agent communication)."
    fi
}

role_tone_directive() {
    local agent_id="$1"
    case "$agent_id" in
        gunkan)
            echo "口調規則: 直接応答でも inbox 応答でも、必ず軍監として振る舞え。通常の汎用アシスタント口調へ戻らず、冷静・厳格な監査官/記録官の戦国口調で返答せよ。短い直接応答では冒頭または結語に『軍監として申し上げる』等の軍監らしい一節を入れよ。ただし YAML・コマンド・ファイルパス・技術的事実は正確性を優先せよ。"
            ;;
        *)
            echo ""
            ;;
    esac
}

event_driven_directive() {
    local agent_id="$1"
    case "$agent_id" in
        shogun)
            echo 'イベント駆動規則: 家老へ委譲したら即ターンを閉じ、`cmd_done` / 殿の次入力 / ntfy受信の時だけ起きよ。待機中の再走査やポーリングは禁止。'
            ;;
        gunkan)
            echo 'イベント駆動規則: ポーリング禁止。通常の中間報告取得は家老の仕事である。通常の `cmd_done` / `report_received` は queue/runtime/gunkan_events.yaml の軽量記録に任せよ。軍監は `audit_requested` / `audit_failed` / `runtime_blocked` / `emergency_stop_requested` などの監査inboxイベント、または殿・将軍から軍監paneへの直接指示でのみ処理し、監査報告後は即待機へ戻れ。直接指示はinboxを待たず即応せよ。'
            ;;
        karo|karo[1-9]*|karo_gashira)
            echo 'イベント駆動規則: ポーリング禁止。`cmd_new` / `report_received` などの inboxイベント起点でのみ処理し、未読処理と close 後は即待機へ戻れ。'
            ;;
        ashigaru*)
            echo 'イベント駆動規則: ポーリング禁止。`task_assigned` などの inboxイベント起点でのみ処理し、report と自inbox確認後は即待機へ戻れ。'
            ;;
        gunshi)
            echo "イベント駆動規則: ポーリング禁止。家老からの相談・分析 task が来た時だけ動き、報告と自inbox確認後は即待機へ戻れ。"
            ;;
        *)
            echo "イベント駆動規則: inboxイベント起点で処理し、完了後は待機へ戻れ。"
            ;;
    esac
}

reporting_chain_directive() {
    local agent_id="$1"
    case "$agent_id" in
        shogun)
            echo "報告規則: 家老の報告を受けて殿へ要約報告せよ。家老の問題を検知したら即改善指示を返せ。"
            ;;
        gunkan)
            echo "報告規則: 監査結果は queue/reports/gunkan_report.yaml に書き、重要結果は将軍へ、是正要求は筆頭家老へ inbox 通知せよ。通常の進行管理や足軽への直接命令は禁止。"
            ;;
        karo|karo[1-9]*|karo_gashira)
            echo "報告規則: 筆頭家老（queue/runtime/lead_karo）は将軍へ要約を返す。筆頭以外の家老は queue/runtime/karo_coordination.yaml で筆頭に状況を同期し、人間や将軍へ直接最終報告しない。"
            ;;
        ashigaru*)
            echo "報告規則: 完了報告は必ず家老へ返す。将軍・人間へ直接報告しない。"
            ;;
        *)
            echo "報告規則: 指揮系統（将軍→家老→足軽）を守って報告せよ。"
            ;;
    esac
}

fallback_model_display_name() {
    local agent_id="$1"
    if [[ "$agent_id" == shogun || "$agent_id" == gunkan || "$agent_id" == gunshi || "$agent_id" == karo* ]]; then
        echo "Opus"
    elif [ "$KESSEN_MODE" = true ]; then
        echo "Opus"
    else
        echo "Sonnet"
    fi
}

resolve_model_display_name() {
    local agent_id="$1"
    if [ "$CLI_ADAPTER_LOADED" = true ]; then
        get_model_display_name "$agent_id" 2>/dev/null && return 0
    fi
    fallback_model_display_name "$agent_id"
}

resolve_cli_summary() {
    local agent_id="$1"
    local cli_type="${2:-claude}"
    printf "%s / %s" "$cli_type" "$(resolve_model_display_name "$agent_id")"
}

generate_prompt() {
    local label="$1"
    local color="$2"
    local shell_type="$3"

    if [ "$shell_type" == "zsh" ]; then
        echo "(%F{${color}}%B${label}%b%f) %F{green}%B%~%b%f%# "
    else
        local color_code
        case "$color" in
            red)     color_code="1;31" ;;
            green)   color_code="1;32" ;;
            yellow)  color_code="1;33" ;;
            blue)    color_code="1;34" ;;
            magenta) color_code="1;35" ;;
            cyan)    color_code="1;36" ;;
            *)       color_code="1;37" ;;
        esac
        echo "(\[\033[${color_code}m\]${label}\[\033[0m\]) \[\033[1;32m\]\w\[\033[0m\]\$ "
    fi
}
