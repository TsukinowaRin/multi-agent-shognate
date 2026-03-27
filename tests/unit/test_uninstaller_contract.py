import unittest
from pathlib import Path


ROOT = Path(__file__).resolve().parents[2]
UNINSTALLER = ROOT / "Shogunate-Uninstaller.bat"


class UninstallerContractTests(unittest.TestCase):
    @classmethod
    def setUpClass(cls):
        cls.text = UNINSTALLER.read_text(encoding="utf-8")

    def test_requires_install_manifest(self):
        self.assertIn(r'.shogunate\install_manifest.json', self.text)
        self.assertIn("安全のため、削除対象を特定できない状態ではアンインストールを実行しません。", self.text)

    def test_no_folder_wide_delete_patterns(self):
        self.assertNotIn(r'for /d %%%%D in ^("%SCRIPT_DIR%\\*"^) do rmdir /s /q "%%%%~fD"', self.text)
        self.assertNotIn(r'del /f /q "%SCRIPT_DIR%\\*"', self.text)

    def test_cleanup_uses_manifest_scoped_powershell(self):
        self.assertIn("ConvertFrom-Json", self.text)
        self.assertIn("manifest.PSObject.Properties.Name", self.text)
        self.assertIn("Unrelated files in the same folder are kept.", self.text)
        self.assertIn("Remove-Item -LiteralPath $target -Force -Recurse", self.text)


if __name__ == "__main__":
    unittest.main()
