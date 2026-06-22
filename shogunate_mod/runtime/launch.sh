tmux_send_text_and_enter() {
    local pane_target="$1"
    local text="$2"
    local action_label="${3:-tmux send-keys}"
    local literal_mode="${4:-0}"

    if [ "$literal_mode" = "1" ]; then
        tmux send-keys -l -t "$pane_target" "$text" >/dev/null 2>&1 || {
            echo "[WARN] ${action_label}: text send failed for ${pane_target}" >&2
            return 1
        }
    else
        tmux send-keys -t "$pane_target" "$text" >/dev/null 2>&1 || {
            echo "[WARN] ${action_label}: text send failed for ${pane_target}" >&2
            return 1
        }
    fi

    sleep 0.3
    tmux send-keys -t "$pane_target" Enter >/dev/null 2>&1 || {
        echo "[WARN] ${action_label}: Enter send failed for ${pane_target}" >&2
        return 1
    }

    return 0
}

tmux_send_enter_only() {
    local pane_target="$1"
    local action_label="${2:-tmux send-keys}"

    tmux send-keys -t "$pane_target" Enter >/dev/null 2>&1 || {
        echo "[WARN] ${action_label}: Enter send failed for ${pane_target}" >&2
        return 1
    }

    return 0
}

write_agent_launch_script() {
    local agent_id="$1"
    local launch_cmd="$2"
    local safe_agent
    local script_path

    safe_agent="$(printf '%s' "$agent_id" | tr -c 'A-Za-z0-9_.-' '_')"
    script_path="$SCRIPT_DIR/queue/runtime/launch_${safe_agent}.sh"
    mkdir -p "$SCRIPT_DIR/queue/runtime"
    {
        printf '#!/usr/bin/env bash\n'
        printf 'set -uo pipefail\n'
        printf 'export SHOGUNATE_RUNTIME_DIR=%q\n' "$SCRIPT_DIR"
        printf 'export SHOGUNATE_PROJECT_DIR=%q\n' "$SHOGUNATE_PROJECT_DIR"
        printf 'cd %q\n' "$SHOGUNATE_PROJECT_DIR"
        printf '%s\n' "$launch_cmd"
        printf 'status=$?\n'
        printf 'if [ -n "${TMUX_PANE:-}" ]; then tmux set-option -p -t "$TMUX_PANE" @agent_cli_running 0 >/dev/null 2>&1 || true; fi\n'
        printf 'echo "[Shogunate] %s CLI exited with status ${status}"\n' "$agent_id"
        printf 'exec bash -i\n'
    } > "$script_path"
    chmod 700 "$script_path" 2>/dev/null || true
    printf '%s\n' "$script_path"
}

launch_agent_cli_pane_or_die() {
    local pane_target="$1"
    local agent_id="$2"
    local launch_cmd="$3"
    local action_label="$4"
    local script_path
    local script_quoted

    script_path="$(write_agent_launch_script "$agent_id" "$launch_cmd")"
    printf -v script_quoted '%q' "$script_path"
    tmux set-option -p -t "$pane_target" @agent_cli_running 1 >/dev/null 2>&1 || true
    tmux respawn-pane -k -t "$pane_target" "bash $script_quoted" >/dev/null 2>&1 || {
        echo "[ERROR] ${action_label}: respawn-pane failed for ${pane_target}" >&2
        exit 1
    }
}

agent_launch_shell_command() {
    local agent_id="$1"
    local launch_cmd="$2"
    local script_path

    script_path="$(write_agent_launch_script "$agent_id" "$launch_cmd")"
    printf 'bash %q' "$script_path"
}

tmux_send_text_and_enter_or_die() {
    local pane_target="$1"
    local text="$2"
    local action_label="$3"
    local literal_mode="${4:-0}"

    if ! tmux_send_text_and_enter "$pane_target" "$text" "$action_label" "$literal_mode"; then
        echo "[ERROR] ${action_label}: delivery failed for ${pane_target}" >&2
        exit 1
    fi
}

