#!/usr/bin/env python3
"""Unit tests for report provenance: pane-bound receipts and completion gate.

acceptance 条件 1〜4 を pure function で検証する。tmux は起動せず、
pane metadata と role_failover 状態を dict で与えて境界を確認する。
"""

from __future__ import annotations

import sys
import tempfile
from pathlib import Path

import yaml

import unittest
from unittest import mock


def find_repo_root(start: Path) -> Path:
    for path in [start, *start.parents]:
        if (path / "shogunate_mod" / "manifest.yaml").is_file() and (
            path / "shogunate_mod" / "runtime" / "role_failover.py"
        ).is_file():
            return path
    raise RuntimeError(f"repo root not found from {start}")


ROOT = find_repo_root(Path(__file__).resolve())
sys.path.insert(0, str(ROOT))

from shogunate_mod.runtime import report_provenance as rp  # noqa: E402
from shogunate_mod.runtime import karo_done_to_shogun_bridge as bridge  # noqa: E402


def pane_meta(role="ashigaru1", *, generation=2, agent_id=None, running="true", cli="codex", pane="%5"):
    return {
        "pane": pane,
        "agent_id": agent_id if agent_id is not None else role,
        "role_generation": generation,
        "agent_cli_running": running,
        "agent_cli": cli,
    }


def role_state(role="ashigaru1", *, generation=2, status="ready", slot="primary", cli="codex", fallback_cli=None):
    state = {
        "generation": generation,
        "status": status,
        "active_slot": slot,
        "primary_profile": {"type": cli},
    }
    if fallback_cli is not None:
        state["fallback_profile"] = {"type": fallback_cli}
    return state


REPORT_BYTES = b"report: done\nstatus: completed\n"
ASHIGARU_REPORT = "queue/reports/ashigaru1_report.yaml"


class PaneIdentityTests(unittest.TestCase):
    def test_gunkan_uses_canonical_runtime_report(self):
        self.assertEqual(Path("queue/reports/gunkan_report.yaml"), rp.expected_report_rel("gunkan"))

    def test_bare_report_filename_is_rejected(self):
        self.assertFalse(rp.report_path_matches_role("ashigaru1", "ashigaru1_report.yaml"))

    def test_correct_pane_succeeds(self):
        result = rp.verify_pane_identity(
            role="ashigaru1",
            pane_meta=pane_meta(),
            role_state=role_state(),
            report_path=ASHIGARU_REPORT,
        )
        self.assertTrue(result.ok)
        self.assertEqual("authorized", result.reason)

    def test_wrong_role_rejected(self):
        result = rp.verify_pane_identity(
            role="ashigaru1",
            pane_meta=pane_meta(agent_id="karo"),
            role_state=role_state(),
            report_path=ASHIGARU_REPORT,
        )
        self.assertFalse(result.ok)
        self.assertEqual("wrong_role", result.reason)

    def test_wrong_pane_rejected(self):
        # pane metadata must be present and identify the sender pane.
        result = rp.verify_pane_identity(
            role="ashigaru1",
            pane_meta=pane_meta(pane=""),
            role_state=role_state(),
            report_path=ASHIGARU_REPORT,
        )
        self.assertEqual("missing_pane", result.reason)

    def test_missing_pane_metadata_rejected(self):
        result = rp.verify_pane_identity(
            role="ashigaru1",
            pane_meta={},
            role_state=role_state(),
            report_path=ASHIGARU_REPORT,
        )
        self.assertEqual("missing_pane", result.reason)

    def test_stale_generation_rejected(self):
        result = rp.verify_pane_identity(
            role="ashigaru1",
            pane_meta=pane_meta(generation=1),
            role_state=role_state(generation=2),
            report_path=ASHIGARU_REPORT,
        )
        self.assertEqual("stale_generation", result.reason)

    def test_missing_generation_rejected(self):
        meta = pane_meta()
        meta["role_generation"] = None
        result = rp.verify_pane_identity(
            role="ashigaru1",
            pane_meta=meta,
            role_state=role_state(generation=2),
            report_path=ASHIGARU_REPORT,
        )
        self.assertEqual("stale_generation", result.reason)

    def test_stopped_role_rejected(self):
        for stopped in ("stopped", "safe_stopped", "awaiting_handoff"):
            with self.subTest(status=stopped):
                result = rp.verify_pane_identity(
                    role="ashigaru1",
                    pane_meta=pane_meta(),
                    role_state=role_state(status=stopped),
                    report_path=ASHIGARU_REPORT,
                )
                self.assertEqual("role_stopped", result.reason)

    def test_cli_stopped_rejected(self):
        result = rp.verify_pane_identity(
            role="ashigaru1",
            pane_meta=pane_meta(running="false"),
            role_state=role_state(),
            report_path=ASHIGARU_REPORT,
        )
        self.assertEqual("cli_stopped", result.reason)

    def test_cli_mismatch_rejected(self):
        result = rp.verify_pane_identity(
            role="ashigaru1",
            pane_meta=pane_meta(cli="opencode"),
            role_state=role_state(cli="codex"),
            report_path=ASHIGARU_REPORT,
        )
        self.assertEqual("cli_mismatch", result.reason)

    def test_report_path_mismatch_rejected(self):
        result = rp.verify_pane_identity(
            role="ashigaru1",
            pane_meta=pane_meta(),
            role_state=role_state(),
            report_path="queue/reports/ashigaru2_report.yaml",
        )
        self.assertEqual("report_path_mismatch", result.reason)


