#!/usr/bin/env python3
"""Compatibility wrapper for the Shogunate MOD pairing server."""

from __future__ import annotations

import importlib.util
from pathlib import Path
import sys


MOD_SERVER = Path(__file__).resolve().parents[1] / "shogunate_mod" / "pair" / "server.py"
SPEC = importlib.util.spec_from_file_location("shogunate_mod_pair_server", MOD_SERVER)
if SPEC is None or SPEC.loader is None:
    raise ImportError(f"cannot load {MOD_SERVER}")
_module = importlib.util.module_from_spec(SPEC)
sys.modules[SPEC.name] = _module
SPEC.loader.exec_module(_module)

for _name in dir(_module):
    if not _name.startswith("__"):
        globals()[_name] = getattr(_module, _name)


if __name__ == "__main__":
    raise SystemExit(_module.main(sys.argv[1:]))