mark_cli_launch_attempt_tmux() {
    local pane_target="$1"
    tmux set-option -p -t "$pane_target" @cli_launch_epoch "$(date +%s)" >/dev/null 2>&1 || true
}

wait_for_goza_client_before_cli_launch() {
    local timeout="${MAS_WAIT_FOR_GOZA_CLIENT_TIMEOUT:-300}"
    local waited=0

    [ "${MAS_WAIT_FOR_GOZA_CLIENT_BEFORE_CLI:-0}" = "1" ] || return 0
    [ "$SETUP_ONLY" = false ] || return 0

    log_info "🖥️  御座の間 attach 待機中（CLIは表示端末接続後に起動）..."
    while ! tmux list-clients -t "$GOZA_SESSION_NAME" -F '#{client_name}' 2>/dev/null | grep -q .; do
        sleep 1
        waited=$((waited + 1))
        if [[ "$timeout" =~ ^[0-9]+$ ]] && [ "$timeout" -gt 0 ] && [ "$waited" -ge "$timeout" ]; then
            echo "[ERROR] Shogunate attach wait timed out after ${timeout}s" >&2
            echo "        Attach manually or disable MAS_WAIT_FOR_GOZA_CLIENT_BEFORE_CLI." >&2
            exit 1
        fi
    done
    log_success "  └─ 御座の間 attach 検出。CLI起動を開始"
}

