#!/usr/bin/env bash
# Shogunate MOD runtime prompt handling helpers.

codex_prompt_compact_text_tmux() {
    printf '%s' "${1:-}" | tr '[:upper:]' '[:lower:]' | tr -cd '[:alnum:]'
}

codex_usage_limit_prompt_detected_tmux() {
    local compact_text
    compact_text="$(codex_prompt_compact_text_tmux "${1:-}")"
    [[ "$compact_text" == *"youvehityourusagelimit"* || "$compact_text" == *"tryagainat"* ]]
}

codex_usage_limit_switchable_tmux() {
    local compact_text
    compact_text="$(codex_prompt_compact_text_tmux "${1:-}")"
    [[ "$compact_text" == *"gpt51codexmini"* || "$compact_text" == *"switchto"*mini* || "$compact_text" == *"1switch"* ]]
}

codex_switch_confirm_prompt_detected_tmux() {
    local compact_text
    compact_text="$(codex_prompt_compact_text_tmux "${1:-}")"
    [[ "$compact_text" == *"pressentertoconfirm"* || "$compact_text" == *"esctogoback"* ]] || return 1
    [[ "$compact_text" == *"switchto"* || "$compact_text" == *"optimizedforcodex"* ]] || return 1
    [[ "$compact_text" == *"gpt51"* || "$compact_text" == *"mini"* || "$compact_text" == *"optimizedforcodex"* ]]
}

codex_rate_limit_prompt_detected_tmux() {
    local compact_text
    compact_text="$(codex_prompt_compact_text_tmux "${1:-}")"
    [[ "$compact_text" == *"approachingratelimits"* || "$compact_text" == *"keepcurrentmodel"* || "$compact_text" == *"hidefutureratelimit"* ]]
}

codex_hooks_no_hooks_screen_detected_tmux() {
    local compact_text
    compact_text="$(codex_prompt_compact_text_tmux "${1:-}")"
    [[ "$compact_text" == *"nohooksinstalledforthisevent"* ]]
}

codex_hooks_overview_screen_detected_tmux() {
    local compact_text
    compact_text="$(codex_prompt_compact_text_tmux "${1:-}")"
    [[ "$compact_text" == *"lifecyclehooksfromconfigandenabledplugins"* || "$compact_text" == *"pressentertoviewhooks"* ]]
}

codex_hooks_trust_all_shortcut_detected_tmux() {
    local compact_text
    compact_text="$(codex_prompt_compact_text_tmux "${1:-}")"
    [[ "$compact_text" == *"pressttotrustall"* ]]
}

codex_hooks_review_prompt_detected_tmux() {
    local compact_text
    compact_text="$(codex_prompt_compact_text_tmux "${1:-}")"
    [[ "$compact_text" == *"hooksneedreview"* || "$compact_text" == *"trustallandcontinue"* ]]
}

codex_ready_prompt_detected_tmux() {
    local screen_content="${1:-}"
    printf '%s' "$screen_content" | grep -qiE '(openai codex|/model to change|Use /skills|Tip:|Working|esc to interrupt|% left|context left)'
}

codex_pasted_content_pending_tmux() {
    local screen_content="${1:-}"
    printf '%s' "$screen_content" | grep -qi 'pasted content'
}

confirm_codex_pasted_content_tmux() {
    local pane_target="$1"
    local agent_id="$2"
    local action_label="${3:-Codex pasted content confirm}"
    local screen_content=""

    screen_content=$(tmux capture-pane -p -t "$pane_target" 2>/dev/null | tail -40 || true)
    codex_pasted_content_pending_tmux "$screen_content" || return 0

    echo "[INFO] ${action_label}: confirming pasted content for ${agent_id} (${pane_target})" >&2
    if ! tmux_send_enter_only "$pane_target" "$action_label"; then
        return 1
    fi

    sleep 0.3
    screen_content=$(tmux capture-pane -p -t "$pane_target" 2>/dev/null | tail -40 || true)
    if codex_pasted_content_pending_tmux "$screen_content"; then
        echo "[WARN] ${action_label}: pasted content still pending for ${agent_id} (${pane_target})" >&2
        return 1
    fi

    return 0
}

