#!/usr/bin/env bash
# Execute only controller-enumerated role recovery actions for a tmux pane.

set -uo pipefail

ROOT="${SHOGUNATE_RUNTIME_DIR:-$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)}"
CONTROLLER="$ROOT/shogunate_mod/runtime/role_failover.py"
SETTINGS="${MAS_SETTINGS_PATH:-$ROOT/config/settings.yaml}"
PYTHON="${CLI_ADAPTER_PYTHON:-python3}"
COOLDOWN="${SHOGUNATE_ROLE_RESTART_COOLDOWN_SECONDS:-2}"

fail() {
    echo "[role-failover] $*" >&2
    return 1
}

valid_role() {
    [[ "${1:-}" =~ ^(shogun|gunkan|gunshi|karo([1-9][0-9]*)?|ashigaru[1-9][0-9]*)$ ]]
}

prepare_role_bootstrap() {
    local role="$1"
    local slot="$2"
    local bootstrap="$ROOT/queue/runtime/bootstrap_${role}.md"
    local primary="$ROOT/queue/runtime/bootstrap_${role}.primary.md"
    local pending="$ROOT/queue/runtime/bootstrap_${role}.pending"
    local delivered="$ROOT/queue/runtime/bootstrap_${role}.delivered"
    local marker="【Primary/Fallback引継ぎ】"
    local tmp=""

    [ -f "$primary" ] || return 0
    if [ "$slot" = "primary" ]; then
        cp "$primary" "$bootstrap"
    elif ! grep -Fq "$marker" "$bootstrap"; then
        tmp=$(mktemp "$ROOT/queue/runtime/.bootstrap_${role}.XXXXXX") || return 1
        {
            printf '%s 最新世代のFallbackとして起動した。queue/runtime/role_failover.yamlの自役職handoffを確認し、role/generation/plan/scope/workspaceを検証してhandoff_complete eventを記録するまで通常作業を開始するな。\n' "$marker"
            cat "$primary"
        } > "$tmp"
        mv "$tmp" "$bootstrap"
    fi
    : > "$pending"
    rm -f "$delivered"
}

