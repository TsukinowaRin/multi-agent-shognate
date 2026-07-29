#!/usr/bin/env bash
append_bootstrap_status_log() {
    local agent_id="$1"
    local cli_type="$2"
    local pane_target="$3"
    local status="$4"
    local detail="${5:-}"

    mkdir -p "$SCRIPT_DIR/queue/runtime"
    printf '%s\tagent=%s\tcli=%s\tpane=%s\tstatus=%s\tdetail=%s\n' \
        "$(date '+%Y-%m-%d %H:%M:%S %Z')" \
        "$agent_id" \
        "$cli_type" \
        "$pane_target" \
        "$status" \
        "$detail" >> "$GOZA_BOOTSTRAP_LOG"
}

# ブートストラップメッセージを事前にファイルへ書き出す
# 各エージェントが自分専用のファイルを読むことで誤送信を根本的に排除
generate_bootstrap_file() {
    local agent_id="$1"
    local cli_type="$2"
    local bootstrap_dir="$SCRIPT_DIR/queue/runtime"
    local bootstrap_file="$bootstrap_dir/bootstrap_${agent_id}.md"
    local pending_file="$bootstrap_dir/bootstrap_${agent_id}.pending"
    local delivered_file="$bootstrap_dir/bootstrap_${agent_id}.delivered"
    local ready_file="$bootstrap_dir/bootstrap_${agent_id}.ready"
    local role_instruction_file=""
    local optimized_instruction_file=""
    local lang_rule="" event_rule="" report_rule="" linkage_rule="" tone_rule="" startup_fastpath="" instruction_ref_rule="" ready_instruction=""

    if [ "$CLI_ADAPTER_LOADED" = true ]; then
        role_instruction_file="$(get_role_instruction_file "$agent_id" 2>/dev/null || true)"
        optimized_instruction_file="$(get_instruction_file "$agent_id" "$cli_type" 2>/dev/null || true)"
    fi

    if [ -z "$role_instruction_file" ]; then
        case "$agent_id" in
            shogun) role_instruction_file="instructions/shogun.md" ;;
            gunkan) role_instruction_file="instructions/gunkan.md" ;;
            gunshi) role_instruction_file="instructions/gunshi.md" ;;
            karo|karo[1-9]*|karo_gashira) role_instruction_file="instructions/karo.md" ;;
            ashigaru*) role_instruction_file="instructions/ashigaru.md" ;;
            *) role_instruction_file="AGENTS.md" ;;
        esac
    fi

    if [ -z "$optimized_instruction_file" ] || [ ! -f "$SCRIPT_DIR/$optimized_instruction_file" ]; then
        optimized_instruction_file="$role_instruction_file"
    fi

    linkage_rule="$(role_linkage_directive "$agent_id")"
    lang_rule="$(language_directive)"
    event_rule="$(event_driven_directive "$agent_id")"
    report_rule="$(reporting_chain_directive "$agent_id")"
    tone_rule="$(role_tone_directive "$agent_id")"
    startup_fastpath="$(startup_fastpath_directive "$agent_id")"
    ready_instruction="$(bootstrap_ready_instruction_text "$agent_id")"
    instruction_ref_rule="正本参照: project側AGENTS.md、${SCRIPT_DIR}/AGENTS.md、${SCRIPT_DIR}/${optimized_instruction_file} を役職・CLI別の正本として扱え。ただし起動直後にこれらを全文読込しない。実タスク、未読inbox、直接指示を処理する時だけ必要な最小範囲を読むこと。"

    local startup_msg
    if [ "$optimized_instruction_file" != "$role_instruction_file" ]; then
        startup_msg="【初動命令】あなたは${agent_id}。作業対象projectは ${SHOGUNATE_PROJECT_DIR}、Shogunate runtime rootは ${SCRIPT_DIR} である。この初動命令を ${cli_type} 用の正本指示として即適用せよ。${instruction_ref_rule} queue/dashboard/logs は ${SCRIPT_DIR} 配下を正とする。${SCRIPT_DIR}/${role_instruction_file} との比較・diff・読み比べは不要。${lang_rule} ${tone_rule} ${event_rule} ${linkage_rule} ${report_rule} ${startup_fastpath} ${ready_instruction}"
    else
        startup_msg="【初動命令】あなたは${agent_id}。作業対象projectは ${SHOGUNATE_PROJECT_DIR}、Shogunate runtime rootは ${SCRIPT_DIR} である。この初動命令を役割・口調・禁止事項の正本指示として即適用せよ。${instruction_ref_rule} queue/dashboard/logs は ${SCRIPT_DIR} 配下を正とする。${lang_rule} ${tone_rule} ${event_rule} ${linkage_rule} ${report_rule} ${startup_fastpath} ${ready_instruction}"
    fi

    mkdir -p "$bootstrap_dir"
    echo "$startup_msg" > "$bootstrap_file"
    : > "$pending_file"
    rm -f "$delivered_file" "$ready_file"
    clear_bootstrap_diagnostic_for_agent "$agent_id"
}