codex_bootstrap_input_visible_tmux() {
    local screen_content="${1:-}"
    local agent_id="${2:-}"
    [ -n "$agent_id" ] || return 1
    printf '%s' "$screen_content" | grep -qiE "【初動命令】あなたは${agent_id}|【初動命令】|イベント駆動規則|連携順序:|準備が整ったら未読inbox監視へ戻れ"
}

bootstrap_delivery_prompt_tmux() {
    local agent_id="$1"
    local bootstrap_file="$2"

    printf "【初動命令】あなたは%s。詳細正本は %s に保存済み。起動直後は読まず、実タスク/未読inbox/直接指示を受けた時だけ必要最小範囲を読め。今は追加探索せず ready:%s を1行だけ送信し、イベント駆動で待機せよ。" \
        "$agent_id" "$bootstrap_file" "$agent_id"
}

codex_bootstrap_delivery_prompt_tmux() {
    bootstrap_delivery_prompt_tmux "$@"
}

codex_bootstrap_activity_visible_tmux() {
    local screen_content="${1:-}"
    local agent_id="${2:-}"
    local filtered_content=""

    bootstrap_acknowledged_tmux "" "$agent_id" "$screen_content" && return 0
    filtered_content="$(printf '%s\n' "$screen_content" | grep -v '【初動命令】' || true)"
    printf '%s' "$filtered_content" | grep -qiE '(Working|esc to interrupt|^• |^[[:space:]]*└ |Ran |Explored|Read )'
}

confirm_codex_bootstrap_submitted_tmux() {
    local pane_target="$1"
    local agent_id="$2"
    local action_label="${3:-Codex bootstrap submit confirm}"
    local screen_content=""
    local attempt

    if ! confirm_codex_pasted_content_tmux "$pane_target" "$agent_id" "$action_label"; then
        return 1
    fi

    for attempt in 1 2 3; do
        sleep 1
        screen_content=$(tmux capture-pane -p -t "$pane_target" 2>/dev/null | tail -60 || true)
        if codex_bootstrap_activity_visible_tmux "$screen_content" "$agent_id"; then
            return 0
        fi
        if codex_bootstrap_input_visible_tmux "$screen_content" "$agent_id"; then
            echo "[INFO] ${action_label}: bootstrap still visible in composer for ${agent_id}; sending Enter (${attempt})" >&2
        else
            echo "[INFO] ${action_label}: Codex bootstrap not active yet for ${agent_id}; sending Enter (${attempt})" >&2
        fi
        tmux_send_enter_only "$pane_target" "$action_label" || return 1
    done

    screen_content=$(tmux capture-pane -p -t "$pane_target" 2>/dev/null | tail -60 || true)
    if codex_bootstrap_activity_visible_tmux "$screen_content" "$agent_id"; then
        return 0
    fi
    if codex_bootstrap_input_visible_tmux "$screen_content" "$agent_id"; then
        echo "[WARN] ${action_label}: bootstrap still appears unsubmitted for ${agent_id} (${pane_target})" >&2
        return 1
    fi

    echo "[WARN] ${action_label}: Codex bootstrap did not show activity for ${agent_id} (${pane_target})" >&2
    return 1
}

auto_accept_antigravity_trust_prompt_tmux() {
    local pane_target="$1"
    local agent_id="$2"
    local cli_type="$3"
    local i
    local pane_text

    [ "$cli_type" = "antigravity" ] || return 0

    for i in {1..20}; do
        pane_text="$(tmux capture-pane -p -t "$pane_target" 2>/dev/null | tail -60 || true)"
        if echo "$pane_text" | grep -q "Do you trust this folder"; then
            tmux_send_text_and_enter "$pane_target" "1" "Antigravity trust prompt" || return 1
            log_info "  └─ ${agent_id}: Antigravity trust prompt を自動承認"
            sleep 1
            return 0
        fi
        sleep 1
    done
    return 0
}

auto_retry_antigravity_busy_tmux() {
    local pane_target="$1"
    local agent_id="$2"
    local cli_type="$3"
    local i
    local pane_text

    [ "$cli_type" = "antigravity" ] || return 0

    for i in {1..20}; do
        pane_text="$(tmux capture-pane -p -t "$pane_target" 2>/dev/null | tail -80 || true)"
        if echo "$pane_text" | grep -q "We are currently experiencing high demand"; then
            tmux_send_text_and_enter "$pane_target" "1" "Antigravity high-demand retry" || return 1
            log_info "  └─ ${agent_id}: Antigravity high-demand を自動再試行"
            sleep 2
            return 0
        fi
        sleep 1
    done
    return 0
}