run_monitor_daemon() {
    local interval="${SHOGUNATE_NO_PROGRESS_INTERVAL_SECONDS:-30}"
    local payload=""
    local role=""
    local generation=""
    local pane=""
    local safe_role=""
    local fingerprint=""
    local previous=""
    local fingerprint_file=""
    local tick_type=""
    [[ "$interval" =~ ^[0-9]+$ ]] && [ "$interval" -ge 5 ] && [ "$interval" -le 300 ] || interval=30
    while true; do
        payload=$("$PYTHON" "$CONTROLLER" --root "$ROOT" monitor-candidates --format json 2>/dev/null || printf '[]')
        while IFS=$'\t' read -r role generation; do
            [ -n "$role" ] || continue
            pane=$(tmux list-panes -a -F $'#{pane_id}\t#{@agent_id}' 2>/dev/null \
                | awk -F '\t' -v wanted="$role" '$2==wanted {print $1; exit}')
            [[ "$pane" =~ ^%[0-9]+$ ]] || continue
            safe_role=$(printf '%s' "$role" | tr -c 'A-Za-z0-9_.-' '_')
            fingerprint_file="$ROOT/queue/runtime/role_progress_${safe_role}.fingerprint"
            fingerprint=$("$PYTHON" - "$ROOT" "$role" <<'PY'
import os, sys
root, role = sys.argv[1:]
paths = [
    os.path.join(root, "queue", "tasks", f"{role}.yaml"),
    os.path.join(root, "queue", "reports", f"{role}_report.yaml"),
    os.path.join(root, "queue", "inbox", f"{role}.yaml"),
]
parts = []
for path in paths:
    try:
        stat = os.stat(path)
        parts.append(f"{stat.st_mtime_ns}:{stat.st_size}")
    except OSError:
        parts.append("missing")
print("|".join(parts))
PY
            )
            previous=$(head -n1 "$fingerprint_file" 2>/dev/null || true)
            if [ -z "$previous" ] || [ "$previous" != "$fingerprint" ]; then
                tick_type="progress"
                printf '%s\n' "$fingerprint" > "$fingerprint_file"
            else
                tick_type="no_progress"
            fi
            SHOGUNATE_RUNTIME_DIR="$ROOT" bash "$0" "$tick_type" "$role" "$generation" "$tick_type" "$pane" || true
        done < <(printf '%s' "$payload" | "$PYTHON" -c '
import json, sys
for item in json.load(sys.stdin):
    print("{}\t{}".format(item.get("role", ""), item.get("generation", "")))
' 2>/dev/null)
        sleep "$interval"
    done
}

main() {
    local event_type="${1:-}"
    local role="${2:-}"
    local generation="${3:-}"
    local reason="${4:-process_exit}"
    local pane="${5:-${TMUX_PANE:-}}"
    local event_id=""
    local event_json=""
    local result=""
    local action=""
    local new_generation=""
    local slot=""
    local safe_role=""
    local launch_script=""

    [ "$event_type" = "process_exit" ] || [ "$event_type" = "explicit_failure" ] || [ "$event_type" = "user_stop" ] || [ "$event_type" = "no_progress" ] || [ "$event_type" = "progress" ] || [ "$event_type" = "primary_recovered" ] || fail "invalid event type" || return 1
    valid_role "$role" || fail "invalid role" || return 1
    [[ "$generation" =~ ^[1-9][0-9]*$ ]] || fail "invalid generation" || return 1
    [[ "$pane" =~ ^%[0-9]+$ ]] || fail "invalid tmux pane" || return 1
    case "$event_type:$reason" in
        process_exit:process_exit|process_exit:shell_return|explicit_failure:config_error|explicit_failure:rate_limit|explicit_failure:auth_error|explicit_failure:model_unavailable|user_stop:intentional_stop|no_progress:no_progress|progress:progress|primary_recovered:primary_recovered) ;;
        *) fail "invalid failure reason"; return 1 ;;
    esac
    [ -f "$CONTROLLER" ] || fail "controller missing" || return 1
    [[ "$COOLDOWN" =~ ^[0-9]+$ ]] && [ "$COOLDOWN" -le 30 ] || COOLDOWN=2

    event_id="${event_type}-${role}-${generation}"
    case "$event_type" in no_progress|progress|primary_recovered) event_id="${event_id}-$(date +%s)" ;; esac
    event_json=$("$PYTHON" - "$event_id" "$event_type" "$role" "$generation" "$reason" <<'PY'
import json, sys
event_id, event_type, role, generation, reason = sys.argv[1:]
print(json.dumps({
    "event_id": event_id,
    "type": event_type,
    "role": role,
    "expected_generation": int(generation),
    "reason": reason,
}, separators=(",", ":")))
PY
    ) || return 1
    result=$("$PYTHON" "$CONTROLLER" --root "$ROOT" apply-event --event-json "$event_json" --format json) || return $?
    mapfile -t parsed < <(printf '%s' "$result" | "$PYTHON" -c '
import json, sys
data = json.load(sys.stdin)
role = data.get("state", {}).get("roles", {}).get(sys.argv[1], {})
print(data.get("action", ""))
print(role.get("generation", ""))
print(role.get("active_slot", ""))
' "$role") || return 1
    [ "${#parsed[@]}" -eq 3 ] || return 1
    action="${parsed[0]}"
    new_generation="${parsed[1]}"
    slot="${parsed[2]}"

    case "$event_type" in
        process_exit|explicit_failure)
            tmux set-option -p -t "$pane" @role_exit_reported_generation "$generation" >/dev/null 2>&1 || true
            ;;
    esac
    case "$action" in
        restart_primary|activate_fallback|restore_primary)
            prepare_role_bootstrap "$role" "$slot"
            sleep "$COOLDOWN"
            safe_role=$(printf '%s' "$role" | tr -c 'A-Za-z0-9_.-' '_')
            launch_script="$ROOT/queue/runtime/launch_${safe_role}.sh"
            [ -f "$launch_script" ] || fail "launch script missing" || return 1
            tmux set-option -p -t "$pane" @role_generation "$new_generation" >/dev/null 2>&1 || true
            tmux set-option -p -t "$pane" @role_slot "$slot" >/dev/null 2>&1 || true
            tmux respawn-pane -k -t "$pane" "bash $(printf '%q' "$launch_script")" >/dev/null 2>&1 || return 1
            ;;
        enter_emergency)
            pane=$(tmux list-panes -a -F $'#{pane_id}\t#{@agent_id}' 2>/dev/null \
                | awk -F '\t' '$2=="gunkan" {print $1; exit}')
            if [[ "$pane" =~ ^%[0-9]+$ ]]; then
                tmux send-keys -l -t "$pane" "Shogun停止により非常指揮へ移行した。queue/runtime/role_failover.yaml の固定policyを読み、各taskをemergency_authorize_workで照合し、計画外または完了時は安全停止せよ。" >/dev/null 2>&1 || true
                tmux send-keys -t "$pane" Enter >/dev/null 2>&1 || true
            fi
            ;;
        request_reassignment)
            pane=$(tmux list-panes -a -F $'#{pane_id}\t#{@agent_id}' 2>/dev/null \
                | awk -F '\t' '$2=="karo" || $2=="karo1" {print $1; exit}')
            if [[ "$pane" =~ ^%[0-9]+$ ]]; then
                tmux send-keys -l -t "$pane" "足軽の再割当要求がある。queue/runtime/role_failover.yaml のpending_reassignmentsを確認し、旧lease・途中変更・競合を確認してから再割当せよ。" >/dev/null 2>&1 || true
                tmux send-keys -t "$pane" Enter >/dev/null 2>&1 || true
            fi
            ;;
        none|safe_stop|warn|mark_handoff_required|resume_after_handoff|authorize|reject)
            ;;
        *)
            fail "controller returned unknown action '$action'"
            return 1
            ;;
    esac
}

if [ "${1:-}" = "daemon" ]; then
    run_monitor_daemon
else
    main "$@"
fi
