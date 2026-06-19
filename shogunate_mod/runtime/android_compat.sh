#!/usr/bin/env bash
# Shogunate MOD Android compatibility tmux helpers.

is_android_compat_enabled() {
    [ "${MAS_ENABLE_ANDROID_COMPAT:-0}" = "1" ]
}

android_proxy_command() {
    local agent_id="$1"
    printf 'cd %q && exec %q %q %q' \
        "$SCRIPT_DIR" \
        "${RUNTIME_PYTHON:-python3}" \
        "$SCRIPT_DIR/shogunate_mod/runtime/android_tmux_proxy.py" \
        "$agent_id"
}

create_android_compat_sessions() {
    local wrapper_target=""
    local agent_id=""
    local -a compat_targets=()
    local root_pane=""

    if ! is_android_compat_enabled; then
        return 0
    fi
    if [ ! -f "$SCRIPT_DIR/shogunate_mod/runtime/android_tmux_proxy.py" ]; then
        log_info "Android互換sessionは無効（shogunate_mod/runtime/android_tmux_proxy.py がありません）"
        return 0
    fi

    tmux kill-session -t '=shogun' 2>/dev/null || true
    tmux kill-session -t '=gunkan' 2>/dev/null || true
    tmux kill-session -t '=gunshi' 2>/dev/null || true
    tmux kill-session -t '=multiagent' 2>/dev/null || true

    tmux new-session -d -s shogun -n main "$(android_proxy_command shogun)"
    tmux set-option -p -t shogun:main @agent_id "shogun"
    tmux set-option -p -t shogun:main @model_name "$(resolve_model_display_name "shogun")"
    tmux set-option -p -t shogun:main @current_task ""
    tmux set-option -p -t shogun:main @agent_cli "$(resolve_cli_type_for_agent "shogun" 2>/dev/null || echo codex)"
    tmux select-pane -t shogun:main -T shogun >/dev/null 2>&1 || true

    tmux new-session -d -s gunkan -n main "$(android_proxy_command gunkan)"
    tmux set-option -p -t gunkan:main @agent_id "gunkan"
    tmux set-option -p -t gunkan:main @model_name "$(resolve_model_display_name "gunkan")"
    tmux set-option -p -t gunkan:main @current_task ""
    tmux set-option -p -t gunkan:main @agent_cli "$(resolve_cli_type_for_agent "gunkan" 2>/dev/null || echo codex)"
    tmux select-pane -t gunkan:main -T gunkan >/dev/null 2>&1 || true

    tmux new-session -d -s gunshi -n main "$(android_proxy_command gunshi)"
    tmux set-option -p -t gunshi:main @agent_id "gunshi"
    tmux set-option -p -t gunshi:main @model_name "$(resolve_model_display_name "gunshi")"
    tmux set-option -p -t gunshi:main @current_task ""
    tmux set-option -p -t gunshi:main @agent_cli "$(resolve_cli_type_for_agent "gunshi" 2>/dev/null || echo codex)"
    tmux select-pane -t gunshi:main -T gunshi >/dev/null 2>&1 || true

    tmux new-session -d -s multiagent -n agents "$(android_proxy_command "${KARO_AGENTS[0]:-karo}")"
    root_pane="$(tmux display-message -p -t "multiagent:agents" "#{pane_id}")"
    compat_targets=("$root_pane")
    for ((i=1; i<MULTIAGENT_COUNT; i++)); do
        compat_targets+=("$(tmux split-window -v -t "$root_pane" -P -F '#{pane_id}' "$(android_proxy_command "${MULTIAGENT_IDS[$i]}")")")
        tmux select-layout -t "multiagent:agents" tiled >/dev/null 2>&1 || true
    done
    for i in "${!MULTIAGENT_IDS[@]}"; do
        wrapper_target="${compat_targets[$i]:-}"
        [ -n "$wrapper_target" ] || continue
        agent_id="${MULTIAGENT_IDS[$i]}"
        tmux set-option -p -t "$wrapper_target" @agent_id "$agent_id"
        tmux set-option -p -t "$wrapper_target" @model_name "$(resolve_model_display_name "$agent_id")"
        tmux set-option -p -t "$wrapper_target" @current_task ""
        tmux set-option -p -t "$wrapper_target" @agent_cli "$(resolve_cli_type_for_agent "$agent_id" 2>/dev/null || echo codex)"
        tmux select-pane -t "$wrapper_target" -T "$agent_id" >/dev/null 2>&1 || true
    done
    tmux set-option -t multiagent -w pane-border-status top
    tmux set-option -t multiagent -w pane-border-format '#{?pane_active,#[reverse],}#[bold]#{@agent_id}#[default] (#{@model_name}) #{@current_task}'
}
