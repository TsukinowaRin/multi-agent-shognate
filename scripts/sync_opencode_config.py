#!/usr/bin/env python3
"""Compatibility wrapper for the Shogunate MOD OpenCode config sync."""

from __future__ import annotations

import runpy
import sys
from pathlib import Path


ROOT = Path(__file__).resolve().parent.parent
MOD_SCRIPT = ROOT / "shogunate_mod/configure/sync_opencode_config.py"


if __name__ == "__main__":
    sys.path.insert(0, str(MOD_SCRIPT.parent))
    runpy.run_path(str(MOD_SCRIPT), run_name="__main__")