bootstrap_ready_instruction_text() {
    local agent_id="$1"
    # 完成形tokenを指示文へ書くと、TUIの自動折返しでtokenだけが単独行となり、
    # モデル応答と誤認できる。構成要素だけを説明し、完成形は応答にだけ現す。
    printf '準備が整ったら、半角英字 ready、半角コロン、役職ID %s を空白なしで連結した1行だけを返し、追加探索せず未読inbox監視へ戻れ。\n' "$agent_id"
}

bootstrap_message_text() {
    local agent_id="$1"
    local bootstrap_file="$SCRIPT_DIR/queue/runtime/bootstrap_${agent_id}.md"
    [ -f "$bootstrap_file" ] || return 1
    cat "$bootstrap_file"
}

bootstrap_acknowledged_tmux() {
    local pane_target="$1"
    local agent_id="$2"
    local screen_content="${3:-}"
    local ack_token=""

    ack_token="ready:${agent_id}"
    [[ -n "$ack_token" ]] || return 1
    if [ -z "$screen_content" ]; then
        screen_content=$(tmux capture-pane -p -t "$pane_target" 2>/dev/null || true)
    fi
    # Grok TUIはassistant応答の右端へ時刻とscrollbarを同じ行に描画する。
    # 指示文側には完成形tokenを書かないため、token単独またはtoken+UI装飾だけを
    # 許可してもuser promptをackと誤認しない。
    printf '%s\n' "$screen_content" | grep -Eq \
        "^[[:space:]]*([•●][[:space:]]*)?${ack_token}([[:space:]]+[0-9]{1,2}:[0-9]{2}[[:space:]]*(AM|PM)?)?[[:space:]│█]*$"
}

mark_bootstrap_ready_tmux() {
    local pane_target="$1"
    local agent_id="$2"
    local cli_type="${3:-unknown}"
    local ready_file="$SCRIPT_DIR/queue/runtime/bootstrap_${agent_id}.ready"

    if [ ! -f "$ready_file" ]; then
        : > "$ready_file"
        append_bootstrap_status_log "$agent_id" "$cli_type" "$pane_target" "bootstrap-ready" "ready:${agent_id} acknowledged"
    fi
}

redact_bootstrap_diagnostic_text() {
    local screen_content="${1:-}"
    printf '%s\n' "$screen_content" | sed -E \
        -e 's#https?://[^[:space:]]+#[redacted-url]#g' \
        -e 's/[A-Za-z0-9._%+-]+@[A-Za-z0-9.-]+/[redacted-email]/g' \
        -e 's/[A-Za-z0-9_=+-]{32,}/[redacted-long-token]/g'
}

clear_bootstrap_diagnostic_for_agent() {
    local agent_id="$1"
    local safe_agent=""
    safe_agent="$(printf '%s' "$agent_id" | tr -c 'A-Za-z0-9_.-' '_')"
    # role単位の生成物だけを対象とし、他roleや診断directory全体は消さない。
    rm -f "$SCRIPT_DIR/queue/runtime/bootstrap_diagnostics/${safe_agent}.txt"
}

capture_bootstrap_diagnostic_tmux() {
    local pane_target="$1"
    local agent_id="$2"
    local cli_type="${3:-unknown}"
    local reason="${4:-not-ready}"
    local diagnostic_dir="$SCRIPT_DIR/queue/runtime/bootstrap_diagnostics"
    local safe_agent=""
    local diagnostic_file=""
    local tmp_file=""
    local screen_content=""

    safe_agent="$(printf '%s' "$agent_id" | tr -c 'A-Za-z0-9_.-' '_')"
    mkdir -p "$diagnostic_dir"
    diagnostic_file="$diagnostic_dir/${safe_agent}.txt"
    tmp_file="${diagnostic_file}.tmp.$$"
    screen_content="$(tmux capture-pane -p -t "$pane_target" -S -120 2>/dev/null || true)"
    {
        printf 'agent=%s\ncli=%s\npane=%s\nreason=%s\ncaptured_at=%s\n---\n' \
            "$agent_id" "$cli_type" "$pane_target" "$reason" "$(date '+%Y-%m-%d %H:%M:%S %Z')"
        redact_bootstrap_diagnostic_text "$screen_content"
    } > "$tmp_file"
    mv "$tmp_file" "$diagnostic_file"
    append_bootstrap_status_log "$agent_id" "$cli_type" "$pane_target" "diagnostic-saved" "queue/runtime/bootstrap_diagnostics/${safe_agent}.txt"
}

