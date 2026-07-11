#!/usr/bin/env python3
from __future__ import annotations

import subprocess
import tempfile
import textwrap
import unittest
from pathlib import Path

import yaml


def find_repo_root(start: Path) -> Path:
    for path in [start, *start.parents]:
        if (
            (path / "shogunate_mod" / "manifest.yaml").exists()
            and (path / "shogunate_mod" / "runtime" / "sync_state.py").exists()
        ):
            return path
    raise RuntimeError("repo root not found")


ROOT = find_repo_root(Path(__file__).resolve())
SYNC = ROOT / "shogunate_mod" / "runtime" / "sync_state.py"


class RuntimeSyncStateTest(unittest.TestCase):
    def setUp(self) -> None:
        self.tmp = tempfile.TemporaryDirectory()
        self.root = Path(self.tmp.name)
        for rel in ("queue/inbox", "queue/tasks", "queue/reports", "queue/runtime", "scripts"):
            (self.root / rel).mkdir(parents=True, exist_ok=True)
        (self.root / "queue" / "inbox" / "gunkan.yaml").write_text("messages: []\n", encoding="utf-8")
        (self.root / "queue" / "inbox" / "karo.yaml").write_text("messages: []\n", encoding="utf-8")
        (self.root / "dashboard.md").write_text(
            "# Shogunate Dashboard\n\n最終更新: -\n\n## 🔄 進行中\n\n- `cmd_999`: in_progress - keep me\n\n## ✅ 本日の戦果\n\n| 時刻 | command | 状態 | 要約 |\n|---|---|---|---|\n| old | `cmd_998` | done | keep result |\n",
            encoding="utf-8",
        )
        (self.root / "queue" / "shogun_to_karo.yaml").write_text(
            textwrap.dedent(
                """\
                - id: cmd_001
                  timestamp: "2026-06-21T17:00:00+09:00"
                  status: in_progress
                  project: /tmp/example
                  purpose: sample project
                """
            ),
            encoding="utf-8",
        )
        (self.root / "queue" / "tasks" / "ashigaru1.yaml").write_text(
            "task_id: subtask_a\nparent_cmd: cmd_001\nstatus: assigned\n", encoding="utf-8"
        )
        (self.root / "queue" / "tasks" / "ashigaru2.yaml").write_text(
            "task_id: subtask_b\nparent_cmd: cmd_001\nstatus: assigned\n", encoding="utf-8"
        )
        (self.root / "queue" / "reports" / "ashigaru1_report.yaml").write_text(
            "task_id: subtask_a\nparent_cmd: cmd_001\nstatus: done\nsummary: wrote code\n", encoding="utf-8"
        )
        (self.root / "queue" / "reports" / "ashigaru2_report.yaml").write_text(
            "task_id: subtask_b\nparent_cmd: cmd_001\nstatus: done\nsummary: tests passed\n", encoding="utf-8"
        )
        (self.root / "scripts" / "inbox_write.sh").write_text(
            textwrap.dedent(
                """\
                #!/usr/bin/env bash
                set -euo pipefail
                target="$1"
                content="$2"
                type="$3"
                from="$4"
                python3 - "$PWD/queue/inbox/${target}.yaml" "$content" "$type" "$from" <<'PY'
                import sys, yaml
                path, content, typ, source = sys.argv[1:]
                data = yaml.safe_load(open(path, encoding="utf-8")) or {"messages": []}
                data.setdefault("messages", []).append({"id": "msg_test", "from": source, "type": typ, "content": content, "read": False})
                yaml.safe_dump(data, open(path, "w", encoding="utf-8"), allow_unicode=True, sort_keys=False)
                PY
                """
            ),
            encoding="utf-8",
        )

    def tearDown(self) -> None:
        self.tmp.cleanup()

    def run_sync(self) -> subprocess.CompletedProcess[str]:
        return subprocess.run(
            ["python3", str(SYNC), "--project-root", str(self.root)],
            cwd=str(ROOT),
            text=True,
            stdout=subprocess.PIPE,
            stderr=subprocess.PIPE,
            check=True,
        )

    def read_yaml(self, rel: str):
        with (self.root / rel).open(encoding="utf-8") as fh:
            return yaml.safe_load(fh)

    def test_reports_done_request_gunkan_once_then_gunkan_report_closes_command(self) -> None:
        first = self.run_sync()
        self.assertIn("audit_requested\tcmd_001", first.stdout)

        commands = self.read_yaml("queue/shogun_to_karo.yaml")
        self.assertEqual("audit_requested", commands[0]["status"])
        self.assertEqual("done", self.read_yaml("queue/tasks/ashigaru1.yaml")["status"])
        self.assertEqual("done", self.read_yaml("queue/tasks/ashigaru2.yaml")["status"])

        inbox = self.read_yaml("queue/inbox/gunkan.yaml")
        self.assertEqual(1, len(inbox["messages"]))
        self.assertEqual("audit_requested", inbox["messages"][0]["type"])
        self.assertIn("[cmd:cmd_001]", inbox["messages"][0]["content"])
        self.assertIn("audit_requested", (self.root / "dashboard.md").read_text(encoding="utf-8"))
        self.assertIn("`cmd_999`: in_progress - keep me", (self.root / "dashboard.md").read_text(encoding="utf-8"))
        self.assertIn("| old | `cmd_998` | done | keep result |", (self.root / "dashboard.md").read_text(encoding="utf-8"))

        second = self.run_sync()
        self.assertNotIn("audit_requested\tcmd_001", second.stdout)
        inbox = self.read_yaml("queue/inbox/gunkan.yaml")
        self.assertEqual(1, len(inbox["messages"]))

        (self.root / "queue" / "reports" / "gunkan_report.yaml").write_text(
            "parent_cmd: cmd_001\nstatus: passed\nsummary: no policy violation\n", encoding="utf-8"
        )
        third = self.run_sync()
        self.assertIn("done\tcmd_001", third.stdout)

        commands = self.read_yaml("queue/shogun_to_karo.yaml")
        self.assertEqual("done", commands[0]["status"])
        self.assertIn("completed_at", commands[0])
        self.assertIn("| `cmd_001` | done |", (self.root / "dashboard.md").read_text(encoding="utf-8"))

    def test_failed_gunkan_audit_requests_karo_review(self) -> None:
        self.run_sync()
        (self.root / "queue" / "reports" / "gunkan_report.yaml").write_text(
            "parent_cmd: cmd_001\nstatus: failed\nsummary: npm test failed\n", encoding="utf-8"
        )

        result = self.run_sync()
        self.assertIn("review_requested\tcmd_001", result.stdout)

        commands = self.read_yaml("queue/shogun_to_karo.yaml")
        self.assertEqual("review", commands[0]["status"])
        inbox = self.read_yaml("queue/inbox/karo.yaml")
        self.assertEqual(1, len(inbox["messages"]))
        self.assertEqual("audit_failed", inbox["messages"][0]["type"])
        self.assertIn("cmd_001", inbox["messages"][0]["content"])

    def test_worker_report_update_after_failed_audit_requests_gunkan_reaudit(self) -> None:
        self.run_sync()
        gunkan_report = self.root / "queue" / "reports" / "gunkan_report.yaml"
        gunkan_report.write_text(
            "parent_cmd: cmd_001\nstatus: failed\nsummary: npm test failed\n", encoding="utf-8"
        )
        self.run_sync()

        report = self.root / "queue" / "reports" / "ashigaru2_report.yaml"
        report.write_text(
            "task_id: subtask_b\nparent_cmd: cmd_001\nstatus: done\nsummary: tests fixed and passed\n",
            encoding="utf-8",
        )
        report.touch()

        result = self.run_sync()
        self.assertIn("reaudit_requested\tcmd_001", result.stdout)

        commands = self.read_yaml("queue/shogun_to_karo.yaml")
        self.assertEqual("audit_requested", commands[0]["status"])
        inbox = self.read_yaml("queue/inbox/gunkan.yaml")
        self.assertEqual(2, len(inbox["messages"]))
        self.assertEqual("audit_requested", inbox["messages"][-1]["type"])
        self.assertIn("再監査", inbox["messages"][-1]["content"])

    def test_audit_gate_blocks_final_audit_without_gunshi_report(self) -> None:
        commands = self.read_yaml("queue/shogun_to_karo.yaml")
        commands[0]["audit_gate"] = ["gunshi"]
        (self.root / "queue" / "shogun_to_karo.yaml").write_text(
            yaml.safe_dump(commands, allow_unicode=True, sort_keys=False), encoding="utf-8"
        )

        result = self.run_sync()
        self.assertIn("audit_gated\tcmd_001", result.stdout)

        commands = self.read_yaml("queue/shogun_to_karo.yaml")
        self.assertEqual("in_progress", commands[0]["status"])
        inbox = self.read_yaml("queue/inbox/gunkan.yaml")
        self.assertEqual([], inbox["messages"])
        self.assertNotIn("`cmd_001`: audit_requested", (self.root / "dashboard.md").read_text(encoding="utf-8"))

    def test_audit_gate_allows_final_audit_after_gunshi_report_done(self) -> None:
        commands = self.read_yaml("queue/shogun_to_karo.yaml")
        commands[0]["audit_gate"] = ["gunshi"]
        (self.root / "queue" / "shogun_to_karo.yaml").write_text(
            yaml.safe_dump(commands, allow_unicode=True, sort_keys=False), encoding="utf-8"
        )
        (self.root / "queue" / "reports" / "gunshi_report.yaml").write_text(
            "parent_cmd: cmd_001\nstatus: done\nsummary: reviewed sequence\n", encoding="utf-8"
        )

        result = self.run_sync()
        self.assertIn("audit_requested\tcmd_001", result.stdout)

        commands = self.read_yaml("queue/shogun_to_karo.yaml")
        self.assertEqual("audit_requested", commands[0]["status"])
        inbox = self.read_yaml("queue/inbox/gunkan.yaml")
        self.assertEqual(1, len(inbox["messages"]))
        self.assertEqual("audit_requested", inbox["messages"][0]["type"])


if __name__ == "__main__":
    unittest.main()
