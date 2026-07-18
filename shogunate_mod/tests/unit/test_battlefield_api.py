#!/usr/bin/env python3
from __future__ import annotations

import json
import sys
import tempfile
import unittest
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


class SessionRecencyTest(unittest.TestCase):
    def _write_session_store(self, runtime: Path, sessions: list[dict], current: str = "") -> None:
        path = api.session_store(runtime)
        path.parent.mkdir(parents=True, exist_ok=True)
        path.write_text(
            json.dumps({"current": current, "sessions": sessions}, ensure_ascii=False, indent=2) + "\n",
            encoding="utf-8",
        )

    def _write_transcript(self, runtime: Path, session_id: str, entries: list[dict]) -> None:
        path = api.session_dir(runtime, session_id) / "messages.jsonl"
        path.parent.mkdir(parents=True, exist_ok=True)
        path.write_text(
            "".join(json.dumps(entry, ensure_ascii=False) + "\n" for entry in entries),
            encoding="utf-8",
        )

    def test_user_event_newer_than_metadata_updates_effective_updated_at(self) -> None:
        session = {"id": "chat-user", "updated_at": 1_700_000_000, "created_at": 1_700_000_000}
        messages = [
            {"time": "2024-01-01T00:00:00+00:00", "from": "user", "type": "user_message", "content": "hi"},
            {"time": "2024-06-15T12:00:00+00:00", "from": "user", "type": "user_message", "content": "later"},
        ]
        effective = api.session_effective_updated_at(session, messages)
        self.assertEqual(1_718_452_800, effective)
        self.assertGreater(effective, int(session["updated_at"]))

    def test_role_reply_event_updates_effective_updated_at(self) -> None:
        session = {"id": "chat-role", "updated_at": 1_700_000_000, "created_at": 1_700_000_000}
        messages = [
            {"time": "2024-01-01T00:00:00+00:00", "from": "user", "type": "user_message", "content": "hi"},
            {
                "time": "2024-07-01T09:30:00+00:00",
                "from": "shogun",
                "to": "user",
                "type": "role_reply",
                "content": "ack",
            },
        ]
        effective = api.session_effective_updated_at(session, messages)
        self.assertEqual(1_719_826_200, effective)
        self.assertGreater(effective, int(session["updated_at"]))

    def test_malformed_or_missing_timestamp_is_stable_not_wall_clock(self) -> None:
        session = {"id": "chat-bad", "updated_at": "not-a-time", "created_at": None}
        messages = [
            {"time": "garbage", "from": "user", "type": "user_message"},
            {"from": "shogun", "type": "role_reply", "content": "no time"},
            {"time": "", "from": "user"},
            {"time": -5, "from": "user"},
        ]
        first = api.session_effective_updated_at(session, messages)
        second = api.session_effective_updated_at(session, messages)
        self.assertEqual(0, first)
        self.assertEqual(first, second)

        session_meta = {"id": "chat-meta", "updated_at": "bad", "created_at": 1_650_000_000}
        self.assertEqual(1_650_000_000, api.session_effective_updated_at(session_meta, messages))

        session_updated = {"id": "chat-upd", "updated_at": 1_660_000_000, "created_at": 1_650_000_000}
        self.assertEqual(1_660_000_000, api.session_effective_updated_at(session_updated, messages))

    def test_sessions_listed_newest_first_with_transcript_recency(self) -> None:
        with tempfile.TemporaryDirectory() as tmp:
            runtime = Path(tmp)
            self._write_session_store(
                runtime,
                [
                    {
                        "id": "chat-old",
                        "title": "old",
                        "mode": "resume",
                        "created_at": 1_000,
                        "updated_at": 2_000,
                    },
                    {
                        "id": "chat-mid",
                        "title": "mid",
                        "mode": "resume",
                        "created_at": 1_100,
                        "updated_at": 3_000,
                    },
                    {
                        "id": "chat-new",
                        "title": "new",
                        "mode": "new",
                        "created_at": 1_200,
                        "updated_at": 1_500,
                    },
                ],
                current="chat-mid",
            )
            # mid has stale metadata but a newer role reply
            self._write_transcript(
                runtime,
                "chat-mid",
                [{"time": 5_000, "from": "shogun", "type": "role_reply", "content": "later"}],
            )
            # new has a user event between mid metadata and mid reply
            self._write_transcript(
                runtime,
                "chat-new",
                [{"time": "2024-01-01T00:00:00Z", "from": "user", "type": "user_message", "content": "u"}],
            )
            # old has only malformed times -> falls back to metadata updated_at=2000
            self._write_transcript(
                runtime,
                "chat-old",
                [{"time": "nope", "from": "user", "type": "user_message"}],
            )

            data = api.sessions_with_effective_updated_at(runtime)
            ids = [s["id"] for s in data["sessions"]]
            self.assertEqual(["chat-new", "chat-mid", "chat-old"], ids)
            by_id = {s["id"]: s for s in data["sessions"]}
            self.assertEqual(1_704_067_200, by_id["chat-new"]["updated_at"])
            self.assertEqual(5_000, by_id["chat-mid"]["updated_at"])
            self.assertEqual(2_000, by_id["chat-old"]["updated_at"])
            self.assertEqual("chat-mid", data["current"])

            # Stable across repeated loads (no wall-clock injection)
            again = api.sessions_with_effective_updated_at(runtime)
            self.assertEqual(
                [s["updated_at"] for s in data["sessions"]],
                [s["updated_at"] for s in again["sessions"]],
            )

    def test_parse_public_timestamp_accepts_iso_with_compact_offset(self) -> None:
        # Matches time.strftime("%Y-%m-%dT%H:%M:%S%z") used by iso_now()
        ts = api.parse_public_timestamp("2024-06-15T12:00:00+0000")
        self.assertEqual(1_718_452_800, ts)

    def test_parse_public_timestamp_fail_closed_on_non_finite_and_extreme(self) -> None:
        for value in (
            float("inf"),
            float("-inf"),
            float("nan"),
            "Infinity",
            "-Infinity",
            "NaN",
            "inf",
            "nan",
            "1" * 100,
            "9" * 50,
            10**20,
            -(10**20),
            10**13,
            -1,
            -5,
            1e308,
            -1e308,
        ):
            with self.subTest(value=value):
                self.assertIsNone(api.parse_public_timestamp(value))


if __name__ == "__main__":
    unittest.main()
