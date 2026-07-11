#!/usr/bin/env python3
"""Compatibility entrypoint for the Shogunate MOD dashboard viewer."""

from pathlib import Path
import runpy


MOD_SCRIPT = Path(__file__).resolve().parents[1] / "shogunate_mod" / "view" / "dashboard_viewer.py"


if __name__ == "__main__":
    runpy.run_path(str(MOD_SCRIPT), run_name="__main__")
