#!/bin/bash
set -euo pipefail

# tmux 専用 inbox watcher supervisor

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
cd "$SCRIPT_DIR"

mkdir -p logs

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

start_watcher_if_missing() {
    local agent="$1"
    local pane="$2"
    local log_file="$3"
    local cli

    ensure_inbox_file "$agent"
    pane_exists "$pane" || return 0

    if pgrep -f "scripts/inbox_watcher.sh ${agent} ${pane} " >/dev/null 2>&1; then
        return 0
    fi

    if pgrep -f "scripts/inbox_watcher.sh ${agent} " >/dev/null 2>&1; then
        pkill -f "scripts/inbox_watcher.sh ${agent} " >/dev/null 2>&1 || true
        sleep 0.2
    fi

    cli=$(resolve_cli_type "$agent" "$pane")
    nohup env ASW_DISABLE_ESCALATION=1 ASW_PROCESS_TIMEOUT=0 ASW_DISABLE_NORMAL_NUDGE=0 \
        bash scripts/inbox_watcher.sh "$agent" "$pane" "$cli" "tmux" >> "$log_file" 2>&1 &
}

cleanup_stale_watchers() {
    local line pid cmd agent
    while IFS= read -r line; do
        pid="${line%% *}"
        cmd="${line#* }"
        if [[ "$cmd" =~ scripts/inbox_watcher\.sh[[:space:]]+([a-zA-Z0-9_]+)[[:space:]] ]]; then
            agent="${BASH_REMATCH[1]}"
            [ "$agent" = "shogun" ] && continue
            agent_in_active_list "$agent" && continue
            agent_in_karo_list "$agent" && continue
            kill "$pid" >/dev/null 2>&1 || true
        fi
    done < <(pgrep -af "scripts/inbox_watcher.sh" || true)
}

while true; do
    if ! command -v inotifywait >/dev/null 2>&1; then
        sleep 30
        continue
    fi

    refresh_active_ashigaru
    refresh_karo_agents
    cleanup_stale_watchers

    pane="$(resolve_agent_pane_target "shogun")"
    [ -n "$pane" ] && start_watcher_if_missing "shogun" "$pane" "logs/inbox_watcher_shogun.log"
    pane="$(resolve_agent_pane_target "gunshi")"
    [ -n "$pane" ] && start_watcher_if_missing "gunshi" "$pane" "logs/inbox_watcher_gunshi.log"
    for karo_agent in "${KARO_AGENTS[@]}"; do
        pane="$(resolve_agent_pane_target "$karo_agent")"
        [ -n "$pane" ] || continue
        start_watcher_if_missing "$karo_agent" "$pane" "logs/inbox_watcher_${karo_agent}.log"
    done
    for agent in "${ACTIVE_ASHIGARU[@]}"; do
        pane="$(resolve_agent_pane_target "$agent")"
        [ -n "$pane" ] || continue
        start_watcher_if_missing "$agent" "$pane" "logs/inbox_watcher_${agent}.log"
    done
    sleep 5
done
