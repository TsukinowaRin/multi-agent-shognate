#!/usr/bin/env bash

initialize_runtime_topology() {
    local _a=""
    local _b=""
    local _found=0

    ASHIGARU_PANES=()
    KARO_PANES=()

    ACTIVE_ASHIGARU=("ashigaru1")
    if [ -f "./config/settings.yaml" ]; then
        mapfile -t _active_from_yaml < <(python3 - << 'PY' 2>/dev/null || true
import yaml
from pathlib import Path
p = Path("config/settings.yaml")
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
if out:
    for i in out:
        print(i)
PY
)
        if [ "${#_active_from_yaml[@]}" -gt 0 ]; then
            ACTIVE_ASHIGARU=("${_active_from_yaml[@]}")
        fi
    fi

    ACTIVE_ASHIGARU_COUNT=${#ACTIVE_ASHIGARU[@]}
    KARO_AGENTS=("karo")
    if [ "$TOPOLOGY_ADAPTER_LOADED" = true ]; then
        mapfile -t _karo_from_topology < <(topology_resolve_karo_agents "${ACTIVE_ASHIGARU[@]}" 2>/dev/null || true)
        if [ "${#_karo_from_topology[@]}" -gt 0 ]; then
            KARO_AGENTS=("${_karo_from_topology[@]}")
        fi
    fi
    LEAD_KARO="${KARO_AGENTS[0]:-karo}"

    KNOWN_ASHIGARU=("${ACTIVE_ASHIGARU[@]}")
    mapfile -t _known_from_files < <(python3 - << 'PY' 2>/dev/null || true
import re
from pathlib import Path
ids = set()
for p in Path("queue/tasks").glob("ashigaru*.yaml"):
    m = re.fullmatch(r"ashigaru([1-9][0-9]*)\.yaml", p.name)
    if m:
        ids.add(int(m.group(1)))
for p in Path("queue/reports").glob("ashigaru*_report.yaml"):
    m = re.fullmatch(r"ashigaru([1-9][0-9]*)_report\.yaml", p.name)
    if m:
        ids.add(int(m.group(1)))
for p in Path("queue/inbox").glob("ashigaru*.yaml"):
    m = re.fullmatch(r"ashigaru([1-9][0-9]*)\.yaml", p.name)
    if m:
        ids.add(int(m.group(1)))
for i in sorted(ids):
    print(f"ashigaru{i}")
PY
)
    for _a in "${_known_from_files[@]}"; do
        _found=0
        for _b in "${KNOWN_ASHIGARU[@]}"; do
            if [ "$_a" = "$_b" ]; then
                _found=1
                break
            fi
        done
        if [ "$_found" -eq 0 ]; then
            KNOWN_ASHIGARU+=("$_a")
        fi
    done
    if [ "${#KNOWN_ASHIGARU[@]}" -eq 0 ]; then
        KNOWN_ASHIGARU=("ashigaru1")
    fi
}
