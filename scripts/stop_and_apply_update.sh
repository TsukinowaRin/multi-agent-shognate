#!/usr/bin/env bash
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
cd "$SCRIPT_DIR"

usage() {
    cat <<'EOF'
Usage:
  bash scripts/stop_and_apply_update.sh <manual|upstream-sync> [--restart] [--requested-by <name>]

Queues an update request, stops Shogunate tmux sessions, applies the pending update,
and optionally restarts the system with the new code.
EOF
}

if [ "$#" -lt 1 ]; then
    usage >&2
    exit 2
fi

ACTION="$1"
shift

REQUESTED_BY="unknown"
RESTART=0

while [ "$#" -gt 0 ]; do
    case "$1" in
        --restart)
            RESTART=1
            ;;
        --requested-by)
            shift
            REQUESTED_BY="${1:-unknown}"
            ;;
        -h|--help)
            usage
            exit 0
            ;;
        *)
            echo "[stop_and_apply_update] unknown option: $1" >&2
            usage >&2
            exit 2
            ;;
    esac
    shift
done

echo "[stop_and_apply_update] queue update: action=${ACTION} requested_by=${REQUESTED_BY}"
python3 scripts/update_manager.py queue-update "$ACTION" --requested-by "$REQUESTED_BY"

for session in goza-no-ma shogun gunshi multiagent; do
    if tmux has-session -t "$session" 2>/dev/null; then
        echo "[stop_and_apply_update] stop tmux session: $session"
        tmux kill-session -t "$session"
    fi
done

set +e
python3 scripts/update_manager.py apply-pending
STATUS=$?
set -e

case "$STATUS" in
    0|10)
        ;;
    *)
        echo "[stop_and_apply_update] apply-pending failed: exit=${STATUS}" >&2
        exit "$STATUS"
        ;;
esac

if [ "$STATUS" -eq 10 ]; then
    echo "[stop_and_apply_update] update applied; running first_setup.sh"
    bash "$SCRIPT_DIR/first_setup.sh" || true
fi

if [ "$RESTART" -eq 1 ]; then
    echo "[stop_and_apply_update] restarting Shogunate"
    exec env MAS_SKIP_PENDING_UPDATE=1 MAS_SKIP_STARTUP_UPDATE=1 bash "$SCRIPT_DIR/shutsujin_departure.sh"
fi

echo "[stop_and_apply_update] done"
