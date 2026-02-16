#!/usr/bin/env bash
# topology_adapter.sh — 足軽/家老トポロジ解決ヘルパー
#
# 提供関数:
#   topology_load_active_ashigaru
#   topology_resolve_karo_agents [ashigaru...]
#   build_even_ownership_map [output_path] [ashigaru...]
#   topology_lookup_owner_karo <ashigaru_id> [map_path]
#   topology_print_owner_summary [map_path]

TOPOLOGY_ADAPTER_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
TOPOLOGY_PROJECT_ROOT="${TOPOLOGY_PROJECT_ROOT:-$(cd "${TOPOLOGY_ADAPTER_DIR}/.." && pwd)}"
TOPOLOGY_SETTINGS_PATH="${TOPOLOGY_SETTINGS_PATH:-${TOPOLOGY_PROJECT_ROOT}/config/settings.yaml}"
TOPOLOGY_RUNTIME_DIR="${TOPOLOGY_RUNTIME_DIR:-${TOPOLOGY_PROJECT_ROOT}/queue/runtime}"
TOPOLOGY_OWNER_MAP="${TOPOLOGY_OWNER_MAP:-${TOPOLOGY_RUNTIME_DIR}/ashigaru_owner.tsv}"

topology__sort_agent_ids() {
    printf '%s\n' "$@" | awk 'NF{print $0}' | sort -V
}

topology_load_active_ashigaru() {
    python3 - "$TOPOLOGY_SETTINGS_PATH" << 'PY'
import sys
from pathlib import Path

settings = Path(sys.argv[1])
try:
    import yaml  # type: ignore
except Exception:
    print("ashigaru1")
    raise SystemExit(0)

if not settings.exists():
    print("ashigaru1")
    raise SystemExit(0)

cfg = yaml.safe_load(settings.read_text(encoding="utf-8")) or {}
active = ((cfg.get("topology") or {}).get("active_ashigaru") or [])
out = []
seen = set()
for item in active:
    if isinstance(item, int):
        if item >= 1:
            aid = f"ashigaru{item}"
            if aid not in seen:
                seen.add(aid)
                out.append(aid)
    else:
        s = str(item).strip()
        if s.isdigit() and int(s) >= 1:
            aid = f"ashigaru{int(s)}"
            if aid not in seen:
                seen.add(aid)
                out.append(aid)
        elif s.startswith("ashigaru") and s[8:].isdigit() and int(s[8:]) >= 1:
            if s not in seen:
                seen.add(s)
                out.append(s)

if not out:
    out = ["ashigaru1"]

for aid in sorted(out, key=lambda x: int(x[8:])):
    print(aid)
PY
}

topology__karo_mode() {
    python3 - "$TOPOLOGY_SETTINGS_PATH" << 'PY'
import sys
from pathlib import Path
try:
    import yaml  # type: ignore
except Exception:
    print("auto")
    raise SystemExit(0)

settings = Path(sys.argv[1])
if not settings.exists():
    print("auto")
    raise SystemExit(0)

cfg = yaml.safe_load(settings.read_text(encoding="utf-8")) or {}
mode = str((((cfg.get("topology") or {}).get("karo") or {}).get("mode") or "auto")).strip().lower()
if mode not in ("auto", "manual"):
    mode = "auto"
print(mode)
PY
}

topology__max_ashigaru_per_karo() {
    python3 - "$TOPOLOGY_SETTINGS_PATH" << 'PY'
import sys
from pathlib import Path
try:
    import yaml  # type: ignore
except Exception:
    print(8)
    raise SystemExit(0)

settings = Path(sys.argv[1])
if not settings.exists():
    print(8)
    raise SystemExit(0)

cfg = yaml.safe_load(settings.read_text(encoding="utf-8")) or {}
value = (((cfg.get("topology") or {}).get("karo") or {}).get("max_ashigaru_per_karo"))
try:
    n = int(value)
except Exception:
    n = 8
if n < 1:
    n = 1
print(n)
PY
}