cli_ready_screen_detected() {
    local cli_type="${1:-}"
    local screen_content="${2:-}"

    case "$cli_type" in
        claude)
            printf '%s' "$screen_content" | grep -qiE 'Quick safety check: Is this a project you created or one you trust\?|Yes, I trust this folder' && return 1
            printf '%s' "$screen_content" | grep -qiE 'Claude Code v[0-9]|manual mode on.*for shortcuts|(auto|manual) mode on.*for agents'
            ;;
        codex)
            printf '%s' "$screen_content" | grep -qiE '(openai codex|/model to change|Use /skills|Tip:|Working|esc to interrupt|% left|context left)'
            ;;
        antigravity)
            printf '%s' "$screen_content" | grep -qiE 'Do you trust this folder|Do you trust the contents of this project\?|Antigravity CLI requires permission to read, edit, and execute files here' && return 1
            printf '%s' "$screen_content" | grep -qiE 'Antigravity CLI[[:space:]]+[0-9]' && \
                printf '%s' "$screen_content" | grep -qiE '\? for shortcuts|esc to cancel|Generating\.\.\.'
            ;;
        grok)
            # 起動bannerは会話後にscroll outする。Grok TUIの常設shortcut行も
            # composer readyの証拠に含め、応答後のwake/bootstrap再送を可能にする。
            printf '%s' "$screen_content" | grep -qiE 'Grok Build( Beta)?[[:space:]]+[0-9]|Ctrl\+x:shortcuts'
            ;;
        copilot)
            printf '%s' "$screen_content" | grep -qiE 'GitHub Copilot|Copilot CLI|/model'
            ;;
        kimi)
            printf '%s' "$screen_content" | grep -qiE 'Kimi|Moonshot|/model'
            ;;
        opencode)
            printf '%s' "$screen_content" | grep -qiE 'OpenCode|Ask anything|ctrl\+p commands|/model|ready:'
            ;;
        kilo)
            printf '%s' "$screen_content" | grep -qiE 'Kilo|/model|ready:'
            ;;
        localapi)
            printf '%s' "$screen_content" | grep -qiE 'LocalAPI|ready:|\$'
            ;;
        *)
            return 1
            ;;
    esac
}

startup_fastpath_directive() {
    local agent_id="$1"
    case "$agent_id" in
        shogun)
            echo "初動最適化: 起動直後は自inboxだけ確認し、未読が無ければ即待機。task_assigned を受けたら queue/shogun_to_karo.yaml・自inbox・settings だけで即 cmd 起票し、app.py/tests/README や git status のような実装調査は家老へ委ねよ。"
            ;;
        karo|karo[1-9]*|karo_gashira)
            echo "初動最適化: 起動直後は自inboxだけ確認して待機。cmd_new は inbox・queue/shogun_to_karo.yaml・active ashigaru の task/report YAML だけで即 in_progress と task_assigned まで進め。成果物や工程が分けられる cmd なら、active ashigaru 全体を確認し、ashigaru1/2だけで止めず、ashigaru3以降も含めて有用で安全な数の補完的 subtasks を初手で切ってから待機せよ。複雑・高リスク・分解困難なら初手dispatchを止めずに queue/tasks/gunshi.yaml へ分析taskを並行投入せよ。dashboard/settings/対象コードは dispatch 後か runtime 矛盾時だけ読め。report_received は report YAML を正本として dashboard 更新と cmd close を最優先せよ。bridge/ntfy/streaks/sample は異常時以外読むな。"
            ;;
        ashigaru*)
            echo "初動最適化: 起動直後は自inbox/task だけ確認し、未読も task も無ければ即待機。着手後も自task と対象ファイルに限定して動け。"
            ;;
        gunshi)
            echo "初動最適化: 起動直後は自inbox/task だけ確認し、未読が無ければ即待機。相談が来た時だけ必要最小限の資料を読め。"
            ;;
        *)
            echo "初動最適化: 起動直後は自inbox/task の最小確認だけを行い、全体探索は実タスク受領後まで遅らせよ。"
            ;;
    esac
}

