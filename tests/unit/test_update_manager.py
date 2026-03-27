import json
import os
import sys
import tempfile
import unittest
from pathlib import Path

import importlib.util
import yaml


ROOT = Path(__file__).resolve().parents[2]
MODULE_PATH = ROOT / "scripts" / "update_manager.py"
SPEC = importlib.util.spec_from_file_location("update_manager", MODULE_PATH)
update_manager = importlib.util.module_from_spec(SPEC)
assert SPEC.loader is not None
sys.modules[SPEC.name] = update_manager
SPEC.loader.exec_module(update_manager)


class UpdateManagerApplySnapshotTests(unittest.TestCase):
    def setUp(self):
        self.temp_dir = tempfile.TemporaryDirectory(prefix="mas-update-test-")
        self.root = Path(self.temp_dir.name) / "repo"
        self.root.mkdir(parents=True)
        self.state_dir = self.root / ".shogunate"
        self.merge_root = self.state_dir / "merge-candidates"
        self.notice_path = self.state_dir / "pending_merge_notice.json"

        self.original_root = update_manager.ROOT
        self.original_state_dir = update_manager.STATE_DIR
        self.original_manifest = update_manager.MANIFEST_PATH
        self.original_notice = update_manager.NOTICE_PATH
        self.original_merge_root = update_manager.MERGE_ROOT
        self.original_pending = update_manager.PENDING_UPDATE_PATH

        update_manager.ROOT = self.root
        update_manager.STATE_DIR = self.state_dir
        update_manager.MANIFEST_PATH = self.state_dir / "install_manifest.json"
        update_manager.NOTICE_PATH = self.notice_path
        update_manager.MERGE_ROOT = self.merge_root
        update_manager.PENDING_UPDATE_PATH = self.state_dir / "pending_update.json"

    def tearDown(self):
        update_manager.ROOT = self.original_root
        update_manager.STATE_DIR = self.original_state_dir
        update_manager.MANIFEST_PATH = self.original_manifest
        update_manager.NOTICE_PATH = self.original_notice
        update_manager.MERGE_ROOT = self.original_merge_root
        update_manager.PENDING_UPDATE_PATH = self.original_pending
        self.temp_dir.cleanup()

    def _write(self, rel: str, content: str):
        path = self.root / rel
        path.parent.mkdir(parents=True, exist_ok=True)
        path.write_text(content, encoding="utf-8")
        return path

    def _source_dir(self, files: dict[str, str]) -> Path:
        source_root = Path(self.temp_dir.name) / "source"
        source_root.mkdir(exist_ok=True)
        for rel, content in files.items():
            path = source_root / rel
            path.parent.mkdir(parents=True, exist_ok=True)
            path.write_text(content, encoding="utf-8")
        return source_root

    def test_replaces_unmodified_file(self):
        self._write("README.md", "old\n")
        old_manifest = {"README.md": update_manager.sha256_file(self.root / "README.md")}
        source = self._source_dir({"README.md": "new\n"})

        result = update_manager.apply_release_snapshot(
            source_root=source,
            version_before="v1",
            version_after="v2",
            old_manifest=old_manifest,
            preserve_patterns=[],
        )

        self.assertTrue(result.applied)
        self.assertEqual((self.root / "README.md").read_text(encoding="utf-8"), "new\n")
        self.assertIn("README.md", result.updated)

    def test_keeps_local_change_and_writes_merge_candidate(self):
        self._write("README.md", "local edit\n")
        old_manifest = {"README.md": "oldhash"}
        source = self._source_dir({"README.md": "incoming\n"})

        result = update_manager.apply_release_snapshot(
            source_root=source,
            version_before="v1",
            version_after="v2",
            old_manifest=old_manifest,
            preserve_patterns=[],
        )

        self.assertEqual((self.root / "README.md").read_text(encoding="utf-8"), "local edit\n")
        self.assertIn("README.md", result.conflicts)
        incoming = list(self.merge_root.rglob("README.md"))
        self.assertTrue(incoming)
        self.assertEqual(incoming[0].read_text(encoding="utf-8"), "incoming\n")
        notice = json.loads(self.notice_path.read_text(encoding="utf-8"))
        self.assertEqual(notice["conflicts"], ["README.md"])
        queue = yaml.safe_load((self.root / "queue" / "shogun_to_karo.yaml").read_text(encoding="utf-8"))
        self.assertEqual(queue[-1]["status"], "pending")
        self.assertIn("merge-candidates", queue[-1]["command"])

    def test_preserve_pattern_skips_copy(self):
        self._write("memory/global_context.md", "keep me\n")
        old_manifest = {"memory/global_context.md": update_manager.sha256_file(self.root / "memory/global_context.md")}
        source = self._source_dir({"memory/global_context.md": "incoming\n"})

        result = update_manager.apply_release_snapshot(
            source_root=source,
            version_before="v1",
            version_after="v2",
            old_manifest=old_manifest,
            preserve_patterns=["memory/global_context.md"],
        )

        self.assertEqual((self.root / "memory/global_context.md").read_text(encoding="utf-8"), "keep me\n")
        self.assertIn("memory/global_context.md", result.preserved)

    def test_emit_merge_command_can_be_disabled(self):
        self._write("README.md", "local edit\n")
        old_manifest = {"README.md": "oldhash"}
        source = self._source_dir({"README.md": "incoming\n"})

        update_manager.apply_release_snapshot(
            source_root=source,
            version_before="v1",
            version_after="v2",
            old_manifest=old_manifest,
            preserve_patterns=[],
            emit_merge_command=False,
        )

        self.assertFalse((self.root / "queue" / "shogun_to_karo.yaml").exists())

    def test_dry_run_reports_conflict_without_writing_files(self):
        self._write("README.md", "local edit\n")
        old_manifest = {"README.md": "oldhash"}
        source = self._source_dir({"README.md": "incoming\n"})

        result = update_manager.apply_release_snapshot(
            source_root=source,
            version_before="v1",
            version_after="v2",
            old_manifest=old_manifest,
            preserve_patterns=[],
            dry_run=True,
        )

        self.assertEqual((self.root / "README.md").read_text(encoding="utf-8"), "local edit\n")
        self.assertIn("README.md", result.conflicts)
        self.assertEqual(list(self.merge_root.rglob("*")), [])
        self.assertFalse(self.notice_path.exists())
        self.assertFalse((self.root / "queue" / "shogun_to_karo.yaml").exists())
        self.assertFalse(update_manager.MANIFEST_PATH.exists())


