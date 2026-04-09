#!/bin/bash
set -euo pipefail

# tmux 専用 inbox watcher supervisor

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
cd "$SCRIPT_DIR"

mkdir -p logs

CLI_RESTART_COOLDOWN="${CLI_RESTART_COOLDOWN:-30}"
CLI_STARTUP_GRACE_SECONDS="${CLI_STARTUP_GRACE_SECONDS:-20}"
RUNTIME_STARTUP_RECOVERY_GRACE_SECONDS="${RUNTIME_STARTUP_RECOVERY_GRACE_SECONDS:-90}"
WATCHER_RUNTIME_SESSION="${WATCHER_RUNTIME_SESSION:-goza-runtime}"

if [ -f "$SCRIPT_DIR/lib/inbox_path.sh" ]; then
    # shellcheck source=/dev/null
    source "$SCRIPT_DIR/lib/inbox_path.sh"
fi
if declare -F ensure_local_inbox_dir >/dev/null 2>&1; then
    ensure_local_inbox_dir "queue/inbox"
else
    mkdir -p queue/inbox
fi

if [ -f "$SCRIPT_DIR/lib/cli_adapter.sh" ]; then
    # shellcheck source=/dev/null
    source "$SCRIPT_DIR/lib/cli_adapter.sh"
fi

TOPOLOGY_ADAPTER_LOADED=false
if [ -f "$SCRIPT_DIR/lib/topology_adapter.sh" ]; then
    # shellcheck source=/dev/null
    source "$SCRIPT_DIR/lib/topology_adapter.sh"
    TOPOLOGY_ADAPTER_LOADED=true
fi

ensure_inbox_file() {
    local agent="$1"
    if [ ! -f "queue/inbox/${agent}.yaml" ]; then
        printf 'messages: []\n' > "queue/inbox/${agent}.yaml"
    fi
}

refresh_active_ashigaru() {
    mapfile -t ACTIVE_ASHIGARU < <(python3 - << 'PY' 2>/dev/null || true
import yaml
from pathlib import Path

p = Path("config/settings.yaml")
if not p.exists():
    print("ashigaru1")
    raise SystemExit(0)

cfg = yaml.safe_load(p.read_text(encoding="utf-8")) or {}
v = ((cfg.get("topology") or {}).get("active_ashigaru") or [])
out = []
seen = set()
for x in v:
    if isinstance(x, int):
        if x >= 1:
            name = f"ashigaru{x}"
            if name not in seen:
                out.append(name)
                seen.add(name)
    elif isinstance(x, str):
        s = x.strip()
        if s.isdigit():
            i = int(s)
            if i >= 1:
                name = f"ashigaru{i}"
                if name not in seen:
                    out.append(name)
                    seen.add(name)
        elif s.startswith("ashigaru") and s[8:].isdigit() and int(s[8:]) >= 1:
            if s not in seen:
                out.append(s)
                seen.add(s)

if not out:
    out = ["ashigaru1"]
for name in out:
    print(name)
PY
)
    if [ "${#ACTIVE_ASHIGARU[@]}" -eq 0 ]; then
        ACTIVE_ASHIGARU=("ashigaru1")
    fi
}

refresh_karo_agents() {
    KARO_AGENTS=("karo")

    if [ "$TOPOLOGY_ADAPTER_LOADED" = true ]; then
        mapfile -t _karos_from_topology < <(topology_resolve_karo_agents "${ACTIVE_ASHIGARU[@]}" 2>/dev/null || true)
        if [ "${#_karos_from_topology[@]}" -gt 0 ]; then
            KARO_AGENTS=("${_karos_from_topology[@]}")
            return 0
        fi
    fi

    if [ -f "queue/runtime/ashigaru_owner.tsv" ]; then
        mapfile -t _karos_from_owner < <(awk -F '\t' 'NF>=2{print $2}' queue/runtime/ashigaru_owner.tsv | sort -Vu)
        if [ "${#_karos_from_owner[@]}" -gt 0 ]; then
            KARO_AGENTS=("${_karos_from_owner[@]}")
        fi
    fi
}

agent_in_active_list() {
    local target="$1"
    local a
    for a in "${ACTIVE_ASHIGARU[@]}"; do
        [ "$a" = "$target" ] && return 0
    done
    return 1
}

agent_in_karo_list() {
    local target="$1"
    local a
    for a in "${KARO_AGENTS[@]}"; do
        [ "$a" = "$target" ] && return 0
    done
    return 1
}

agent_is_supervised() {
    local target="$1"
    case "$target" in
        shogun|gunshi) return 0 ;;
    esac
    agent_in_active_list "$target" && return 0
    agent_in_karo_list "$target" && return 0
    return 1
}

