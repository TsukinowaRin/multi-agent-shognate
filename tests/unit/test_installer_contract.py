import re
import unittest
from pathlib import Path


ROOT = Path(__file__).resolve().parents[2]


class InstallerContractTests(unittest.TestCase):
    def test_unix_installers_are_release_ref_aware(self):
        text = (ROOT / "install.sh").read_text(encoding="utf-8")
        self.assertIn('REPO_REF="main"', text)
        self.assertIn('REPO_REF_KIND="heads"', text)
        self.assertIn('REPO_VERSION_LABEL="main"', text)
        self.assertIn("/archive/refs/${REPO_REF_KIND}/${REPO_REF}.zip", text)
        self.assertIn("apply-source-release", text)
        self.assertIn("bash first_setup.sh", text)

    def test_macos_command_delegates_to_install_sh(self):
        text = (ROOT / "install.command").read_text(encoding="utf-8")
        self.assertIn('"$SCRIPT_DIR/install.sh"', text)
        self.assertIn("Press Enter to close", text)

    def test_release_workflow_builds_all_installer_assets(self):
        text = (ROOT / ".github/workflows/android-release.yml").read_text(encoding="utf-8")
        self.assertIn("v<upstream-version>.<fork-revision>", text)
        self.assertIn("multi-agent-shognate-installer-${VERSION}.bat", text)
        self.assertIn("multi-agent-shognate-installer-${VERSION}.sh", text)
        self.assertIn("multi-agent-shognate-installer-${VERSION}.command", text)
        self.assertIn('("command"', text)
        self.assertIn("Press Enter to close this window", text)
        self.assertIn("REPO_REF={tag}", text)
        self.assertIn('REPO_REF_KIND="tags"', text)
        self.assertRegex(text, r"\^\(android-\)\?v\[0-9\]")

    def test_docs_use_upstream_plus_fork_version_examples(self):
        docs = "\n".join(
            [
                (ROOT / "README.md").read_text(encoding="utf-8"),
                (ROOT / "README_ja.md").read_text(encoding="utf-8"),
                (ROOT / "android/release/README.md").read_text(encoding="utf-8"),
            ]
        )
        self.assertIn("v4.6.0.0", docs)
        self.assertIn("v4.6.0.12", docs)
        self.assertIn("multi-agent-shognate-installer-<version>.sh", docs)
        self.assertIn("multi-agent-shognate-installer-<version>.command", docs)
        self.assertIn("moving `main`", docs)


if __name__ == "__main__":
    unittest.main()