class UpdateManagerPendingUpdateTests(unittest.TestCase):
    def setUp(self):
        self.temp_dir = tempfile.TemporaryDirectory(prefix="mas-pending-update-test-")
        self.root = Path(self.temp_dir.name) / "repo"
        self.root.mkdir(parents=True)
        self.state_dir = self.root / ".shogunate"

        self.original_root = update_manager.ROOT
        self.original_state_dir = update_manager.STATE_DIR
        self.original_state_path = update_manager.STATE_PATH
        self.original_pending_path = update_manager.PENDING_UPDATE_PATH

        update_manager.ROOT = self.root
        update_manager.STATE_DIR = self.state_dir
        update_manager.STATE_PATH = self.state_dir / "install_state.json"
        update_manager.PENDING_UPDATE_PATH = self.state_dir / "pending_update.json"

    def tearDown(self):
        update_manager.ROOT = self.original_root
        update_manager.STATE_DIR = self.original_state_dir
        update_manager.STATE_PATH = self.original_state_path
        update_manager.PENDING_UPDATE_PATH = self.original_pending_path
        self.temp_dir.cleanup()

    def test_queue_update_request_writes_pending_file(self):
        payload = update_manager.queue_update_request("manual", "android")

        self.assertEqual(payload["action"], "manual")
        self.assertEqual(payload["requested_by"], "android")
        stored = json.loads(update_manager.PENDING_UPDATE_PATH.read_text(encoding="utf-8"))
        self.assertEqual(stored["status"], "queued")

    def test_apply_pending_dispatches_manual_update(self):
        update_manager.queue_update_request("manual", "android")
        original_run_update = update_manager.run_update

        def fake_run_update(mode):
            self.assertEqual(mode, "manual")
            return True, "v-test"

        update_manager.run_update = fake_run_update
        try:
            applied, version = update_manager.apply_pending_update_request()
        finally:
            update_manager.run_update = original_run_update

        self.assertTrue(applied)
        self.assertEqual(version, "v-test")
        self.assertFalse(update_manager.PENDING_UPDATE_PATH.exists())

    def test_apply_pending_dispatches_upstream_sync(self):
        update_manager.queue_update_request("upstream-sync", "android")
        original_upstream_sync = update_manager.upstream_sync

        def fake_upstream_sync(dry_run=False):
            self.assertFalse(dry_run)
            return True, "upstream-123"

        update_manager.upstream_sync = fake_upstream_sync
        try:
            applied, version = update_manager.apply_pending_update_request()
        finally:
            update_manager.upstream_sync = original_upstream_sync

        self.assertTrue(applied)
        self.assertEqual(version, "upstream-123")
        self.assertFalse(update_manager.PENDING_UPDATE_PATH.exists())

    def test_apply_pending_invalid_action_is_marked_failed(self):
        update_manager.ensure_state_dir()
        update_manager.write_json(
            update_manager.PENDING_UPDATE_PATH,
            {"action": "bad-action", "requested_by": "android", "status": "queued"},
        )

        applied, _ = update_manager.apply_pending_update_request()

        self.assertFalse(applied)
        stored = json.loads(update_manager.PENDING_UPDATE_PATH.read_text(encoding="utf-8"))
        self.assertEqual(stored["status"], "failed")
        self.assertIn("unsupported action", stored["last_error"])


class UpdateManagerInstallModeDetectionTests(unittest.TestCase):
    def setUp(self):
        self.temp_dir = tempfile.TemporaryDirectory(prefix="mas-install-mode-test-")
        self.root = Path(self.temp_dir.name) / "repo"
        self.root.mkdir(parents=True)

        self.original_root = update_manager.ROOT
        update_manager.ROOT = self.root

    def tearDown(self):
        update_manager.ROOT = self.original_root
        self.temp_dir.cleanup()

    def test_release_state_wins_over_embedded_git_checkout(self):
        git_dir = self.root / ".git"
        git_dir.mkdir(parents=True, exist_ok=True)

        original_git = update_manager.git

        def fake_git(args, check=True):
            class Result:
                stdout = "feature/host-project\n"
            return Result()

        update_manager.git = fake_git
        try:
            mode = update_manager.detect_install_mode({"install_mode": "release"})
        finally:
            update_manager.git = original_git

        self.assertEqual(mode, "release")


if __name__ == "__main__":
    unittest.main()