pane_exists() {
    local pane="$1"
    tmux display-message -p -t "$pane" "#{pane_id}" >/dev/null 2>&1
}

list_backend_pane_targets() {
    if tmux has-session -t "goza-no-ma" 2>/dev/null; then
        tmux list-panes -s -t "goza-no-ma" -F "#{pane_id}" 2>/dev/null || true
        return 0
    fi
    if tmux has-session -t "shogun" 2>/dev/null; then
        tmux list-panes -t "shogun:main" -F "#{pane_id}" 2>/dev/null || true
    fi
    if tmux has-session -t "gunshi" 2>/dev/null; then
        tmux list-panes -t "gunshi:main" -F "#{pane_id}" 2>/dev/null || true
    fi
    if tmux has-session -t "multiagent" 2>/dev/null; then
        tmux list-panes -t "multiagent:agents" -F "#{pane_id}" 2>/dev/null || true
    fi
}

resolve_agent_pane_target() {
    local agent="$1"
    local pane
    local pane_agent
    while IFS= read -r pane; do
        [ -n "$pane" ] || continue
        pane_agent="$(tmux show-options -p -t "$pane" -v @agent_id 2>/dev/null | tr -d '\r' | head -n1)"
        if [ "$pane_agent" = "$agent" ]; then
            printf '%s\n' "$pane"
            return 0
        fi
    done < <(list_backend_pane_targets)
    return 1
}

resolve_cli_type() {
    local agent="$1"
    local pane="$2"

    local cli_tmux
    cli_tmux=$(tmux show-options -p -t "$pane" -v @agent_cli 2>/dev/null || true)
    cli_tmux=$(echo "$cli_tmux" | tr -d '\r' | head -n1 | tr -d '[:space:]')
    if [ -n "$cli_tmux" ]; then
        echo "$cli_tmux"
        return 0
    fi

    if [ -f "$SCRIPT_DIR/queue/runtime/agent_cli.tsv" ]; then
        local cli_runtime
        cli_runtime=$(awk -F '\t' -v a="$agent" '$1==a{print $2}' "$SCRIPT_DIR/queue/runtime/agent_cli.tsv" | tail -n1)
        if [ -n "$cli_runtime" ]; then
            echo "$cli_runtime"
            return 0
        fi
    fi

    if declare -F get_cli_type >/dev/null 2>&1; then
        get_cli_type "$agent"
    else
        echo "codex"
    fi
}

restart_state_file() {
    local agent="$1"
    printf '%s\n' "$SCRIPT_DIR/queue/runtime/cli_restart_${agent}.state"
}

clear_restart_state() {
    local agent="$1"
    rm -f "$(restart_state_file "$agent")"
}

watcher_window_name() {
    local agent="$1"
    printf 'inbox-%s\n' "$agent"
}

watcher_window_target() {
    local agent="$1"
    printf '%s:%s\n' "$WATCHER_RUNTIME_SESSION" "$(watcher_window_name "$agent")"
}

watcher_window_exists() {
    local agent="$1"
    tmux list-windows -t "$WATCHER_RUNTIME_SESSION" -F "#{window_name}" 2>/dev/null | grep -Fxq "$(watcher_window_name "$agent")"
}

watcher_window_is_current() {
    local agent="$1"
    local pane="$2"
    local target
    local configured_agent=""
    local configured_pane=""
    local pane_dead=""

    target="$(watcher_window_target "$agent")"
    watcher_window_exists "$agent" || return 1

    configured_agent="$(tmux show-options -w -t "$target" -v @watch_agent 2>/dev/null | tr -d '\r' | head -n1)"
    configured_pane="$(tmux show-options -w -t "$target" -v @watch_pane 2>/dev/null | tr -d '\r' | head -n1)"
    pane_dead="$(tmux list-panes -t "$target" -F "#{pane_dead}" 2>/dev/null | head -n1)"

    [ "$configured_agent" = "$agent" ] || return 1
    [ "$configured_pane" = "$pane" ] || return 1
    [ "$pane_dead" = "0" ] || return 1
    return 0
}

watcher_shell_command() {
    local agent="$1"
    local pane="$2"
    local cli="$3"
    local log_file="$4"
    local shell_cmd=""

    printf -v shell_cmd \
        'cd %q && env ASW_DISABLE_ESCALATION=1 ASW_PROCESS_TIMEOUT=1 ASW_DISABLE_NORMAL_NUDGE=0 bash %q %q %q %q %q >> %q 2>&1' \
        "$SCRIPT_DIR" \
        "$SCRIPT_DIR/scripts/inbox_watcher.sh" \
        "$agent" \
        "$pane" \
        "$cli" \
        "tmux" \
        "$SCRIPT_DIR/$log_file"
    printf '%s\n' "$shell_cmd"
}