# CLIの準備完了をスクリーン内容で確認（pane_current_command の誤判定を回避）
# codex / antigravity は node 等で表示されるため、UI文字列パターンで判定する。
wait_for_cli_ready_tmux() {
    local pane_target="$1"
    local cli_type="${2:-claude}"
    local max_wait="${3:-30}"
    local i

    # max_wait=0 でも1回は即時チェックする（for ループでは 0<0 が偽でスキップされるため分離）
    local screen_content
    screen_content=$(tmux capture-pane -p -t "$pane_target" 2>/dev/null || true)
    if [ "$cli_type" = "opencode" ] && opencode_project_prompt_detected_tmux "$pane_target"; then
        auto_accept_opencode_project_prompt_tmux "$pane_target" "startup" || true
        screen_content=$(tmux capture-pane -p -t "$pane_target" 2>/dev/null || true)
    fi
    if [ "$cli_type" = "opencode" ] && opencode_update_prompt_detected_tmux "$screen_content"; then
        auto_skip_opencode_update_prompt_tmux "$pane_target" "startup" "$cli_type" || true
        screen_content=$(tmux capture-pane -p -t "$pane_target" 2>/dev/null || true)
    fi
    if [ "$cli_type" = "antigravity" ] && antigravity_feedback_prompt_detected_tmux "$screen_content"; then
        auto_skip_antigravity_feedback_prompt_tmux "$pane_target" "startup" "$cli_type" || true
        screen_content=$(tmux capture-pane -p -t "$pane_target" 2>/dev/null || true)
    fi
    if [ "$cli_type" = "codex" ] && codex_auth_prompt_detected_tmux "$pane_target"; then
        return 2
    fi
    if cli_ready_screen_detected "$cli_type" "$screen_content"; then
        return 0
    fi

    for ((i=0; i<max_wait; i++)); do
        sleep 1
        screen_content=$(tmux capture-pane -p -t "$pane_target" 2>/dev/null || true)
        if [ "$cli_type" = "opencode" ] && opencode_project_prompt_detected_tmux "$pane_target"; then
            auto_accept_opencode_project_prompt_tmux "$pane_target" "startup" || true
            continue
        fi
        if [ "$cli_type" = "opencode" ] && opencode_update_prompt_detected_tmux "$screen_content"; then
            auto_skip_opencode_update_prompt_tmux "$pane_target" "startup" "$cli_type" || true
            continue
        fi
        if [ "$cli_type" = "antigravity" ] && antigravity_feedback_prompt_detected_tmux "$screen_content"; then
            auto_skip_antigravity_feedback_prompt_tmux "$pane_target" "startup" "$cli_type" || true
            continue
        fi
        if [ "$cli_type" = "codex" ] && codex_auth_prompt_detected_tmux "$pane_target"; then
            return 2
        fi
        if cli_ready_screen_detected "$cli_type" "$screen_content"; then
            return 0
        fi
    done
    return 1
}

