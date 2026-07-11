#!/usr/bin/env python3
from __future__ import annotations

import unittest
import sys
from pathlib import Path


def find_repo_root(start: Path) -> Path:
    for candidate in (start, *start.parents):
        if (candidate / "shogunate_mod" / "manifest.yaml").is_file():
            return candidate
    raise RuntimeError(f"repo root not found from {start}")


ROOT = find_repo_root(Path(__file__).resolve())
if str(ROOT) not in sys.path:
    sys.path.insert(0, str(ROOT))

from shogunate_mod.battlefield import api


class BattlefieldApiProcessDetectionTest(unittest.TestCase):
    def test_active_pane_command_prefers_agent_cli_descendant(self) -> None:
        table = {
            100: (1, "bash"),
            101: (100, "bash /tmp/launch_shogun.sh"),
            102: (101, "/opt/homebrew/bin/codex --search --sandbox danger-full-access"),
        }

        self.assertEqual("codex", api.active_pane_command("100", "bash", table))

    def test_active_pane_command_keeps_raw_command_without_descendant(self) -> None:
        self.assertEqual("bash", api.active_pane_command("100", "bash", {100: (1, "bash")}))


if __name__ == "__main__":
    unittest.main()