class ReceiptTests(unittest.TestCase):
    def setUp(self):
        self.tmp = tempfile.TemporaryDirectory()
        self.root = Path(self.tmp.name)
        self.receipt_dir = self.root / "queue" / "runtime" / "report_receipts"

    def tearDown(self):
        self.tmp.cleanup()

    def _write_receipt(self, role="ashigaru1", report_bytes=REPORT_BYTES, generation=2):
        receipt = rp.build_receipt(
            role=role,
            generation=generation,
            pane="%5",
            agent_cli="codex",
            report_path=ASHIGARU_REPORT,
            report_bytes=report_bytes,
            parent_cmd="cmd_receipt",
            task_id=f"task_{role}",
        )
        rp.write_receipt(self.receipt_dir, role, receipt)
        return receipt

    def test_receipt_atomic_write_and_load(self):
        receipt = self._write_receipt()
        loaded = rp.load_receipt(self.receipt_dir, "ashigaru1")
        self.assertIsNotNone(loaded)
        self.assertEqual(receipt["digest"], loaded["digest"])
        self.assertEqual(2, loaded["generation"])
        # file lives at <receipt_dir>/<role>.yaml
        self.assertTrue((self.receipt_dir / "ashigaru1.yaml").exists())

    def test_receipt_idempotent_overwrite_same_digest(self):
        self._write_receipt()
        self._write_receipt()
        self.assertTrue((self.receipt_dir / "ashigaru1.yaml").exists())
        self.assertEqual(1, len(list(self.receipt_dir.glob("*.yaml"))))

    def test_receipt_role_must_match_target(self):
        receipt = rp.build_receipt(
            role="ashigaru2",
            generation=2,
            pane="%6",
            agent_cli="codex",
            report_path="queue/reports/ashigaru2_report.yaml",
            report_bytes=b"x",
            parent_cmd="cmd_receipt",
            task_id="task_ashigaru2",
        )
        with self.assertRaises(ValueError):
            rp.write_receipt(self.receipt_dir, "ashigaru1", receipt)

    def test_report_changed_after_receipt_digest_mismatch(self):
        self._write_receipt(report_bytes=REPORT_BYTES)
        # report content changed after the receipt was created
        result = rp.verify_receipt_against_report(
            receipt=rp.load_receipt(self.receipt_dir, "ashigaru1"),
            role="ashigaru1",
            report_bytes=b"report: done\nstatus: TAMPERED\n",
            current_generation=2,
        )
        self.assertFalse(result.ok)
        self.assertEqual("digest_mismatch", result.reason)

    def test_receipt_role_mismatch_rejected(self):
        self._write_receipt(role="ashigaru1")
        result = rp.verify_receipt_against_report(
            receipt=rp.load_receipt(self.receipt_dir, "ashigaru1"),
            role="ashigaru2",
            report_bytes=REPORT_BYTES,
            current_generation=2,
        )
        self.assertEqual("receipt_role_mismatch", result.reason)

    def test_receipt_stale_generation_rejected(self):
        self._write_receipt(generation=2)
        result = rp.verify_receipt_against_report(
            receipt=rp.load_receipt(self.receipt_dir, "ashigaru1"),
            role="ashigaru1",
            report_bytes=REPORT_BYTES,
            current_generation=3,
        )
        self.assertEqual("stale_generation", result.reason)

    def test_missing_receipt_rejected(self):
        result = rp.verify_receipt_against_report(
            receipt=None,
            role="ashigaru1",
            report_bytes=REPORT_BYTES,
            current_generation=2,
        )
        self.assertEqual("missing_receipt", result.reason)

    def test_empty_report_cannot_create_receipt(self):
        with self.assertRaises(ValueError):
            rp.build_receipt(
                role="ashigaru1",
                generation=2,
                pane="%5",
                agent_cli="codex",
                report_path=ASHIGARU_REPORT,
                report_bytes=b"",
                task_id="task_current",
                parent_cmd="cmd_current",
            )

    def test_receipt_is_bound_to_task_and_parent_command(self):
        receipt = rp.build_receipt(
            role="ashigaru1",
            generation=2,
            pane="%5",
            agent_cli="codex",
            report_path=ASHIGARU_REPORT,
            report_bytes=REPORT_BYTES,
            task_id="task_old",
            parent_cmd="cmd_old",
        )
        result = rp.verify_receipt_against_report(
            receipt=receipt,
            role="ashigaru1",
            report_bytes=REPORT_BYTES,
            current_generation=2,
            expected_task_id="task_new",
            expected_parent_cmd="cmd_new",
        )
        self.assertFalse(result.ok)
        self.assertEqual("parent_cmd_mismatch", result.reason)

        result = rp.verify_receipt_against_report(
            receipt={**receipt, "parent_cmd": "cmd_new"},
            role="ashigaru1",
            report_bytes=REPORT_BYTES,
            current_generation=2,
            expected_task_id="task_new",
            expected_parent_cmd="cmd_new",
        )
        self.assertFalse(result.ok)
        self.assertEqual("task_id_mismatch", result.reason)


