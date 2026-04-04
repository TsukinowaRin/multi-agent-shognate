import importlib.util
import sys
import tempfile
import unittest
from pathlib import Path


ROOT = Path(__file__).resolve().parents[2]
MODULE_PATH = ROOT / "scripts" / "runtime_blocker_notice.py"
SPEC = importlib.util.spec_from_file_location("runtime_blocker_notice", MODULE_PATH)
runtime_blocker_notice = importlib.util.module_from_spec(SPEC)
assert SPEC.loader is not None
sys.modules[SPEC.name] = runtime_blocker_notice
SPEC.loader.exec_module(runtime_blocker_notice)


class RuntimeBlockerNoticeTests(unittest.TestCase):
    def setUp(self):
        self.temp_dir = tempfile.TemporaryDirectory(prefix="mas-runtime-blocker-")
        self.root = Path(self.temp_dir.name)
        self.dashboard = self.root / "dashboard.md"

    def tearDown(self):
        self.temp_dir.cleanup()

    def test_creates_dashboard_and_notice_when_missing(self):
        status = runtime_blocker_notice.ensure_notice(
            self.dashboard,
            "shogun",
            "codex-hard-usage-limit",
            "try again at Apr 4th, 2026 12:47 AM.",
            "2026-04-04 09:30",
        )

        self.assertEqual(status, "updated")
        text = self.dashboard.read_text(encoding="utf-8")
        self.assertIn("# 📊 戦況報告", text)
        self.assertIn("最終更新: 2026-04-04 09:30", text)
        self.assertIn("[runtime-blocked/shogun]", text)
        self.assertNotIn("\nなし\n", text.split(runtime_blocker_notice.ACTION_REQUIRED_HEADING, 1)[1].split("## ", 1)[0])

    def test_replaces_none_and_dedupes_same_notice(self):
        self.dashboard.write_text(
            "\n".join(
                [
                    "# 📊 戦況報告",
                    "最終更新: 2026-04-04 09:00",
                    "",
                    runtime_blocker_notice.ACTION_REQUIRED_HEADING,
                    "なし",
                    "",
                    "## 🔄 進行中 - 只今、戦闘中でござる",
                    "なし",
                    "",
                ]
            )
            + "\n",
            encoding="utf-8",
        )

        first = runtime_blocker_notice.ensure_notice(
            self.dashboard,
            "shogun",
            "codex-hard-usage-limit",
            "try again at Apr 4th, 2026 12:47 AM.",
            "2026-04-04 09:31",
        )
        second = runtime_blocker_notice.ensure_notice(
            self.dashboard,
            "shogun",
            "codex-hard-usage-limit",
            "try again at Apr 4th, 2026 12:47 AM.",
            "2026-04-04 09:32",
        )

        self.assertEqual(first, "updated")
        self.assertEqual(second, "duplicate")
        text = self.dashboard.read_text(encoding="utf-8")
        self.assertEqual(text.count("[runtime-blocked/shogun]"), 1)
        self.assertIn("最終更新: 2026-04-04 09:31", text)

    def test_updates_bilingual_dashboard_heading(self):
        self.dashboard.write_text(
            "\n".join(
                [
                    "# 📊 戦況報告 (Battle Status Report)",
                    "最終更新 (Last Updated): 2026-04-04 09:00",
                    "",
                    runtime_blocker_notice.ACTION_REQUIRED_HEADING_ALT,
                    "なし (None)",
                    "",
                    "## 🔄 進行中 - 只今、戦闘中でござる (In Progress - Currently in Battle)",
                    "なし (None)",
                    "",
                ]
            )
            + "\n",
            encoding="utf-8",
        )

        status = runtime_blocker_notice.ensure_notice(
            self.dashboard,
            "shogun",
            "codex-hard-usage-limit",
            "try again at Apr 4th, 2026 12:47 AM.",
            "2026-04-04 09:33",
        )

        self.assertEqual(status, "updated")
        text = self.dashboard.read_text(encoding="utf-8")
        self.assertIn("最終更新 (Last Updated): 2026-04-04 09:33", text)
        self.assertIn(runtime_blocker_notice.ACTION_REQUIRED_HEADING_ALT, text)
        self.assertEqual(text.count("[runtime-blocked/shogun]"), 1)

    def test_clear_notice_removes_blocker_and_restores_none(self):
        self.dashboard.write_text(
            "\n".join(
                [
                    "# 📊 戦況報告",
                    "最終更新: 2026-04-04 09:00",
                    "",
                    runtime_blocker_notice.ACTION_REQUIRED_HEADING,
                    "- [runtime-blocked/shogun] Codex hard usage-limit prompt を検知。人手で再開判断が必要。 詳細: try again at Apr 4th, 2026 12:47 AM.",
                    "",
                    "## 🔄 進行中 - 只今、戦闘中でござる",
                    "なし",
                    "",
                ]
            )
            + "\n",
            encoding="utf-8",
        )

        status = runtime_blocker_notice.clear_notice(
            self.dashboard,
            "shogun",
            "codex-hard-usage-limit",
            "2026-04-04 09:34",
        )

        self.assertEqual(status, "cleared")
        text = self.dashboard.read_text(encoding="utf-8")
        self.assertIn("最終更新: 2026-04-04 09:34", text)
        self.assertNotIn("[runtime-blocked/shogun]", text)
        self.assertIn(f"{runtime_blocker_notice.ACTION_REQUIRED_HEADING}\nなし\n", text)

    def test_clear_notice_not_found_keeps_existing_timestamp(self):
        self.dashboard.write_text(
            "\n".join(
                [
                    "# 📊 戦況報告",
                    "最終更新: 2026-04-04 09:40",
                    "",
                    runtime_blocker_notice.ACTION_REQUIRED_HEADING,
                    "なし",
                    "",
                    "## 🔄 進行中 - 只今、戦闘中でござる",
                    "なし",
                    "",
                ]
            )
            + "\n",
            encoding="utf-8",
        )

        status = runtime_blocker_notice.clear_notice(
            self.dashboard,
            "shogun",
            "codex-hard-usage-limit",
            "2026-04-04 09:41",
        )

        self.assertEqual(status, "not_found")
        text = self.dashboard.read_text(encoding="utf-8")
        self.assertIn("最終更新: 2026-04-04 09:40", text)

    def test_auth_required_notice_round_trip(self):
        first = runtime_blocker_notice.ensure_notice(
            self.dashboard,
            "karo",
            "codex-auth-required",
            "Sign in with ChatGPT",
            "2026-04-04 09:50",
        )
        cleared = runtime_blocker_notice.clear_notice(
            self.dashboard,
            "karo",
            "codex-auth-required",
            "2026-04-04 09:51",
        )

        self.assertEqual(first, "updated")
        self.assertEqual(cleared, "cleared")
        text = self.dashboard.read_text(encoding="utf-8")
        self.assertNotIn("Codex auth prompt", text)
        self.assertIn("最終更新: 2026-04-04 09:51", text)

    def test_same_agent_issue_updates_detail_in_place(self):
        first = runtime_blocker_notice.ensure_notice(
            self.dashboard,
            "shogun",
            "codex-auth-required",
            "Sign in with ChatGPT",
            "2026-04-04 09:52",
        )
        second = runtime_blocker_notice.ensure_notice(
            self.dashboard,
            "shogun",
            "codex-auth-required",
            "Finish signing in via your browser",
            "2026-04-04 09:53",
        )

        self.assertEqual(first, "updated")
        self.assertEqual(second, "updated")
        text = self.dashboard.read_text(encoding="utf-8")
        self.assertEqual(text.count("[runtime-blocked/shogun]"), 1)
        self.assertIn("Finish signing in via your browser", text)
        self.assertNotIn("Sign in with ChatGPT", text)
        self.assertIn("最終更新: 2026-04-04 09:53", text)

    def test_record_normalizes_preexisting_duplicate_blocked_notices(self):
        self.dashboard.write_text(
            "\n".join(
                [
                    "# 📊 戦況報告",
                    "最終更新: 2026-04-04 09:54",
                    "",
                    runtime_blocker_notice.ACTION_REQUIRED_HEADING,
                    "- [runtime-blocked/shogun] Codex auth prompt を検知。ログイン完了待ち。 詳細: Sign in with ChatGPT",
                    "- [runtime-blocked/karo] Codex auth prompt を検知。ログイン完了待ち。 詳細: Sign in with ChatGPT",
                    "- [runtime-blocked/shogun] Codex auth prompt を検知。ログイン完了待ち。 詳細: Finish signing in via your browser",
                    "",
                    "## 🔄 進行中 - 只今、戦闘中でござる",
                    "なし",
                    "",
                ]
            )
            + "\n",
            encoding="utf-8",
        )

        status = runtime_blocker_notice.ensure_notice(
            self.dashboard,
            "karo",
            "codex-auth-required",
            "Finish signing in via your browser",
            "2026-04-04 09:55",
        )

        self.assertEqual(status, "updated")
        text = self.dashboard.read_text(encoding="utf-8")
        self.assertEqual(text.count("[runtime-blocked/shogun]"), 1)
        self.assertEqual(text.count("[runtime-blocked/karo]"), 1)
        self.assertIn("Finish signing in via your browser", text)
        self.assertNotIn("詳細: Sign in with ChatGPT\n- [runtime-blocked/karo]", text)
        self.assertIn("最終更新: 2026-04-04 09:55", text)


if __name__ == "__main__":
    unittest.main()