restart_cooldown_active() {
    local agent="$1"
    local state_file
    local last_ts
    local now

    state_file="$(restart_state_file "$agent")"
    [ -f "$state_file" ] || return 1

    last_ts="$(awk 'NR==1{print $1}' "$state_file" 2>/dev/null || true)"
    [[ "$last_ts" =~ ^[0-9]+$ ]] || return 1
    now="$(date +%s)"
    [ $((now - last_ts)) -lt "$CLI_RESTART_COOLDOWN" ]
}

mark_restart_attempt() {
    local agent="$1"
    local pane="$2"
    local cli="$3"

    mkdir -p "$SCRIPT_DIR/queue/runtime"
    printf '%s\t%s\t%s\n' "$(date +%s)" "$pane" "$cli" > "$(restart_state_file "$agent")"
}

rearm_bootstrap_pending_for_restart() {
    local agent="$1"
    local bootstrap_file="$SCRIPT_DIR/queue/runtime/bootstrap_${agent}.md"
    local pending_file="$SCRIPT_DIR/queue/runtime/bootstrap_${agent}.pending"
    local delivered_file="$SCRIPT_DIR/queue/runtime/bootstrap_${agent}.delivered"

    [ -f "$bootstrap_file" ] || return 0
    : > "$pending_file"
    rm -f "$delivered_file"
}

initial_bootstrap_still_pending() {
    local agent="$1"
    local bootstrap_file="$SCRIPT_DIR/queue/runtime/bootstrap_${agent}.md"
    local pending_file="$SCRIPT_DIR/queue/runtime/bootstrap_${agent}.pending"
    local delivered_file="$SCRIPT_DIR/queue/runtime/bootstrap_${agent}.delivered"

    [ -f "$bootstrap_file" ] || return 1
    [ -f "$pending_file" ] || return 1
    [ ! -f "$delivered_file" ]
}

runtime_startup_recovery_grace_active() {
    local start_file="$SCRIPT_DIR/queue/runtime/runtime_start_epoch"
    local start_ts=""
    local now=""

    [ -f "$start_file" ] || return 1
    start_ts="$(awk 'NR==1{print $1}' "$start_file" 2>/dev/null || true)"
    [[ "$start_ts" =~ ^[0-9]+$ ]] || return 1
    now="$(date +%s)"
    [ $((now - start_ts)) -lt "$RUNTIME_STARTUP_RECOVERY_GRACE_SECONDS" ]
}

cli_launch_grace_active() {
    local pane="$1"
    local launch_ts=""
    local now=""

    launch_ts="$(tmux show-options -p -t "$pane" -v @cli_launch_epoch 2>/dev/null | tr -d '\r' | head -n1)"
    [[ "$launch_ts" =~ ^[0-9]+$ ]] || return 1
    now="$(date +%s)"
    [ $((now - launch_ts)) -lt "$CLI_STARTUP_GRACE_SECONDS" ]
}

restart_shell_returned_codex_if_needed() {
    local agent="$1"
    local pane="$2"
    local cli=""
    local current_command=""
    local cmd=""

    pane_exists "$pane" || return 0
    cli="$(resolve_cli_type "$agent" "$pane")"
    [ "$cli" = "codex" ] || return 0

    current_command="$(tmux display-message -p -t "$pane" "#{pane_current_command}" 2>/dev/null | tr -d '\r' | head -n1)"
    if [ "$current_command" = "node" ]; then
        clear_restart_state "$agent"
        return 0
    fi

    case "$current_command" in
        bash|sh|zsh|fish) ;;
        *) return 0 ;;
    esac

    if runtime_startup_recovery_grace_active; then
        return 0
    fi

    if initial_bootstrap_still_pending "$agent"; then
        return 0
    fi

    if cli_launch_grace_active "$pane"; then
        return 0
    fi

    if restart_cooldown_active "$agent"; then
        return 0
    fi

    if ! declare -F build_cli_command_with_type >/dev/null 2>&1; then
        return 0
    fi
    cmd="$(build_cli_command_with_type "$agent" "$cli" 2>/dev/null || true)"
    [ -n "$cmd" ] || return 0

    rearm_bootstrap_pending_for_restart "$agent"
    if tmux send-keys -l -t "$pane" "$cmd" >/dev/null 2>&1 && tmux send-keys -t "$pane" Enter >/dev/null 2>&1; then
        tmux set-option -p -t "$pane" @cli_launch_epoch "$(date +%s)" >/dev/null 2>&1 || true
        mark_restart_attempt "$agent" "$pane" "$cli"
        echo "[$(date)] restarted shell-returned codex pane for ${agent} on ${pane}" >&2
    else
        echo "[$(date)] [WARN] failed to restart shell-returned codex pane for ${agent} on ${pane}" >&2
    fi
}