# ファイルベースでブートストラップ配信（tmux版）
# ペインターゲットの存在を確認し、CLIの準備完了を待ってから送信
deliver_bootstrap_tmux() {
    local pane_target="$1"
    local agent_id="$2"
    local cli_type="${3:-claude}"
    local bootstrap_file="$SCRIPT_DIR/queue/runtime/bootstrap_${agent_id}.md"
    local pending_file="$SCRIPT_DIR/queue/runtime/bootstrap_${agent_id}.pending"
    local delivered_file="$SCRIPT_DIR/queue/runtime/bootstrap_${agent_id}.delivered"
    local ready_wait=30
    local screen_content=""

    if [ ! -f "$bootstrap_file" ]; then
        echo "[WARN] bootstrap file not found for $agent_id: $bootstrap_file" >&2
        append_bootstrap_status_log "$agent_id" "$cli_type" "$pane_target" "missing-bootstrap" "$bootstrap_file"
        return 1
    fi

    # ペイン存在チェック
    if ! tmux display-message -p -t "$pane_target" "#{pane_id}" >/dev/null 2>&1; then
        echo "[WARN] pane '$pane_target' not found, skipping bootstrap for $agent_id" >&2
        append_bootstrap_status_log "$agent_id" "$cli_type" "$pane_target" "missing-pane" "pane not found"
        return 1
    fi

    if [ ! -f "$pending_file" ]; then
        if [ -f "$delivered_file" ]; then
            append_bootstrap_status_log "$agent_id" "$cli_type" "$pane_target" "already-delivered" "pending cleared before startup delivery"
        fi
        return 0
    fi

    screen_content=$(tmux capture-pane -p -t "$pane_target" 2>/dev/null || true)
    if bootstrap_acknowledged_tmux "$pane_target" "$agent_id" "$screen_content"; then
        rm -f "$pending_file"
        : > "$delivered_file"
        mark_bootstrap_ready_tmux "$pane_target" "$agent_id" "$cli_type"
        append_bootstrap_status_log "$agent_id" "$cli_type" "$pane_target" "already-delivered" "bootstrap already acknowledged in pane"
        return 0
    fi
    if [ "$cli_type" = "codex" ]; then
        auto_accept_codex_hooks_prompt_tmux "$pane_target" "$agent_id" "$cli_type" || true
    fi
    if [ "$cli_type" = "opencode" ]; then
        auto_accept_opencode_project_prompt_tmux "$pane_target" "$agent_id" || true
    fi

    # CLIの準備完了を最大30秒待機（スクリーン内容ベース判定）
    local ready_rc=0
    if [ "$cli_type" = "codex" ]; then
        ready_wait="${MAS_CODEX_BOOTSTRAP_READY_WAIT:-5}"
    elif [ "$cli_type" = "opencode" ]; then
        ready_wait="${MAS_OPENCODE_BOOTSTRAP_READY_WAIT:-5}"
    elif [ "$cli_type" = "kilo" ]; then
        ready_wait="${MAS_KILO_BOOTSTRAP_READY_WAIT:-5}"
    fi
    wait_for_cli_ready_tmux "$pane_target" "$cli_type" "$ready_wait"
    ready_rc=$?
    if [ "$ready_rc" -ne 0 ]; then
        if [ "$ready_rc" -eq 2 ]; then
            record_runtime_blocker_tmux "$agent_id" "codex-auth-required" "Codex authentication prompt detected before bootstrap delivery."
            echo "[WARN] Codex authentication prompt detected in '$pane_target' for '$agent_id'. Skipping bootstrap until login completes." >&2
            append_bootstrap_status_log "$agent_id" "$cli_type" "$pane_target" "auth-required" "codex authentication prompt detected"
            return 1
        fi
        if [ "$cli_type" = "codex" ] && ! codex_process_running_tmux "$pane_target"; then
            echo "[WARN] Codex process is not running in '$pane_target' for '$agent_id'. Keeping bootstrap pending." >&2
            append_bootstrap_status_log "$agent_id" "$cli_type" "$pane_target" "cli-not-running" "codex pane current command is not node"
            return 1
        fi
        if [ "$cli_type" = "codex" ]; then
            echo "[WARN] Codex UI not ready in '$pane_target' for '$agent_id'. Keeping bootstrap pending for watcher retry." >&2
            append_bootstrap_status_log "$agent_id" "$cli_type" "$pane_target" "ready-pending" "codex ui not ready after wait; watcher retry will deliver"
            return 1
        fi
        screen_content=$(tmux capture-pane -p -t "$pane_target" 2>/dev/null || true)
        local blocker_kind=""
        blocker_kind="$(cli_startup_blocker_kind "$cli_type" "$screen_content")"
        if [ -n "$blocker_kind" ]; then
            record_runtime_blocker_tmux "$agent_id" "${cli_type}-${blocker_kind}" "CLI startup blocked before bootstrap delivery."
            append_bootstrap_status_log "$agent_id" "$cli_type" "$pane_target" "$blocker_kind" "bootstrap kept pending"
        else
            append_bootstrap_status_log "$agent_id" "$cli_type" "$pane_target" "ready-timeout" "bootstrap kept pending after ${ready_wait}s"
        fi
        capture_bootstrap_diagnostic_tmux "$pane_target" "$agent_id" "$cli_type" "${blocker_kind:-cli-ready-timeout}"
        echo "[WARN] CLI '$cli_type' not ready in '$pane_target' after ${ready_wait}s. Keeping bootstrap pending." >&2
        return 1
    fi

    if [ ! -f "$pending_file" ]; then
        if [ -f "$delivered_file" ]; then
            append_bootstrap_status_log "$agent_id" "$cli_type" "$pane_target" "already-delivered" "pending cleared during startup wait"
        fi
        return 0
    fi

    screen_content=$(tmux capture-pane -p -t "$pane_target" 2>/dev/null || true)
    if bootstrap_acknowledged_tmux "$pane_target" "$agent_id" "$screen_content"; then
        rm -f "$pending_file"
        : > "$delivered_file"
        mark_bootstrap_ready_tmux "$pane_target" "$agent_id" "$cli_type"
        append_bootstrap_status_log "$agent_id" "$cli_type" "$pane_target" "already-delivered" "bootstrap acknowledged during startup wait"
        return 0
    fi
    if [ "$cli_type" = "codex" ]; then
        auto_accept_codex_hooks_prompt_tmux "$pane_target" "$agent_id" "$cli_type" || true
        screen_content=$(tmux capture-pane -p -t "$pane_target" 2>/dev/null || true)
    fi

    local msg
    msg="$(bootstrap_delivery_prompt_tmux "$agent_id" "$bootstrap_file")"
    # -l: リテラル送信（日本語・特殊文字をキーシーケンスと誤解釈させない）
    # sleep: CLI がテキストをバッファに受け取ってから Enter を送る
    if ! tmux_send_text_and_enter "$pane_target" "$msg" "bootstrap delivery" "1"; then
        append_bootstrap_status_log "$agent_id" "$cli_type" "$pane_target" "bootstrap-send-failed" "text or enter send failed"
        return 1
    fi
    if ! confirm_cli_bootstrap_submitted_tmux "$pane_target" "$agent_id" "$cli_type" "bootstrap delivery"; then
        append_bootstrap_status_log "$agent_id" "$cli_type" "$pane_target" "bootstrap-send-failed" "CLI did not show submission activity"
        capture_bootstrap_diagnostic_tmux "$pane_target" "$agent_id" "$cli_type" "submission-unconfirmed"
        return 1
    fi
    rm -f "$pending_file"
    : > "$delivered_file"
    clear_runtime_blocker_tmux "$agent_id" "codex-auth-required" "Codex auth prompt cleared before bootstrap delivery."
    append_bootstrap_status_log "$agent_id" "$cli_type" "$pane_target" "bootstrap-submitted" "send-keys accepted and CLI activity observed"
}

