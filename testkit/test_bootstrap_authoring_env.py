import unittest
from pathlib import Path

BUILDER_ROOT = Path(__file__).resolve().parents[1]
WINDOWS_BOOTSTRAP = BUILDER_ROOT / "tools" / "bootstrap-authoring-env.ps1"


class WindowsBootstrapEncodingTests(unittest.TestCase):
    def test_generated_project_files_are_guarded_as_utf8_without_bom(self) -> None:
        script = WINDOWS_BOOTSTRAP.read_text(encoding="utf-8")

        self.assertNotIn("-Encoding utf8", script)
        self.assertIn("New-Object System.Text.UTF8Encoding($false)", script)
        self.assertIn("WriteAllText($PipConfigPath, $PipConfig, $Utf8NoBom)", script)
        self.assertIn("Assert-NoUtf8Bom $PipConfigPath", script)
        self.assertIn('Assert-NoUtf8Bom (Join-Path $ProjectRoot ".gitignore")', script)
        self.assertIn("Assert-NoUtf8Bom $EnvFile", script)
        self.assertIn("$bytes[0] -eq 0xEF", script)
        self.assertIn("$bytes[1] -eq 0xBB", script)
        self.assertIn("$bytes[2] -eq 0xBF", script)


if __name__ == "__main__":
    unittest.main()
