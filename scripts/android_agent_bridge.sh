#!/usr/bin/env bash
set -euo pipefail

TMUX_BIN="${TMUX_BIN:-tmux}"
GOZA_SESSION_NAME="${GOZA_SESSION_NAME:-goza-no-ma}"
GOZA_WINDOW_NAME="${GOZA_WINDOW_NAME:-overview}"

usage() {
    cat <<'EOF'
Usage:
  scripts/android_agent_bridge.sh list
  scripts/android_agent_bridge.sh capture <agent_id>
  scripts/android_agent_bridge.sh send-b64 <agent_id> <base64_text>

Android companion bridge. Resolves tmux panes by @agent_id so the app can talk
to shogun, karo, gunshi, or any ashigaru without depending on pane indexes.
EOF
}

tmux_has_session() {
    "$TMUX_BIN" has-session -t "$1" 2>/dev/null
}

list_backend_panes() {
    if tmux_has_session "$GOZA_SESSION_NAME"; then
        "$TMUX_BIN" list-panes -s -t "$GOZA_SESSION_NAME" -F "#{pane_id}" 2>/dev/null || true
        return 0
    fi
    if tmux_has_session shogun; then
        "$TMUX_BIN" list-panes -t "shogun:main" -F "#{pane_id}" 2>/dev/null || true
    fi
    if tmux_has_session gunshi; then
        "$TMUX_BIN" list-panes -t "gunshi:main" -F "#{pane_id}" 2>/dev/null || true
    fi
    if tmux_has_session multiagent; then
        "$TMUX_BIN" list-panes -t "multiagent:agents" -F "#{pane_id}" 2>/dev/null || true
    fi
}

pane_option() {
    local pane="$1"
    local option="$2"
    "$TMUX_BIN" show-options -p -t "$pane" -v "$option" 2>/dev/null | tr -d '\r' | head -n1
}

resolve_agent_pane() {
    local agent_id="$1"
    local pane=""
    local current=""
    while IFS= read -r pane; do
        [ -n "$pane" ] || continue
        current="$(pane_option "$pane" "@agent_id")"
        if [ "$current" = "$agent_id" ]; then
            printf '%s\n' "$pane"
            return 0
        fi
    done < <(list_backend_panes)
    return 1
}

list_agents() {
    local pane=""
    local agent_id=""
    local model_name=""
    local cli_name=""
    local seen=""
    while IFS= read -r pane; do
        [ -n "$pane" ] || continue
        agent_id="$(pane_option "$pane" "@agent_id")"
        [ -n "$agent_id" ] || continue
        case "$seen" in
            *"|$agent_id|"*) continue ;;
        esac
        seen="${seen}|${agent_id}|"
        model_name="$(pane_option "$pane" "@model_name")"
        cli_name="$(pane_option "$pane" "@agent_cli")"
        printf '%s\t%s\t%s\n' "$agent_id" "$model_name" "$cli_name"
    done < <(list_backend_panes)
}

capture_agent() {
    local agent_id="$1"
    local pane=""
    pane="$(resolve_agent_pane "$agent_id")" || {
        printf '[android-bridge] agent not found: %s\n' "$agent_id" >&2
        return 2
    }
    "$TMUX_BIN" capture-pane -p -e -t "$pane" -S -500
}

decode_base64() {
    local encoded="$1"
    printf '%s' "$encoded" | base64 --decode 2>/dev/null || printf '%s' "$encoded" | base64 -D 2>/dev/null
}

send_agent_b64() {
    local agent_id="$1"
    local encoded="$2"
    local pane=""
    local text=""
    pane="$(resolve_agent_pane "$agent_id")" || {
        printf '[android-bridge] agent not found: %s\n' "$agent_id" >&2
        return 2
    }
    text="$(decode_base64 "$encoded")" || {
        printf '[android-bridge] invalid base64 payload\n' >&2
        return 3
    }
    if [ -n "$text" ]; then
        "$TMUX_BIN" send-keys -l -t "$pane" "$text"
        sleep 0.3
    fi
    "$TMUX_BIN" send-keys -t "$pane" Enter
}

main() {
    local cmd="${1:-}"
    case "$cmd" in
        list)
            list_agents
            ;;
        capture)
            [ "$#" -eq 2 ] || { usage >&2; return 64; }
            capture_agent "$2"
            ;;
        send-b64)
            [ "$#" -eq 3 ] || { usage >&2; return 64; }
            send_agent_b64 "$2" "$3"
            ;;
        -h|--help|help|"")
            usage
            ;;
        *)
            usage >&2
            return 64
            ;;
    esac
}

main "$@"