wait_for_bootstrap_ready_tmux() {
    local timeout="${MAS_BOOTSTRAP_READY_TIMEOUT:-180}"
    local waited=0
    local total=0
    local ready=0
    local agent=""
    local pane_target=""
    local pending_file=""
    local delivered_file=""
    local screen_content=""
    local blocker_kind=""
    local _ready_cli=""

    # summaryはpending file数からreadyを推測せず、この関数が実際に確認した
    # ready:<agent> ack数を使う。MULTIAGENT_IDSにはKaroとAshigaruの双方が入る。
    CURRENT_BOOTSTRAP_READY_COUNT=0
    CURRENT_BOOTSTRAP_TOTAL_COUNT=0

    [ "${MAS_WAIT_FOR_BOOTSTRAP_READY_BEFORE_GOZA:-1}" = "1" ] || return 0
    [ "$SETUP_ONLY" = false ] || return 0

    local -a wait_agents=(shogun gunkan gunshi "${MULTIAGENT_IDS[@]}")
    for agent in "${wait_agents[@]}"; do
        # pane解決に失敗したroleも総数へ含める。存在しないagentを分母から消すと、
        # 残りだけreadyで起動完了と誤表示できてしまう。
        total=$((total + 1))
        case "$agent" in
            shogun) pane_target="${SHOGUN_TARGET:-}" ;;
            gunkan) pane_target="${GUNKAN_TARGET:-}" ;;
            gunshi) pane_target="${GUNSHI_TARGET:-}" ;;
            *) pane_target="${AGENT_PANES[$agent]:-}" ;;
        esac
        [ -n "$pane_target" ] || continue
        delivered_file="$SCRIPT_DIR/queue/runtime/bootstrap_${agent}.delivered"
        pending_file="$SCRIPT_DIR/queue/runtime/bootstrap_${agent}.pending"
    done

    [ "$total" -gt 0 ] || return 0
    CURRENT_BOOTSTRAP_TOTAL_COUNT="$total"

    log_info "⏳ 初動命令の処理完了を待機中（ready:agent ${total}件）..."
    while true; do
        ready=0
        for agent in "${wait_agents[@]}"; do
            case "$agent" in
                shogun) pane_target="${SHOGUN_TARGET:-}" ;;
                gunkan) pane_target="${GUNKAN_TARGET:-}" ;;
                gunshi) pane_target="${GUNSHI_TARGET:-}" ;;
                *) pane_target="${AGENT_PANES[$agent]:-}" ;;
            esac
            [ -n "$pane_target" ] || continue
            delivered_file="$SCRIPT_DIR/queue/runtime/bootstrap_${agent}.delivered"
            pending_file="$SCRIPT_DIR/queue/runtime/bootstrap_${agent}.pending"
            if bootstrap_acknowledged_tmux "$pane_target" "$agent"; then
                ready=$((ready + 1))
                _ready_cli=$(tmux show-options -p -t "$pane_target" -v @agent_cli 2>/dev/null || echo "unknown")
                mark_bootstrap_ready_tmux "$pane_target" "$agent" "$_ready_cli"
            fi
        done
        CURRENT_BOOTSTRAP_READY_COUNT="$ready"

        if [ "$ready" -ge "$total" ]; then
            log_success "  └─ 初動命令処理完了（${ready}/${total} ready）"
            return 0
        fi

        if [[ "$timeout" =~ ^[0-9]+$ ]] && [ "$timeout" -gt 0 ] && [ "$waited" -ge "$timeout" ]; then
            log_info "⚠️  初動命令 ready 待機はタイムアウト（${ready}/${total} ready）。御座の間へ移動します"
            for agent in "${wait_agents[@]}"; do
                case "$agent" in
                    shogun) pane_target="${SHOGUN_TARGET:-}" ;;
                    gunkan) pane_target="${GUNKAN_TARGET:-}" ;;
                    gunshi) pane_target="${GUNSHI_TARGET:-}" ;;
                    *) pane_target="${AGENT_PANES[$agent]:-}" ;;
                esac
                [ -n "$pane_target" ] || continue
                bootstrap_acknowledged_tmux "$pane_target" "$agent" && continue
                _ready_cli=$(tmux show-options -p -t "$pane_target" -v @agent_cli 2>/dev/null || echo "unknown")
                screen_content=$(tmux capture-pane -p -t "$pane_target" 2>/dev/null || true)
                blocker_kind="$(cli_startup_blocker_kind "$_ready_cli" "$screen_content")"
                capture_bootstrap_diagnostic_tmux "$pane_target" "$agent" "$_ready_cli" "${blocker_kind:-ready-ack-timeout}"
                append_bootstrap_status_log "$agent" "$_ready_cli" "$pane_target" "ready-ack-timeout" "ready:${agent} not observed"
            done
            return 0
        fi

        sleep 1
        waited=$((waited + 1))
    done
}