start_watcher_if_missing() {
    local agent="$1"
    local pane="$2"
    local log_file="$3"
    local cli
    local window_name=""
    local window_target=""
    local shell_cmd=""

    ensure_inbox_file "$agent"
    pane_exists "$pane" || return 0

    if watcher_window_is_current "$agent" "$pane"; then
        return 0
    fi

    cli=$(resolve_cli_type "$agent" "$pane")
    window_name="$(watcher_window_name "$agent")"
    window_target="$(watcher_window_target "$agent")"
    shell_cmd="$(watcher_shell_command "$agent" "$pane" "$cli" "$log_file")"

    if watcher_window_exists "$agent"; then
        tmux kill-window -t "$window_target" >/dev/null 2>&1 || true
        sleep 0.2
    fi
    if pgrep -f "$SCRIPT_DIR/scripts/inbox_watcher.sh ${agent} " >/dev/null 2>&1; then
        pkill -f "$SCRIPT_DIR/scripts/inbox_watcher.sh ${agent} " >/dev/null 2>&1 || true
        sleep 0.2
    fi

    tmux new-window -d -t "$WATCHER_RUNTIME_SESSION" -n "$window_name" "$shell_cmd" >/dev/null 2>&1
    tmux set-option -w -t "$window_target" @watch_agent "$agent" >/dev/null 2>&1 || true
    tmux set-option -w -t "$window_target" @watch_pane "$pane" >/dev/null 2>&1 || true
    tmux set-option -w -t "$window_target" @watch_cli "$cli" >/dev/null 2>&1 || true
}

cleanup_stale_watchers() {
    local window_name agent target
    while IFS= read -r window_name; do
        case "$window_name" in
            inbox-*)
                agent="${window_name#inbox-}"
                agent_is_supervised "$agent" && continue
                target="${WATCHER_RUNTIME_SESSION}:${window_name}"
                tmux kill-window -t "$target" >/dev/null 2>&1 || true
                ;;
        esac
    done < <(tmux list-windows -t "$WATCHER_RUNTIME_SESSION" -F "#{window_name}" 2>/dev/null || true)

    local line pid cmd agent
    while IFS= read -r line; do
        pid="${line%% *}"
        cmd="${line#* }"
        if [[ "$cmd" =~ scripts/inbox_watcher\.sh[[:space:]]+([a-zA-Z0-9_]+)[[:space:]] ]]; then
            agent="${BASH_REMATCH[1]}"
            agent_is_supervised "$agent" && continue
            kill "$pid" >/dev/null 2>&1 || true
        fi
    done < <(pgrep -af "$SCRIPT_DIR/scripts/inbox_watcher.sh" || true)
}

supervisor_tick() {
    local pane=""
    refresh_active_ashigaru
    refresh_karo_agents
    cleanup_stale_watchers

    pane="$(resolve_agent_pane_target "shogun" || true)"
    [ -n "$pane" ] && restart_shell_returned_codex_if_needed "shogun" "$pane"
    [ -n "$pane" ] && start_watcher_if_missing "shogun" "$pane" "logs/inbox_watcher_shogun.log"
    pane="$(resolve_agent_pane_target "gunshi" || true)"
    [ -n "$pane" ] && restart_shell_returned_codex_if_needed "gunshi" "$pane"
    [ -n "$pane" ] && start_watcher_if_missing "gunshi" "$pane" "logs/inbox_watcher_gunshi.log"
    for karo_agent in "${KARO_AGENTS[@]}"; do
        pane="$(resolve_agent_pane_target "$karo_agent" || true)"
        [ -n "$pane" ] || continue
        restart_shell_returned_codex_if_needed "$karo_agent" "$pane"
        start_watcher_if_missing "$karo_agent" "$pane" "logs/inbox_watcher_${karo_agent}.log"
    done
    for agent in "${ACTIVE_ASHIGARU[@]}"; do
        pane="$(resolve_agent_pane_target "$agent" || true)"
        [ -n "$pane" ] || continue
        restart_shell_returned_codex_if_needed "$agent" "$pane"
        start_watcher_if_missing "$agent" "$pane" "logs/inbox_watcher_${agent}.log"
    done
}

if [ "${WATCHER_SUPERVISOR_ONCE:-0}" = "1" ]; then
    if command -v inotifywait >/dev/null 2>&1; then
        supervisor_tick
    fi
    exit 0
fi

while true; do
    if ! command -v inotifywait >/dev/null 2>&1; then
        sleep 30
        continue
    fi

    supervisor_tick
    sleep 5
done