auto_skip_codex_update_prompt_tmux() {
    local pane_target="$1"
    local agent_id="$2"
    local cli_type="$3"
    local i
    local pane_text

    [ "$cli_type" = "codex" ] || return 0

    for i in {1..20}; do
        pane_text="$(tmux capture-pane -p -t "$pane_target" 2>/dev/null | tail -80 || true)"
        if echo "$pane_text" | grep -qiE "Update available|Update now|Skip until next version|Skip this version|Would you like to update"; then
            tmux_send_text_and_enter "$pane_target" "2" "Codex update prompt" || return 1
            sleep 2
            pane_text="$(tmux capture-pane -p -t "$pane_target" 2>/dev/null | tail -80 || true)"
            if echo "$pane_text" | grep -qiE "Update available|Update now|Skip until next version|Skip this version|Would you like to update"; then
                tmux send-keys -t "$pane_target" Down >/dev/null 2>&1 || {
                    echo "[WARN] Codex update prompt: Down send failed for ${pane_target}" >&2
                    return 1
                }
                tmux send-keys -t "$pane_target" Enter >/dev/null 2>&1 || {
                    echo "[WARN] Codex update prompt: Enter send failed for ${pane_target}" >&2
                    return 1
                }
            fi
            log_info "  └─ ${agent_id}: Codex update prompt を自動スキップ"
            sleep 1
            return 0
        fi
        sleep 1
    done
    return 0
}

opencode_update_prompt_detected_tmux() {
    local screen_content="${1:-}"

    printf '%s' "$screen_content" | grep -qiE 'Update Available|A new release .* is available|Would you like to update now\?|Skip[[:space:]]+Confirm'
}

auto_skip_opencode_update_prompt_tmux() {
    local pane_target="$1"
    local agent_id="$2"
    local cli_type="$3"
    local i
    local pane_text

    [ "$cli_type" = "opencode" ] || return 0

    for i in {1..20}; do
        pane_text="$(tmux capture-pane -p -t "$pane_target" 2>/dev/null | tail -100 || true)"
        if opencode_update_prompt_detected_tmux "$pane_text"; then
            tmux_send_enter_only "$pane_target" "OpenCode update prompt" || return 1
            log_info "  └─ ${agent_id}: OpenCode update prompt を自動スキップ"
            sleep 2
            return 0
        fi
        sleep 1
    done
    return 0
}

auto_accept_codex_workspace_trust_prompt_tmux() {
    local pane_target="$1"
    local agent_id="$2"
    local cli_type="$3"
    local i
    local pane_text

    [ "$cli_type" = "codex" ] || return 0

    for i in {1..20}; do
        pane_text="$(tmux capture-pane -p -t "$pane_target" 2>/dev/null | tail -80 || true)"
        if echo "$pane_text" | grep -qiE "Do you trust the contents of this directory|1\\. Yes, continue|2\\. No, quit"; then
            tmux_send_text_and_enter "$pane_target" "1" "Codex workspace trust prompt" || return 1
            log_info "  └─ ${agent_id}: Codex workspace trust prompt を自動承認"
            sleep 2
            return 0
        fi
        sleep 1
    done
    return 0
}