run_startup_bootstrap_delivery_flow() {
    local cli_ready_timeout="${MAS_CLI_READY_TIMEOUT:-15}"
    local _all_cli_ready=false
    local _ready_count=0
    local _total_count=0
    local _idx=""
    local _agent=""
    local _pane_target=""
    local _expected_cli=""
    local _shogun_cli=""
    local _gunkan_cli=""
    local _gunshi_cli=""
    local _agent_cli_type=""
    local _bootstrap_failed=0
    local i=0

    if ! [[ "$cli_ready_timeout" =~ ^[0-9]+$ ]]; then
        cli_ready_timeout=15
    fi
    echo "  エージェントCLIの起動を確認中（最大${cli_ready_timeout}秒、スクリーン内容判定）..."

    for ((i=1; i<=cli_ready_timeout; i++)); do
        _ready_count=0
        _total_count=0

        _shogun_cli=$(tmux show-options -p -t "$SHOGUN_TARGET" -v @agent_cli 2>/dev/null || echo "claude")
        _total_count=$((_total_count + 1))
        if wait_for_cli_ready_tmux "$SHOGUN_TARGET" "$_shogun_cli" 0 2>/dev/null; then
            _ready_count=$((_ready_count + 1))
        fi

        _gunkan_cli=$(tmux show-options -p -t "$GUNKAN_TARGET" -v @agent_cli 2>/dev/null || echo "claude")
        _total_count=$((_total_count + 1))
        if wait_for_cli_ready_tmux "$GUNKAN_TARGET" "$_gunkan_cli" 0 2>/dev/null; then
            _ready_count=$((_ready_count + 1))
        fi

        _gunshi_cli=$(tmux show-options -p -t "$GUNSHI_TARGET" -v @agent_cli 2>/dev/null || echo "claude")
        _total_count=$((_total_count + 1))
        if wait_for_cli_ready_tmux "$GUNSHI_TARGET" "$_gunshi_cli" 0 2>/dev/null; then
            _ready_count=$((_ready_count + 1))
        fi

        for _idx in "${!MULTIAGENT_IDS[@]}"; do
            _agent="${MULTIAGENT_IDS[$_idx]}"
            _pane_target="${AGENT_PANES[$_agent]:-}"
            [ -n "$_pane_target" ] || continue
            _expected_cli=$(tmux show-options -p -t "$_pane_target" -v @agent_cli 2>/dev/null || echo "claude")
            _total_count=$((_total_count + 1))
            if wait_for_cli_ready_tmux "$_pane_target" "$_expected_cli" 0 2>/dev/null; then
                _ready_count=$((_ready_count + 1))
            fi
        done

        if [ "$_ready_count" -ge "$_total_count" ] && [ "$_total_count" -gt 0 ]; then
            echo "  └─ ${_ready_count}/${_total_count} エージェントCLI起動を確認（${i}秒）"
            _all_cli_ready=true
            break
        fi
        sleep 1
    done

    if [ "$_all_cli_ready" != true ]; then
        log_info "⚠️  一部CLIの起動確認は未完了（タイムアウト）ですが、deliver_bootstrap_tmux で個別待機します"
    fi

    log_info "📜 初動命令をエージェント毎に個別配信中（CLI ready確認つき）"
    for _idx in "${!MULTIAGENT_IDS[@]}"; do
        _agent="${MULTIAGENT_IDS[$_idx]}"
        _agent_cli_type="${MULTIAGENT_CLI[$_agent]:-claude}"
        _pane_target="${AGENT_PANES[$_agent]:-}"
        if [ -z "$_pane_target" ]; then
            echo "[WARN] pane target unresolved for $_agent, skipping bootstrap" >&2
            continue
        fi
        if ! deliver_bootstrap_tmux "$_pane_target" "$_agent" "$_agent_cli_type"; then
            _bootstrap_failed=1
        fi
    done
    if ! deliver_bootstrap_tmux "$GUNSHI_TARGET" "gunshi" "$_gunshi_cli_type"; then
        _bootstrap_failed=1
    fi
    if ! deliver_bootstrap_tmux "$GUNKAN_TARGET" "gunkan" "$_gunkan_cli_type"; then
        _bootstrap_failed=1
    fi
    if ! deliver_bootstrap_tmux "$SHOGUN_TARGET" "shogun" "$_shogun_cli_type"; then
        _bootstrap_failed=1
    fi
    tmux select-pane -t "$SHOGUN_TARGET" >/dev/null 2>&1 || true
    if [ "$_bootstrap_failed" -ne 0 ]; then
        log_info "⚠️  一部エージェントは bootstrap 未配信のまま継続（詳細: queue/runtime/goza_bootstrap_*.log）"
    fi
    log_info "📜 初動命令の配信完了"
    wait_for_bootstrap_ready_tmux
}