launch_all_agent_clis_tmux() {
    local _shogun_cmd=""
    local _gunkan_cmd=""
    local _gunshi_cmd=""
    local _shogun_startup_prompt=""
    local _gunkan_startup_prompt=""
    local _gunshi_startup_prompt=""
    local _idx=""
    local _agent=""
    local _is_karo_agent=false
    local _agent_cli_type=""
    local _agent_cmd=""
    local _agent_startup_prompt=""
    local _ashi_num=""
    local _pane_target=""
    local _agent_display=""
    local _launch_line=""
    local _karo_launched=0
    local _ashigaru_launched=0
    local _cli_gate_pids=()
    local _pid=""
    local _pane_cli=""
    local -a _karo_launch_lines=()
    local -a _ashigaru_launch_lines=()

    declare -g _shogun_cli_type="claude"
    declare -g _gunkan_cli_type="claude"
    declare -g _gunshi_cli_type="claude"
    declare -gA MULTIAGENT_CLI=()

    wait_for_goza_client_before_cli_launch

    # CLI の存在チェック（Multi-CLI対応）
    if [ "$CLI_ADAPTER_LOADED" = true ]; then
        if ! get_first_available_cli >/dev/null 2>&1; then
            echo "[ERROR] No supported CLI found. Install one of: claude, codex, agy, localapi, copilot, kimi" >&2
            exit 1
        fi
    else
        if ! command -v claude &> /dev/null; then
            log_info "⚠️  claude コマンドが見つかりません"
            echo "  shogunate_mod/package/first_setup.sh を再実行してください:"
            echo "    bash shogunate_mod/package/first_setup.sh"
            exit 1
        fi
    fi

    log_war "👑 全エージェントCLIを起動中..."
    : > "$SCRIPT_DIR/queue/runtime/agent_cli.tsv"

    # CLI起動前にファイルを書き出すことで、レースコンディションを排除
    log_info "📝 ブートストラップファイルを事前生成中"

    _shogun_cmd="claude --model opus $PERMISSION_FLAG"
    if [ "$CLI_ADAPTER_LOADED" = true ]; then
        _shogun_cli_type=$(resolve_cli_type_for_agent "shogun")
        _shogun_cmd=$(build_cli_command_with_type "shogun" "$_shogun_cli_type")
    fi
    tmux set-option -p -t "$SHOGUN_TARGET" @agent_cli "$_shogun_cli_type"
    generate_bootstrap_file "shogun" "$_shogun_cli_type"
    if [ "$CLI_ADAPTER_LOADED" = true ]; then
        _shogun_startup_prompt="$(bootstrap_message_text "shogun" || true)"
        if [ -n "$_shogun_startup_prompt" ] && should_embed_startup_prompt_in_cli_command "$_shogun_cli_type"; then
            _shogun_cmd=$(build_cli_command_with_startup_prompt "shogun" "$_shogun_cli_type" "$_shogun_startup_prompt")
        fi
    fi
    printf "shogun\t%s\n" "$_shogun_cli_type" >> "$SCRIPT_DIR/queue/runtime/agent_cli.tsv"
    if [ "$SHOGUN_NO_THINKING" = true ] && [ "$_shogun_cli_type" = "claude" ]; then
        launch_agent_cli_pane_or_die "$SHOGUN_TARGET" "shogun" "MAX_THINKING_TOKENS=0 $_shogun_cmd" "shogun CLI launch"
        mark_cli_launch_attempt_tmux "$SHOGUN_TARGET"
        tmux set-option -p -t "$SHOGUN_TARGET" @model_name "$(resolve_model_display_name "shogun")"
        log_info "  └─ 将軍（$(resolve_cli_summary "shogun" "$_shogun_cli_type") / thinking無効）、召喚完了"
    else
        launch_agent_cli_pane_or_die "$SHOGUN_TARGET" "shogun" "$_shogun_cmd" "shogun CLI launch"
        mark_cli_launch_attempt_tmux "$SHOGUN_TARGET"
        tmux set-option -p -t "$SHOGUN_TARGET" @model_name "$(resolve_model_display_name "shogun")"
        log_info "  └─ 将軍（$(resolve_cli_summary "shogun" "$_shogun_cli_type")）、召喚完了"
    fi

    _gunkan_cmd="claude --model opus --effort max $PERMISSION_FLAG"
    if [ "$CLI_ADAPTER_LOADED" = true ]; then
        _gunkan_cli_type=$(resolve_cli_type_for_agent "gunkan")
        _gunkan_cmd=$(build_cli_command_with_type "gunkan" "$_gunkan_cli_type")
    fi
    tmux set-option -p -t "$GUNKAN_TARGET" @agent_cli "$_gunkan_cli_type"
    generate_bootstrap_file "gunkan" "$_gunkan_cli_type"
    if [ "$CLI_ADAPTER_LOADED" = true ]; then
        _gunkan_startup_prompt="$(bootstrap_message_text "gunkan" || true)"
        if [ -n "$_gunkan_startup_prompt" ] && should_embed_startup_prompt_in_cli_command "$_gunkan_cli_type"; then
            _gunkan_cmd=$(build_cli_command_with_startup_prompt "gunkan" "$_gunkan_cli_type" "$_gunkan_startup_prompt")
        fi
    fi
    printf "gunkan\t%s\n" "$_gunkan_cli_type" >> "$SCRIPT_DIR/queue/runtime/agent_cli.tsv"
    launch_agent_cli_pane_or_die "$GUNKAN_TARGET" "gunkan" "$_gunkan_cmd" "gunkan CLI launch"
    mark_cli_launch_attempt_tmux "$GUNKAN_TARGET"
    tmux set-option -p -t "$GUNKAN_TARGET" @model_name "$(resolve_model_display_name "gunkan")"
    log_info "  └─ 軍監（$(resolve_cli_summary "gunkan" "$_gunkan_cli_type")）、召喚完了"

    _gunshi_cmd="claude --model opus --effort max $PERMISSION_FLAG"
    if [ "$CLI_ADAPTER_LOADED" = true ]; then
        _gunshi_cli_type=$(resolve_cli_type_for_agent "gunshi")
        _gunshi_cmd=$(build_cli_command_with_type "gunshi" "$_gunshi_cli_type")
    fi
    tmux set-option -p -t "$GUNSHI_TARGET" @agent_cli "$_gunshi_cli_type"
    generate_bootstrap_file "gunshi" "$_gunshi_cli_type"
    if [ "$CLI_ADAPTER_LOADED" = true ]; then
        _gunshi_startup_prompt="$(bootstrap_message_text "gunshi" || true)"
        if [ -n "$_gunshi_startup_prompt" ] && should_embed_startup_prompt_in_cli_command "$_gunshi_cli_type"; then
            _gunshi_cmd=$(build_cli_command_with_startup_prompt "gunshi" "$_gunshi_cli_type" "$_gunshi_startup_prompt")
        fi
    fi
    printf "gunshi\t%s\n" "$_gunshi_cli_type" >> "$SCRIPT_DIR/queue/runtime/agent_cli.tsv"
    launch_agent_cli_pane_or_die "$GUNSHI_TARGET" "gunshi" "$_gunshi_cmd" "gunshi CLI launch"
    mark_cli_launch_attempt_tmux "$GUNSHI_TARGET"
    tmux set-option -p -t "$GUNSHI_TARGET" @model_name "$(resolve_model_display_name "gunshi")"
    log_info "  └─ 軍師（$(resolve_cli_summary "gunshi" "$_gunshi_cli_type")）、召喚完了"

    sleep 1

    for _idx in "${!MULTIAGENT_IDS[@]}"; do
        _agent="${MULTIAGENT_IDS[$_idx]}"
        _is_karo_agent=false
        if [[ "$_agent" == karo* ]]; then
            _is_karo_agent=true
            _agent_cli_type="claude"
            _agent_cmd="claude --model opus --effort max $PERMISSION_FLAG"
            if [ "$CLI_ADAPTER_LOADED" = true ]; then
                _agent_cli_type=$(resolve_cli_type_for_agent "$_agent")
                _agent_cmd=$(build_cli_command_with_type "$_agent" "$_agent_cli_type")
            fi
            _karo_launched=$((_karo_launched + 1))
        else
            _ashi_num="${_agent#ashigaru}"
            _agent_cli_type="claude"
            if [ "$KESSEN_MODE" = true ]; then
                _agent_cmd="claude --model opus --effort max $PERMISSION_FLAG"
            elif [ "${_ashi_num:-0}" -le 4 ]; then
                _agent_cmd="claude --model sonnet --effort max $PERMISSION_FLAG"
            else
                _agent_cmd="claude --model opus --effort max $PERMISSION_FLAG"
            fi
            if [ "$CLI_ADAPTER_LOADED" = true ]; then
                _agent_cli_type=$(resolve_cli_type_for_agent "$_agent")
                if [ "$KESSEN_MODE" = true ] && [ "$_agent_cli_type" = "claude" ]; then
                    _agent_cmd="claude --model opus --effort max $PERMISSION_FLAG"
                else
                    _agent_cmd=$(build_cli_command_with_type "$_agent" "$_agent_cli_type")
                fi
            fi
            _ashigaru_launched=$((_ashigaru_launched + 1))
        fi

        _pane_target="${AGENT_PANES[$_agent]:-}"
        [ -n "$_pane_target" ] || continue
        tmux set-option -p -t "$_pane_target" @agent_cli "$_agent_cli_type"
        generate_bootstrap_file "$_agent" "$_agent_cli_type"
        if [ "$CLI_ADAPTER_LOADED" = true ]; then
            _agent_startup_prompt="$(bootstrap_message_text "$_agent" || true)"
            if [ -n "$_agent_startup_prompt" ] && should_embed_startup_prompt_in_cli_command "$_agent_cli_type"; then
                _agent_cmd=$(build_cli_command_with_startup_prompt "$_agent" "$_agent_cli_type" "$_agent_startup_prompt")
            fi
        fi
        launch_agent_cli_pane_or_die "$_pane_target" "$_agent" "$_agent_cmd" "${_agent} CLI launch"
        mark_cli_launch_attempt_tmux "$_pane_target"
        printf "%s\t%s\n" "$_agent" "$_agent_cli_type" >> "$SCRIPT_DIR/queue/runtime/agent_cli.tsv"
        MULTIAGENT_CLI["$_agent"]="$_agent_cli_type"
        tmux set-option -p -t "$_pane_target" @model_name "$(resolve_model_display_name "$_agent")"
        _agent_display="$_agent"
        if [[ "$_agent" =~ ^karo([1-9][0-9]*)$ ]]; then
            _agent_display="Karo${BASH_REMATCH[1]}"
        elif [[ "$_agent" == "karo" ]]; then
            _agent_display="Karo"
        fi
        _launch_line="    - ${_agent_display}（$(resolve_cli_summary "$_agent" "$_agent_cli_type")）、CLI起動完了"
        if [ "$_is_karo_agent" = true ]; then
            _karo_launch_lines+=("$_launch_line")
        else
            _ashigaru_launch_lines+=("$_launch_line")
        fi
    done
    log_info "  └─ 家老CLI起動明細:"
    for _launch_line in "${_karo_launch_lines[@]}"; do
        log_info "$_launch_line"
    done
    log_info "  └─ 家老（${_karo_launched}名）、召喚完了"
    log_info "  └─ 足軽CLI起動明細:"
    for _launch_line in "${_ashigaru_launch_lines[@]}"; do
        log_info "$_launch_line"
    done
    if [ "$KESSEN_MODE" = true ]; then
        log_info "  └─ 足軽（決戦の陣 / Claude系Opus優先: ${_ashigaru_launched}名）、配置完了"
    else
        log_info "  └─ 足軽（設定どおり: ${_ashigaru_launched}名）、配置完了"
    fi

    _cli_gate_handler() {
        local _pane="$1" _agent="$2" _cli="$3"
        auto_skip_codex_update_prompt_tmux "$_pane" "$_agent" "$_cli"
        auto_accept_codex_workspace_trust_prompt_tmux "$_pane" "$_agent" "$_cli"
        auto_accept_codex_hooks_prompt_tmux "$_pane" "$_agent" "$_cli"
        auto_dismiss_codex_rate_limit_prompt_tmux "$_pane" "$_agent" "$_cli"
        auto_skip_opencode_update_prompt_tmux "$_pane" "$_agent" "$_cli"
        auto_accept_antigravity_trust_prompt_tmux "$_pane" "$_agent" "$_cli"
        auto_retry_antigravity_busy_tmux "$_pane" "$_agent" "$_cli"
        auto_skip_antigravity_feedback_prompt_tmux "$_pane" "$_agent" "$_cli"
    }
    { _cli_gate_handler "$SHOGUN_TARGET" "shogun" "$_shogun_cli_type"; } 9>&- &
    _cli_gate_pids+=($!)
    { _cli_gate_handler "$GUNKAN_TARGET" "gunkan" "$_gunkan_cli_type"; } 9>&- &
    _cli_gate_pids+=($!)
    { _cli_gate_handler "$GUNSHI_TARGET" "gunshi" "$_gunshi_cli_type"; } 9>&- &
    _cli_gate_pids+=($!)
    for _idx in "${!MULTIAGENT_IDS[@]}"; do
        _agent="${MULTIAGENT_IDS[$_idx]}"
        _pane_target="${AGENT_PANES[$_agent]:-}"
        [ -n "$_pane_target" ] || continue
        _pane_cli=$(tmux show-options -p -t "$_pane_target" -v @agent_cli 2>/dev/null || echo "claude")
        { _cli_gate_handler "$_pane_target" "$_agent" "$_pane_cli"; } 9>&- &
        _cli_gate_pids+=($!)
    done
    for _pid in "${_cli_gate_pids[@]}"; do
        wait "$_pid" 2>/dev/null || true
    done

    if [ "$KESSEN_MODE" = true ]; then
        log_success "✅ 決戦の陣で出陣（Claude系Opus優先）"
    else
        log_success "✅ 設定どおりの陣容で出陣"
    fi
    echo ""
}

