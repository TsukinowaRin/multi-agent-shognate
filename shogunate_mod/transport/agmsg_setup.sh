#!/usr/bin/env bash
# agmsg_setup.sh -- idempotently join the configured Shogunate agents to agmsg.

set -uo pipefail

AGMSG_SETUP_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
AGMSG_SETUP_PROJECT_ROOT="${SHOGUNATE_REPO_ROOT:-$(cd "${AGMSG_SETUP_DIR}/../.." && pwd -P)}"

# shellcheck source=shogunate_mod/transport/agmsg_bridge.sh
source "${AGMSG_SETUP_DIR}/agmsg_bridge.sh"

AGMSG_SETUP_SETTINGS="${SHOGUN_SETTINGS_FILE:-${AGMSG_SETUP_PROJECT_ROOT}/config/settings.yaml}"
AGMSG_SETUP_TEAM="$(agmsg_bridge_team)"
AGMSG_SETUP_SKILL_DIR="$(agmsg_bridge_skill_dir)"
AGMSG_SETUP_JOIN="${AGMSG_SETUP_SKILL_DIR}/scripts/join.sh"

if [ ! -f "$AGMSG_SETUP_JOIN" ]; then
    echo "[agmsg_setup] join.sh not found at $AGMSG_SETUP_JOIN" >&2
    exit 1
fi

if ! agent_rows="$(python3 - "$AGMSG_SETUP_SETTINGS" <<'PY'
import re
import sys
from pathlib import Path

try:
    import yaml
except Exception as exc:
    print(f"[agmsg_setup] failed to import yaml: {exc}", file=sys.stderr)
    raise SystemExit(1)

settings = Path(sys.argv[1])
try:
    config = yaml.safe_load(settings.read_text(encoding="utf-8")) or {}
except Exception as exc:
    print(f"[agmsg_setup] failed to read {settings}: {exc}", file=sys.stderr)
    raise SystemExit(1)

agents = ["shogun", "gunkan", "gunshi", "karo"]
for item in ((config.get("topology") or {}).get("active_ashigaru") or []):
    value = str(item).strip()
    if value.isdigit() and int(value) >= 1:
        value = f"ashigaru{int(value)}"
    if re.fullmatch(r"ashigaru[1-9][0-9]*", value):
        agents.append(value)

seen = set()
agents = [agent for agent in agents if not (agent in seen or seen.add(agent))]
configured = (config.get("cli") or {}).get("agents") or {}
type_map = {
    "codex": "codex",
    "claude": "claude-code",
    "opencode": "opencode",
    "antigravity": "antigravity",
    "gemini": "gemini",
    "copilot": "copilot",
    "cursor": "cursor",
}

rows = []
for agent in agents:
    details = configured.get(agent) or {}
    cli_type = str(details.get("type") or "").strip().lower()
    if cli_type not in type_map:
        print(
            f"[agmsg_setup] skip {agent}: no agmsg driver for cli type '{cli_type}'",
            file=sys.stderr,
        )
        continue
    rows.append((agent, type_map[cli_type]))

if not rows:
    print(
        "[agmsg_setup] no supported agents joined; no agmsg driver available for any configured cli type",
        file=sys.stderr,
    )
    raise SystemExit(1)
for agent, agmsg_type in rows:
    print(f"{agent}\t{agmsg_type}")
PY
)"; then
    exit 1
fi

join_failed=0
while IFS=$'\t' read -r agent agmsg_type; do
    [ -n "$agent" ] || continue
    if join_output="$(bash "$AGMSG_SETUP_JOIN" "$AGMSG_SETUP_TEAM" "$agent" "$agmsg_type" "$AGMSG_SETUP_PROJECT_ROOT" 2>&1)"; then
        [ -z "$join_output" ] || printf '%s\n' "$join_output"
        continue
    fi

    normalized_output="${join_output,,}"
    case "$normalized_output" in
        *already*joined*|*already*registered*|*duplicate*|*already*exists*)
            echo "[agmsg_setup] $agent is already joined; continuing" >&2
            ;;
        *)
            echo "[agmsg_setup] failed to join $agent: $join_output" >&2
            join_failed=1
            ;;
    esac
done <<< "$agent_rows"

exit "$join_failed"