class CompletionGateTests(unittest.TestCase):
    def setUp(self):
        self.tmp = tempfile.TemporaryDirectory()
        self.root = Path(self.tmp.name)
        self.runtime_dir = self.root / "queue" / "runtime"
        self.receipt_dir = self.runtime_dir / "report_receipts"

    def tearDown(self):
        self.tmp.cleanup()

    def _receipt_for(self, role, report_bytes, *, generation=2, report_path=None, parent_cmd="cmd_048"):
        if report_path is None:
            report_path = str(rp.expected_report_rel(role))
        receipt = rp.build_receipt(
            role=role,
            generation=generation,
            pane=f"%{role}",
            agent_cli="codex",
            report_path=report_path,
            report_bytes=report_bytes,
            parent_cmd=parent_cmd,
            task_id=f"task_{role}",
        )
        rp.write_receipt(self.receipt_dir, role, receipt)

    def test_four_roles_all_receipts_verified(self):
        roles = ["ashigaru1", "ashigaru2", "gunshi", "gunkan"]
        receipts = {}
        role_states = {}
        report_bytes = {}
        for role in roles:
            self._receipt_for(role, f"report {role}\n".encode())
            receipts[role] = rp.load_receipt(self.receipt_dir, role)
            role_states[role] = role_state(role=role, generation=2)
            report_bytes[role] = f"report {role}\n".encode()
        cmd = {"id": "cmd_048", "audit_gate": ["gunshi", "gunkan"]}
        result = rp.validate_completion(
            cmd=cmd,
            task_roles=["ashigaru1", "ashigaru2"],
            receipts=receipts,
            role_states=role_states,
            report_bytes_by_role=report_bytes,
        )
        self.assertTrue(result.ok)
        self.assertEqual("all_receipts_verified", result.reason)

    def test_one_missing_receipt_blocks_completion(self):
        roles = ["ashigaru1", "ashigaru2", "gunshi", "gunkan"]
        receipts = {}
        role_states = {}
        report_bytes = {}
        for role in roles:
            self._receipt_for(role, f"report {role}\n".encode())
            receipts[role] = rp.load_receipt(self.receipt_dir, role)
            role_states[role] = role_state(role=role, generation=2)
            report_bytes[role] = f"report {role}\n".encode()
        # gunkan receipt missing
        receipts.pop("gunkan")
        cmd = {"id": "cmd_048", "audit_gate": ["gunshi", "gunkan"]}
        result = rp.validate_completion(
            cmd=cmd,
            task_roles=["ashigaru1", "ashigaru2"],
            receipts=receipts,
            role_states=role_states,
            report_bytes_by_role=report_bytes,
        )
        self.assertFalse(result.ok)
        self.assertEqual("missing_receipt", result.reason)
        self.assertEqual({"gunkan"}, result.missing_roles)

    def test_tampered_report_blocks_completion(self):
        roles = ["ashigaru1", "ashigaru2"]
        receipts = {}
        role_states = {}
        report_bytes = {}
        for role in roles:
            self._receipt_for(role, f"report {role}\n".encode(), parent_cmd="cmd_009")
            receipts[role] = rp.load_receipt(self.receipt_dir, role)
            role_states[role] = role_state(role=role, generation=2)
        # ashigaru2 report changed after receipt
        report_bytes["ashigaru1"] = b"report ashigaru1\n"
        report_bytes["ashigaru2"] = b"report ashigaru2 TAMPERED\n"
        cmd = {"id": "cmd_009", "audit_gate": []}
        result = rp.validate_completion(
            cmd=cmd,
            task_roles=roles,
            receipts=receipts,
            role_states=role_states,
            report_bytes_by_role=report_bytes,
        )
        self.assertFalse(result.ok)
        self.assertEqual({"ashigaru2"}, result.invalid_roles)
        # blocked ledger records a single representative reason
        ledger = self.runtime_dir / "report_provenance_blocked.yaml"
        rp.append_blocked_ledger(ledger, rp.blocked_ledger_entry(
            cmd_id="cmd_009", reason=result.reason, invalid_roles=result.invalid_roles,
        ))
        entries = rp.load_blocked_ledger(ledger)
        self.assertEqual(1, len(entries))
        self.assertEqual("cmd_009", entries[0]["cmd_id"])

    def test_blocked_ledger_dedupes_by_cmd_and_reason(self):
        ledger = self.runtime_dir / "report_provenance_blocked.yaml"
        entry = rp.blocked_ledger_entry(cmd_id="cmd_010", reason="missing_receipt", missing_roles=["gunkan"])
        rp.append_blocked_ledger(ledger, entry)
        rp.append_blocked_ledger(ledger, entry)
        self.assertEqual(1, len(rp.load_blocked_ledger(ledger)))

    def test_strict_completion_without_required_roles_is_rejected(self):
        result = rp.validate_completion(
            cmd={"id": "cmd_empty", "audit_gate": []},
            task_roles=[],
            receipts={},
            role_states={},
            report_bytes_by_role={},
        )
        self.assertFalse(result.ok)
        self.assertEqual("missing_required_roles", result.reason)

    def test_separate_task_yaml_contributes_role_and_context(self):
        queue_dir = self.root / "queue"
        tasks_dir = queue_dir / "tasks"
        tasks_dir.mkdir(parents=True)
        (tasks_dir / "ashigaru1.yaml").write_text(
            "task_id: task_separate\nparent_cmd: cmd_separate\nstatus: done\n",
            encoding="utf-8",
        )
        contexts = bridge._collect_cmd_task_contexts(queue_dir, {"id": "cmd_separate"})
        self.assertEqual(
            {"task_id": "task_separate", "parent_cmd": "cmd_separate"},
            contexts["ashigaru1"],
        )

    def _prepare_bridge_gate(self, *, receipt_parent_cmd, write_report=True):
        queue_dir = self.root / "queue"
        tasks_dir = queue_dir / "tasks"
        reports_dir = queue_dir / "reports"
        tasks_dir.mkdir(parents=True, exist_ok=True)
        reports_dir.mkdir(parents=True, exist_ok=True)
        self.runtime_dir.mkdir(parents=True, exist_ok=True)
        (self.runtime_dir / "report_provenance_required").touch()
        (tasks_dir / "ashigaru1.yaml").write_text(
            "task_id: task_current\nparent_cmd: cmd_current\nstatus: done\n",
            encoding="utf-8",
        )
        (self.runtime_dir / "role_failover.yaml").write_text(
            yaml.safe_dump({"roles": {"ashigaru1": role_state(generation=2)}}),
            encoding="utf-8",
        )
        report_bytes = b"task_id: task_current\nparent_cmd: cmd_current\nstatus: done\n"
        if write_report:
            (reports_dir / "ashigaru1_report.yaml").write_bytes(report_bytes)
        receipt = rp.build_receipt(
            role="ashigaru1",
            generation=2,
            pane="%5",
            agent_cli="codex",
            report_path=ASHIGARU_REPORT,
            report_bytes=report_bytes,
            task_id="task_current",
            parent_cmd=receipt_parent_cmd,
        )
        rp.write_receipt(self.receipt_dir, "ashigaru1", receipt)

    def test_bridge_rejects_receipt_from_old_parent_command(self):
        self._prepare_bridge_gate(receipt_parent_cmd="cmd_old")
        with mock.patch.object(bridge, "_load_provenance", return_value=rp):
            reason = bridge._command_completion_blocked_by_provenance(
                self.root,
                self.runtime_dir,
                {"id": "cmd_current", "status": "done"},
            )
        self.assertEqual("parent_cmd_mismatch", reason)

    def test_bridge_rejects_missing_report_even_with_receipt(self):
        self._prepare_bridge_gate(receipt_parent_cmd="cmd_current", write_report=False)
        with mock.patch.object(bridge, "_load_provenance", return_value=rp):
            reason = bridge._command_completion_blocked_by_provenance(
                self.root,
                self.runtime_dir,
                {"id": "cmd_current", "status": "done"},
            )
        self.assertEqual("missing_report", reason)


class StrictModeTests(unittest.TestCase):
    def test_no_marker_is_legacy(self):
        with tempfile.TemporaryDirectory() as tmp:
            runtime_dir = Path(tmp) / "queue" / "runtime"
            runtime_dir.mkdir(parents=True)
            # marker absent -> caller must keep legacy relay behavior
            self.assertFalse(rp.is_strict_mode(runtime_dir))

    def test_marker_enables_strict_gate(self):
        with tempfile.TemporaryDirectory() as tmp:
            runtime_dir = Path(tmp) / "queue" / "runtime"
            rp.enable_strict_mode(runtime_dir)
            self.assertTrue(rp.is_strict_mode(runtime_dir))
            # idempotent
            rp.enable_strict_mode(runtime_dir)
            self.assertTrue(rp.is_strict_mode(runtime_dir))


if __name__ == "__main__":
    unittest.main()
