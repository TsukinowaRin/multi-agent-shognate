#!/usr/bin/env bash
# agmsg_bridge.sh -- agmsg wake-up signal transport helpers.
#
# This file is a function library. YAML inboxes remain the durable message
# store; agmsg carries only a pointer telling the recipient to read its inbox.

AGMSG_BRIDGE_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
AGMSG_BRIDGE_PROJECT_ROOT="${SHOGUNATE_REPO_ROOT:-$(cd "${AGMSG_BRIDGE_DIR}/../.." && pwd)}"
AGMSG_BRIDGE_SETTINGS="${SHOGUN_SETTINGS_FILE:-${AGMSG_BRIDGE_PROJECT_ROOT}/config/settings.yaml}"

_agmsg_bridge_read_scalar() {
    local key_path="$1"
    local fallback="$2"

    python3 - "$AGMSG_BRIDGE_SETTINGS" "$key_path" "$fallback" <<'PY' 2>/dev/null || printf '%s\n' "$fallback"
import sys
from pathlib import Path

try:
    import yaml

    settings = Path(sys.argv[1])
    value = None
    if settings.is_file():
        value = yaml.safe_load(settings.read_text(encoding="utf-8")) or {}
        for key in sys.argv[2].split("."):
            value = value.get(key) if isinstance(value, dict) else None
            if value is None:
                break
    if value is None or isinstance(value, (dict, list)):
        value = sys.argv[3]
    print(value)
except Exception:
    print(sys.argv[3])
PY
}

agmsg_bridge_team() {
    _agmsg_bridge_read_scalar "transport.agmsg.team" "shogunate"
}

agmsg_bridge_skill_dir() {
    local configured

    if [ -n "${AGMSG_SKILL_DIR:-}" ]; then
        printf '%s\n' "$AGMSG_SKILL_DIR"
        return 0
    fi

    configured="$(_agmsg_bridge_read_scalar "transport.agmsg.skill_dir" "")"
    if [ -z "$configured" ]; then
        printf '%s\n' "${HOME:-}/.agents/skills/agmsg"
    elif [[ "$configured" == "~/"* ]]; then
        printf '%s\n' "${HOME:-}/${configured#\~/}"
    else
        printf '%s\n' "$configured"
    fi
}

agmsg_bridge_enabled() {
    local target="${1:-}"

    [ -n "$target" ] || return 1
    python3 - "$AGMSG_BRIDGE_SETTINGS" "$target" <<'PY' 2>/dev/null
import sys
from pathlib import Path

try:
    import yaml

    settings = Path(sys.argv[1])
    if not settings.is_file():
        raise SystemExit(1)
    config = yaml.safe_load(settings.read_text(encoding="utf-8")) or {}
    transport = config.get("transport") or {}
    mode = str(transport.get("mode") or "yaml").strip().lower()
    if mode not in {"yaml", "agmsg", "both"}:
        mode = "yaml"
    if mode in {"agmsg", "both"}:
        raise SystemExit(0)

    agents = (transport.get("agmsg") or {}).get("bridge_agents") or []
    if not isinstance(agents, list):
        agents = []
    target = sys.argv[2]
    raise SystemExit(0 if any(str(agent).strip() == target for agent in agents) else 1)
except SystemExit:
    raise
except Exception:
    raise SystemExit(1)
PY
}

agmsg_bridge_send() {
    local target="${1:-}"
    local type="${2:-}"
    local from="${3:-}"
    local team
    local skill_dir
    local send_script
    local body

    team="$(agmsg_bridge_team)"
    skill_dir="$(agmsg_bridge_skill_dir)"
    send_script="${skill_dir}/scripts/send.sh"
    body="[shogunate] inbox: unread message(s) waiting. Read queue/inbox/${target}.yaml and process type=${type} from ${from}."

    if [ ! -f "$send_script" ]; then
        echo "[agmsg_bridge] warning: send.sh not found at $send_script" >&2
        return 0
    fi
    if ! bash "$send_script" "$team" "$from" "$target" "$body" >/dev/null 2>&1; then
        echo "[agmsg_bridge] warning: failed to send wake-up signal to $target" >&2
    fi
    return 0
}