topology__manual_karo_agents() {
    python3 - "$TOPOLOGY_SETTINGS_PATH" << 'PY'
import re
import sys
from pathlib import Path
try:
    import yaml  # type: ignore
except Exception:
    raise SystemExit(0)

settings = Path(sys.argv[1])
if not settings.exists():
    raise SystemExit(0)

cfg = yaml.safe_load(settings.read_text(encoding="utf-8")) or {}
agents = ((((cfg.get("topology") or {}).get("karo") or {}).get("active_karo")) or [])
out = []
seen = set()
for item in agents:
    s = str(item).strip()
    if s == "karo":
        if s not in seen:
            seen.add(s)
            out.append(s)
    elif re.fullmatch(r"karo[1-9][0-9]*", s):
        if s not in seen:
            seen.add(s)
            out.append(s)

def sort_key(name: str):
    if name == "karo":
        return (0, 0)
    return (1, int(name[4:]))

for name in sorted(out, key=sort_key):
    print(name)
PY
}

topology_resolve_karo_agents() {
    local ashigaru=("$@")
    local mode
    local max_per_karo
    local karo_count
    local i

    if [ "${#ashigaru[@]}" -eq 0 ]; then
        mapfile -t ashigaru < <(topology_load_active_ashigaru)
    fi
    if [ "${#ashigaru[@]}" -eq 0 ]; then
        ashigaru=("ashigaru1")
    fi
    mapfile -t ashigaru < <(topology__sort_agent_ids "${ashigaru[@]}")

    mode="$(topology__karo_mode)"
    if [ "$mode" = "manual" ]; then
        local manual=()
        mapfile -t manual < <(topology__manual_karo_agents)
        if [ "${#manual[@]}" -gt 0 ]; then
            printf '%s\n' "${manual[@]}"
            return 0
        fi
    fi

    max_per_karo="$(topology__max_ashigaru_per_karo)"
    karo_count=$(( (${#ashigaru[@]} + max_per_karo - 1) / max_per_karo ))
    if [ "$karo_count" -le 1 ]; then
        echo "karo"
        return 0
    fi

    for ((i=1; i<=karo_count; i++)); do
        echo "karo${i}"
    done
}

build_even_ownership_map() {
    local output_path="${1:-$TOPOLOGY_OWNER_MAP}"
    shift || true
    local ashigaru=("$@")
    local karos=()
    local i

    if [ "${#ashigaru[@]}" -eq 0 ]; then
        mapfile -t ashigaru < <(topology_load_active_ashigaru)
    fi
    if [ "${#ashigaru[@]}" -eq 0 ]; then
        ashigaru=("ashigaru1")
    fi
    mapfile -t ashigaru < <(topology__sort_agent_ids "${ashigaru[@]}")
    mapfile -t karos < <(topology_resolve_karo_agents "${ashigaru[@]}")
    if [ "${#karos[@]}" -eq 0 ]; then
        karos=("karo")
    fi

    mkdir -p "$(dirname "$output_path")"
    : > "$output_path"
    for ((i=0; i<${#ashigaru[@]}; i++)); do
        printf "%s\t%s\n" "${ashigaru[$i]}" "${karos[$((i % ${#karos[@]}))]}" >> "$output_path"
    done
}

topology_lookup_owner_karo() {
    local ashigaru_id="$1"
    local map_path="${2:-$TOPOLOGY_OWNER_MAP}"
    [ -f "$map_path" ] || return 1
    awk -F '\t' -v a="$ashigaru_id" '$1==a{print $2; exit}' "$map_path"
}

topology_print_owner_summary() {
    local map_path="${1:-$TOPOLOGY_OWNER_MAP}"
    [ -f "$map_path" ] || return 0
    awk -F '\t' 'NF>=2{c[$2]++} END{for (k in c) print k"\t"c[k]}' "$map_path" | sort -V
}
