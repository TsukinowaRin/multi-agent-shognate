#!/usr/bin/env python3
"""Compatibility wrapper for the Shogunate LocalAPI REPL."""

from pathlib import Path
import runpy


ROOT = Path(__file__).resolve().parents[1]
runpy.run_path(str(ROOT / "shogunate_mod" / "localapi" / "repl.py"), run_name="__main__")