goza_startup_window_enabled() {
    [ "${MAS_GOZA_STARTUP_WINDOW:-0}" = "1" ] && [ "$SETUP_ONLY" = false ]
}

create_goza_startup_window() {
    local shell_cmd=""
    local startup_log="${MAS_GOZA_STARTUP_LOG:-queue/runtime/shogunate_runtime_launcher.log}"

    goza_startup_window_enabled || return 0
    printf -v shell_cmd 'cd %q && touch %q; tail -n +1 -F %q' "$SCRIPT_DIR" "$startup_log" "$startup_log"
    tmux new-window -d -t "$GOZA_SESSION_NAME" -n "$GOZA_STARTUP_WINDOW_NAME" "$shell_cmd" >/dev/null 2>&1 || return 0
    tmux select-window -t "$GOZA_SESSION_NAME:$GOZA_STARTUP_WINDOW_NAME" >/dev/null 2>&1 || true
}

create_goza_command_window() {
    local window_name="${MAS_GOZA_COMMAND_WINDOW_NAME:-departure}"
    local rcfile="$SCRIPT_DIR/queue/runtime/goza_command_shell.bashrc"
    local shell_cmd=""

    mkdir -p "$SCRIPT_DIR/queue/runtime"
    {
        printf '[[ -f ~/.bashrc ]] && source ~/.bashrc\n'
        if command -v shogunate_mod_shell_aliases_path >/dev/null 2>&1; then
            printf 'source %q\n' "$(shogunate_mod_shell_aliases_path "$SCRIPT_DIR")"
        else
            printf 'source %q/shogunate_mod/shell/aliases.sh\n' "$SCRIPT_DIR"
        fi
        printf 'cd %q\n' "$SHOGUNATE_PROJECT_DIR"
        printf 'echo "[Shogunate] Ready. Type cgo/CGO for Goza, CMA/cma for Multiagent, csa/CSA for Ashigaru."\n'
    } > "$rcfile"

    printf -v shell_cmd 'exec bash --rcfile %q -i' "$rcfile"
    if tmux list-windows -t "$GOZA_SESSION_NAME" -F '#{window_name}' 2>/dev/null | grep -Fxq "$window_name"; then
        tmux respawn-window -k -t "$GOZA_SESSION_NAME:$window_name" "$shell_cmd" >/dev/null 2>&1 || true
    else
        tmux new-window -d -t "$GOZA_SESSION_NAME" -n "$window_name" "$shell_cmd" >/dev/null 2>&1 || true
    fi
    printf '%s:%s' "$GOZA_SESSION_NAME" "$window_name"
}