auto_accept_codex_hooks_prompt_tmux() {
    local pane_target="$1"
    local agent_id="$2"
    local cli_type="$3"
    local i
    local pane_text
    local handled=0
    local max_wait="${MAS_CODEX_HOOKS_PROMPT_WAIT:-5}"

    [ "$cli_type" = "codex" ] || return 0

    for ((i=1; i<=max_wait; i++)); do
        pane_text="$(tmux capture-pane -p -t "$pane_target" 2>/dev/null | tail -120 || true)"
        if codex_hooks_no_hooks_screen_detected_tmux "$pane_text" || codex_hooks_overview_screen_detected_tmux "$pane_text"; then
            tmux send-keys -t "$pane_target" Escape >/dev/null 2>&1 || {
                echo "[WARN] Codex hooks screen: Escape send failed for ${pane_target}" >&2
                return 1
            }
            handled=1
            log_info "  └─ ${agent_id}: Codex hooks detail 画面を閉じる"
            sleep 1
            continue
        fi
        if codex_hooks_trust_all_shortcut_detected_tmux "$pane_text"; then
            tmux send-keys -t "$pane_target" t >/dev/null 2>&1 || {
                echo "[WARN] Codex hooks prompt: trust-all shortcut failed for ${pane_target}" >&2
                return 1
            }
            handled=1
            log_info "  └─ ${agent_id}: Codex hooks を trust all で承認"
            sleep 1
            continue
        fi
        if codex_hooks_review_prompt_detected_tmux "$pane_text"; then
            tmux_send_text_and_enter "$pane_target" "2" "Codex hooks review prompt" || return 1
            handled=1
            log_info "  └─ ${agent_id}: Codex hooks review prompt を trust all で承認"
            sleep 1
            continue
        fi
        [ "$handled" = "1" ] && return 0
        sleep 1
    done
    return 0
}

auto_dismiss_codex_rate_limit_prompt_tmux() {
    local pane_target="$1"
    local agent_id="$2"
    local cli_type="$3"
    local i
    local pane_text

    [ "$cli_type" = "codex" ] || return 0

    for i in {1..45}; do
        pane_text="$(tmux capture-pane -p -t "$pane_target" 2>/dev/null | tail -120 || true)"
        if codex_usage_limit_prompt_detected_tmux "$pane_text"; then
            if ! codex_usage_limit_switchable_tmux "$pane_text"; then
                record_runtime_blocker_tmux "$agent_id" "codex-hard-usage-limit" "$pane_text"
                log_info "  └─ ${agent_id}: Codex hard usage-limit prompt を検知（mini切替不可のため自動入力せず待機）"
                return 0
            fi
            clear_runtime_blocker_tmux "$agent_id" "codex-hard-usage-limit" "$pane_text"
            tmux_send_text_and_enter "$pane_target" "1" "Codex usage-limit prompt" || return 1
            log_info "  └─ ${agent_id}: Codex usage-limit prompt で mini へ自動切替"
            sleep 2
            return 0
        fi
        clear_runtime_blocker_tmux "$agent_id" "codex-hard-usage-limit" "$pane_text"
        if codex_switch_confirm_prompt_detected_tmux "$pane_text"; then
            tmux_send_enter_only "$pane_target" "Codex switch-confirm prompt" || return 1
            log_info "  └─ ${agent_id}: Codex switch-confirm prompt を Enter で確定"
            sleep 2
            return 0
        fi
        if codex_rate_limit_prompt_detected_tmux "$pane_text"; then
            tmux_send_text_and_enter "$pane_target" "3" "Codex rate-limit prompt" || return 1
            log_info "  └─ ${agent_id}: Codex rate-limit prompt を自動dismiss"
            sleep 2
            return 0
        fi
        sleep 1
    done
    return 0
}

codex_auth_prompt_detected_tmux() {
    local pane_target="$1"
    local pane_text

    pane_text="$(tmux capture-pane -p -t "$pane_target" 2>/dev/null | tail -120 || true)"
    echo "$pane_text" | grep -qiE "Finish signing in via your browser|open the following link to authenticate|Sign in with ChatGPT|Sign in with Device Code|Provide your own API key|auth\\.openai\\.com/oauth/authorize|Login server error: Login cancelled|account/login/start failed|failed to start login server"
}

opencode_project_prompt_detected_tmux() {
    local pane_target="$1"
    local pane_text

    pane_text="$(tmux capture-pane -p -t "$pane_target" 2>/dev/null | tail -80 || true)"
    echo "$pane_text" | grep -qiE "What is this project\\?|What is the project\\?|project\\?\""
}

auto_accept_opencode_project_prompt_tmux() {
    local pane_target="$1"
    local agent_id="$2"

    opencode_project_prompt_detected_tmux "$pane_target" || return 0
    tmux_send_enter_only "$pane_target" "OpenCode project prompt" || return 1
    log_info "  └─ ${agent_id}: OpenCode project prompt を既定値で通過"
    sleep 2
    return 0
}