should_embed_startup_prompt_in_cli_command() {
    local cli_type="${1:-}"
    local mode
    local default_mode

    # CLI ごとにembed 可否と既定mode を分ける (acceptance 5)。
    # codex/claude は起動argv へ初動命令を直接渡し、send-keys fallback は外部fileを
    # 権威として読むよう要求しない。それ以外は従来どおり embedded しない。
    case "$cli_type" in
        codex)
            default_mode="argv"
            ;;
        claude)
            # acceptance 5: Claude startup command に bootstrap 本文を argv 直接渡す。
            # これにより Claude が外部 bootstrap を prompt injection として拒否するのを
            # 回避する (前回 system matrix B の Claude Shogun 拒否原因)。
            default_mode="argv"
            ;;
        *)
            return 1
            ;;
    esac

    if [ "$cli_type" = "codex" ]; then
        mode="$(printf '%s' "${MAS_CODEX_STARTUP_PROMPT_MODE:-$default_mode}" | tr '[:upper:]' '[:lower:]')"
    elif [ "$cli_type" = "claude" ]; then
        mode="$(printf '%s' "${MAS_CLAUDE_STARTUP_PROMPT_MODE:-$default_mode}" | tr '[:upper:]' '[:lower:]')"
    else
        mode="$default_mode"
    fi

    case "$mode" in
        argv|arg|args|inline|positional)
            return 0
            ;;
        *)
            return 1
            ;;
    esac
}