finish_goza_startup_window() {
    local client=""
    local target="$GOZA_SESSION_NAME:$GOZA_WINDOW_NAME"

    goza_startup_window_enabled || return 0
    case "$(printf '%s' "${MAS_GOZA_FINISH_TARGET:-overview}" | tr '[:upper:]' '[:lower:]')" in
        command|shell|aliases|alias)
            target="$(create_goza_command_window)"
            ;;
    esac
    while IFS= read -r client; do
        [ -n "$client" ] || continue
        tmux switch-client -c "$client" -t "$target" >/dev/null 2>&1 || true
    done < <(tmux list-clients -t "$GOZA_SESSION_NAME" -F '#{client_name}' 2>/dev/null || true)
    tmux kill-window -t "$GOZA_SESSION_NAME:$GOZA_STARTUP_WINDOW_NAME" >/dev/null 2>&1 || true
}

codex_process_running_tmux() {
    local pane_target="$1"
    local current_command=""
    local running_flag=""

    running_flag="$(tmux show-options -p -t "$pane_target" -v @agent_cli_running 2>/dev/null || true)"
    [ "$running_flag" = "1" ] && return 0
    current_command="$(tmux display-message -p -t "$pane_target" "#{pane_current_command}" 2>/dev/null || true)"
    [ "$current_command" = "node" ]
}
