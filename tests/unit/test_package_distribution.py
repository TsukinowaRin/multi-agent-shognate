import unittest
from pathlib import Path


ROOT = Path(__file__).resolve().parents[2]


class PackageDistributionContractTests(unittest.TestCase):
    def test_curl_bootstrap_is_release_package_aware(self):
        text = (ROOT / "scripts/shogunate_package_bootstrap.sh").read_text(encoding="utf-8")
        self.assertIn("releases/latest/download/${REPO_NAME}-package.tar.gz", text)
        self.assertIn("releases/download/${VERSION}/${REPO_NAME}-package.tar.gz", text)
        self.assertIn("--strip-components=1", text)
        self.assertIn("first_setup.sh", text)
        self.assertIn("install.bat", text)
        self.assertIn("Shogunate-Uninstaller.bat", text)
        self.assertIn("shogunate pair", text)
        self.assertIn("shogunate_pair_server.py", text)
        self.assertIn("SHOGUNATE_PAIR_PASSWORD", text)

    def test_curl_bootstrap_installs_command_before_first_setup(self):
        text = (ROOT / "scripts/shogunate_package_bootstrap.sh").read_text(encoding="utf-8")
        command_index = text.index('cat > "$BIN_DIR/shogunate"')
        setup_index = text.index('log "run first_setup.sh"')
        self.assertLess(command_index, setup_index)
        self.assertIn("pair)\n        shift || true", text)
        self.assertIn("exec python3 scripts/shogunate_pair_server.py", text)

    def test_npm_wrapper_points_to_curl_bootstrap(self):
        package = (ROOT / "package.json").read_text(encoding="utf-8")
        wrapper = (ROOT / "bin/shogunate.js").read_text(encoding="utf-8")
        self.assertIn('"name": "@tsukinowarin/shogunate"', package)
        self.assertIn('"shogunate": "bin/shogunate.js"', package)
        self.assertIn("shogunate_package_bootstrap.sh", wrapper)
        self.assertIn("shogunate_pair_server.py", wrapper)
        self.assertIn("SHOGUNATE_PAIR_PASSWORD", wrapper)
        self.assertIn("curl -fsSL", wrapper)

    def test_release_workflow_builds_packages_not_installers_or_apks(self):
        text = (ROOT / ".github/workflows/package-release.yml").read_text(encoding="utf-8")
        self.assertIn("v<upstream-version>.<fork-revision>", text)
        self.assertIn("multi-agent-shognate-package.tar.gz", text)
        self.assertIn("multi-agent-shognate-package.zip", text)
        self.assertIn("git archive --format=tar.gz", text)
        self.assertIn("git archive --format=zip", text)
        self.assertIn("fetch-depth: 0", text)
        self.assertIn("git fetch --force --tags", text)
        self.assertNotIn("multi-agent-shognate-installer-", text)
        self.assertNotIn("install.bat", text)
        self.assertNotIn("install.sh", text)
        self.assertNotIn("install.command", text)
        self.assertNotIn("assembleRelease", text)
        self.assertNotIn(".apk", text)

    def test_package_archive_excludes_android_app(self):
        attrs = (ROOT / ".gitattributes").read_text(encoding="utf-8")
        self.assertIn("android/ export-ignore", attrs)

    def test_docs_describe_curl_and_npm_package_distribution(self):
        docs = "\n".join(
            [
                (ROOT / "README.md").read_text(encoding="utf-8"),
                (ROOT / "README_ja.md").read_text(encoding="utf-8"),
            ]
        )
        self.assertIn("curl -fsSL", docs)
        self.assertIn("npx @tsukinowarin/shogunate install", docs)
        self.assertIn("shogunate pair", docs)
        self.assertIn("multi-agent-shognate-package.tar.gz", docs)
        self.assertIn("multi-agent-shognate-package.zip", docs)
        self.assertIn("v5.0.0.0", docs)
        self.assertIn("v5.0.0.12", docs)
        self.assertNotIn("install.bat", docs)
        self.assertNotIn("android/release", docs)
        self.assertNotIn("multi-agent-shognate-installer-<version>", docs)


if __name__ == "__main__":
    unittest.main()
