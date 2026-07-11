#!/usr/bin/env python3
"""Compatibility wrapper for the Shogunate MOD runtime blocker notice helper."""

from __future__ import annotations

import importlib.util
from pathlib import Path
import sys


ROOT = Path(__file__).resolve().parents[1]
MOD_SOURCE = ROOT / "shogunate_mod" / "runtime" / "blocker_notice.py"
SPEC = importlib.util.spec_from_file_location("shogunate_mod_runtime_blocker_notice", MOD_SOURCE)
if SPEC is None or SPEC.loader is None:
    raise RuntimeError(f"failed to load {MOD_SOURCE}")

_module = importlib.util.module_from_spec(SPEC)
sys.modules[SPEC.name] = _module
SPEC.loader.exec_module(_module)

for _name in dir(_module):
    if not _name.startswith("__"):
        globals()[_name] = getattr(_module, _name)


if __name__ == "__main__":
    raise SystemExit(_module.main())
