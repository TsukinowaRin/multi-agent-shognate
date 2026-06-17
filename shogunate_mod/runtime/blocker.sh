#!/usr/bin/env bash
# Shogunate MOD runtime blocked relay helpers.

run_runtime_blocker_notice_tmux() {
    local action="$1"
    shift
    local agent_id="$1"
    local issue="$2"
    local detail="${3:-}"
    local notice_script="${MAS_RUNTIME_BLOCKER_NOTICE_SCRIPT:-$SCRIPT_DIR/shogunate_mod/runtime/blocker_notice.py}"
    local result=""

    if [ ! -f "$notice_script" ]; then
        return 0
    fi
    if ! command -v python3 >/dev/null 2>&1; then
        return 0
    fi

    result=$(python3 "$notice_script" --project-root "$SCRIPT_DIR" --action "$action" --agent "$agent_id" --issue "$issue" --detail "$detail" 2>/dev/null || true)
    if [ -n "$result" ]; then
        result=$(printf '%s' "$result" | tr -d '\r' | tail -n 1)
    fi

    case "$result" in
        updated)
            log_info "  └─ ${agent_id}: runtime blocked notice を dashboard に記録"
            return 0
            ;;
        duplicate)
            return 0
            ;;
        cleared)
            log_info "  └─ ${agent_id}: runtime blocked notice を dashboard から除去"
            return 0
            ;;
        not_found)
            return 0
            ;;
    esac

    log_warn "  └─ ${agent_id}: runtime blocked notice の ${action} に失敗"
    return 0
}

record_runtime_blocker_notice_tmux() {
    run_runtime_blocker_notice_tmux "record" "$@"
}

clear_runtime_blocker_notice_tmux() {
    run_runtime_blocker_notice_tmux "clear" "$@"
}

runtime_blocked_relay_marker_path_tmux() {
    local agent_id="$1"
    local issue="$2"
    printf '%s/queue/runtime/runtime_blocked_relay/%s__%s.sent' "$SCRIPT_DIR" "$agent_id" "$issue"
}

runtime_blocked_human_marker_path_tmux() {
    local agent_id="$1"
    local issue="$2"
    printf '%s/queue/runtime/runtime_blocked_human_relay/%s__%s.sent' "$SCRIPT_DIR" "$agent_id" "$issue"
}

notify_shogun_runtime_blocked_tmux() {
    local agent_id="$1"
    local issue="$2"
    local relay_dir="$SCRIPT_DIR/queue/runtime/runtime_blocked_relay"
    local marker_path=""
    local message=""

    [ -n "$agent_id" ] || return 0
    [ -n "$issue" ] || return 0
    [ "$agent_id" = "shogun" ] && return 0
    marker_path="$(runtime_blocked_relay_marker_path_tmux "$agent_id" "$issue")"
    [ -f "$marker_path" ] && return 0
    mkdir -p "$relay_dir"

    case "$issue" in
        codex-hard-usage-limit)
            message="queue/inbox/${agent_id}.yaml の担当 agent が Codex hard usage-limit で停止中。dashboard.md の runtime-blocked/${agent_id} を確認し、殿へ blocked 状態を報告せよ。"
            ;;
        codex-auth-required)
            message="queue/inbox/${agent_id}.yaml の担当 agent が Codex auth 待ちで停止中。dashboard.md の runtime-blocked/${agent_id} を確認し、殿へ blocked 状態を報告せよ。"
            ;;
        *)
            message="queue/inbox/${agent_id}.yaml の担当 agent が runtime blocker (${issue}) で停止中。dashboard.md の runtime-blocked/${agent_id} を確認し、殿へ blocked 状態を報告せよ。"
            ;;
    esac

    if bash "$SCRIPT_DIR/scripts/inbox_write.sh" shogun "$message" runtime_blocked "startup_guard" >/dev/null 2>&1; then
        : > "$marker_path"
        log_info "  └─ ${agent_id}: runtime blocker を shogun inbox へ通知"
        return 0
    fi

    log_warn "  └─ ${agent_id}: runtime blocker の shogun relay に失敗"
    return 0
}

notify_lord_runtime_blocked_tmux() {
    local agent_id="$1"
    local issue="$2"
    local relay_dir="$SCRIPT_DIR/queue/runtime/runtime_blocked_human_relay"
    local marker_path=""
    local message=""

    [ -n "$agent_id" ] || return 0
    [ -n "$issue" ] || return 0
    [ "$agent_id" = "shogun" ] || return 0
    marker_path="$(runtime_blocked_human_marker_path_tmux "$agent_id" "$issue")"
    [ -f "$marker_path" ] && return 0
    mkdir -p "$relay_dir"

    case "$issue" in
        codex-hard-usage-limit)
            message="queue/inbox/shogun.yaml の担当 agent が Codex hard usage-limit で停止中。dashboard.md の runtime-blocked/* を確認し、人手で再開判断を行え。"
            ;;
        codex-auth-required)
            message="queue/inbox/shogun.yaml の担当 agent が Codex auth 待ちで停止中。dashboard.md の runtime-blocked/* を確認し、人手でログインを完了せよ。"
            ;;
        *)
            message="queue/inbox/shogun.yaml の担当 agent が runtime blocker (${issue}) で停止中。dashboard.md の runtime-blocked/* を確認し、人手で再開判断を行え。"
            ;;
    esac

    if bash "$SCRIPT_DIR/scripts/inbox_write.sh" lord "$message" runtime_blocked "startup_guard" >/dev/null 2>&1; then
        : > "$marker_path"
        log_info "  └─ ${agent_id}: runtime blocker を lord inbox へ通知"
        return 0
    fi

    log_warn "  └─ ${agent_id}: runtime blocker の lord relay に失敗"
    return 0
}

clear_shogun_runtime_blocked_tmux() {
    local agent_id="$1"
    local issue="$2"
    local marker_path=""

    [ -n "$agent_id" ] || return 0
    [ -n "$issue" ] || return 0
    [ "$agent_id" = "shogun" ] && return 0
    marker_path="$(runtime_blocked_relay_marker_path_tmux "$agent_id" "$issue")"
    rm -f "$marker_path"
    return 0
}

clear_lord_runtime_blocked_tmux() {
    local agent_id="$1"
    local issue="$2"
    local marker_path=""

    [ -n "$agent_id" ] || return 0
    [ -n "$issue" ] || return 0
    [ "$agent_id" = "shogun" ] || return 0
    marker_path="$(runtime_blocked_human_marker_path_tmux "$agent_id" "$issue")"
    rm -f "$marker_path"
    return 0
}

record_runtime_blocker_tmux() {
    local agent_id="$1"
    local issue="$2"
    local detail="${3:-}"
    record_runtime_blocker_notice_tmux "$agent_id" "$issue" "$detail"
    notify_shogun_runtime_blocked_tmux "$agent_id" "$issue"
    notify_lord_runtime_blocked_tmux "$agent_id" "$issue"
    return 0
}

clear_runtime_blocker_tmux() {
    local agent_id="$1"
    local issue="$2"
    local detail="${3:-}"
    clear_runtime_blocker_notice_tmux "$agent_id" "$issue" "$detail"
    clear_shogun_runtime_blocked_tmux "$agent_id" "$issue"
    clear_lord_runtime_blocked_tmux "$agent_id" "$issue"
    return 0
}
