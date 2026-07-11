#!/usr/bin/env python3
"""Compatibility wrapper for the Shogunate MOD Shogun-to-Karo bridge."""

from __future__ import annotations

import importlib.util
from pathlib import Path


ROOT = Path(__file__).resolve().parents[1]
MOD_SOURCE = ROOT / "shogunate_mod" / "runtime" / "shogun_to_karo_bridge.py"
SPEC = importlib.util.spec_from_file_location("shogunate_mod_shogun_to_karo_bridge", MOD_SOURCE)
if SPEC is None or SPEC.loader is None:
    raise ImportError(f"Unable to load Shogunate MOD bridge: {MOD_SOURCE}")
_module = importlib.util.module_from_spec(SPEC)
SPEC.loader.exec_module(_module)

for _name in dir(_module):
    if not _name.startswith("__"):
        globals()[_name] = getattr(_module, _name)


if __name__ == "__main__":
    raise SystemExit(_module.main())
