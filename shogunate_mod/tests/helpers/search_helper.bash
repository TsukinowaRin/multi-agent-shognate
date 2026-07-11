#!/usr/bin/env bash

bats_search() {
    local pattern="$1"
    shift

    if command -v rg >/dev/null 2>&1; then
        rg -n -- "$pattern" "$@"
    else
        python3 - "$pattern" "$@" <<'PY'
import os
import re
import sys
from pathlib import Path

pattern = sys.argv[1]
paths = sys.argv[2:]
regex = re.compile(pattern)
matched = False

def emit(path: Path) -> None:
    global matched
    try:
        with path.open(encoding="utf-8", errors="replace") as fh:
            for lineno, line in enumerate(fh, 1):
                if regex.search(line):
                    sys.stdout.write(f"{path}:{lineno}:{line}")
                    matched = True
    except IsADirectoryError:
        return

for raw in paths:
    path = Path(raw)
    if path.is_dir():
        for child in sorted(p for p in path.rglob("*") if p.is_file()):
            emit(child)
    else:
        emit(path)

raise SystemExit(0 if matched else 1)
PY
    fi
}

bats_search_fixed() {
    local pattern="$1"
    shift

    if command -v rg >/dev/null 2>&1; then
        rg -nF -- "$pattern" "$@"
    else
        python3 - "$pattern" "$@" <<'PY'
import sys
from pathlib import Path

needle = sys.argv[1]
paths = sys.argv[2:]
matched = False

def emit(path: Path) -> None:
    global matched
    try:
        with path.open(encoding="utf-8", errors="replace") as fh:
            for lineno, line in enumerate(fh, 1):
                if needle in line:
                    sys.stdout.write(f"{path}:{lineno}:{line}")
                    matched = True
    except IsADirectoryError:
        return

for raw in paths:
    path = Path(raw)
    if path.is_dir():
        for child in sorted(p for p in path.rglob("*") if p.is_file()):
            emit(child)
    else:
        emit(path)

raise SystemExit(0 if matched else 1)
PY
    fi
}
