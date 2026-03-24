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

        update_manager.ROOT = self.root
        update_manager.STATE_DIR = self.state_dir
        update_manager.MANIFEST_PATH = self.state_dir / "install_manifest.json"
        update_manager.NOTICE_PATH = self.notice_path
        update_manager.MERGE_ROOT = self.merge_root

    def tearDown(self):
        update_manager.ROOT = self.original_root
        update_manager.STATE_DIR = self.original_state_dir
        update_manager.MANIFEST_PATH = self.original_manifest
        update_manager.NOTICE_PATH = self.original_notice
        update_manager.MERGE_ROOT = self.original_merge_root
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


if __name__ == "__main__":
    unittest.main()
