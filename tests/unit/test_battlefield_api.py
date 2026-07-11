#!/usr/bin/env python3
from __future__ import annotations

import unittest
import sys
import tempfile
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

    def test_deliver_message_prefixes_content_with_session_id(self) -> None:
        with tempfile.TemporaryDirectory() as tmp:
            runtime = Path(tmp)
            writer = runtime / "shogunate_mod" / "inbox" / "write.sh"
            log = runtime / "writer.log"
            writer.parent.mkdir(parents=True)
            writer.write_text(
                "#!/usr/bin/env bash\n"
                f"printf '%s|%s|%s|%s\\n' \"$1\" \"$2\" \"$3\" \"$4\" >> {str(log)!r}\n",
                encoding="utf-8",
            )
            writer.chmod(0o755)

            result = api.deliver_message(
                runtime,
                {
                    "session": "chat-20260711-120000",
                    "role": "shogun",
                    "content": "hello",
                },
            )

            self.assertEqual(0, result.returncode, result.stderr)
            self.assertEqual(
                "shogun|[session:chat-20260711-120000] hello|user_message|lord\n",
                log.read_text(encoding="utf-8"),
            )


if __name__ == "__main__":
    unittest.main()
