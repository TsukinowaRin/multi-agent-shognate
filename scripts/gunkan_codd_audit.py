#!/usr/bin/env python3
"""Compatibility wrapper for the Shogunate MOD Gunkan CoDD audit."""

from __future__ import annotations

import importlib.util
from pathlib import Path
import sys


MOD_SCRIPT = Path(__file__).resolve().parents[1] / "shogunate_mod" / "gunkan" / "codd_audit.py"
SPEC = importlib.util.spec_from_file_location("shogunate_mod_gunkan_codd_audit", MOD_SCRIPT)
if SPEC is None or SPEC.loader is None:
    raise ImportError(f"cannot load {MOD_SCRIPT}")
_module = importlib.util.module_from_spec(SPEC)
sys.modules[SPEC.name] = _module
SPEC.loader.exec_module(_module)

for _name in dir(_module):
    if not _name.startswith("__"):
        globals()[_name] = getattr(_module, _name)


if __name__ == "__main__":
    raise SystemExit(_module.main())
