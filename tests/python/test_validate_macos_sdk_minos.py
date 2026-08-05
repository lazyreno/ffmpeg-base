import subprocess
import sys
import tempfile
import unittest
from pathlib import Path


REPO_ROOT = Path(__file__).resolve().parents[2]
VALIDATOR = REPO_ROOT / "scripts" / "validate-macos-sdk-minos.py"


class ValidateMacosSdkMinosTest(unittest.TestCase):
    def run_validator(self, vtool_output):
        with tempfile.TemporaryDirectory() as temporary_directory:
            temporary_path = Path(temporary_directory)
            sdk_root = temporary_path / "sdk"
            binary_path = sdk_root / "bin" / "ffmpeg"
            binary_path.parent.mkdir(parents=True)
            binary_path.write_bytes(b"fixture")

            file_tool = temporary_path / "file"
            file_tool.write_text("#!/bin/sh\nprintf '%s\\n' 'Mach-O 64-bit executable arm64'\n", encoding="utf-8")
            file_tool.chmod(file_tool.stat().st_mode | 0o111)

            vtool = temporary_path / "vtool"
            vtool.write_text(f"#!/bin/sh\nprintf '%s\\n' '{vtool_output}'\n", encoding="utf-8")
            vtool.chmod(vtool.stat().st_mode | 0o111)

            return subprocess.run(
                [
                    sys.executable,
                    str(VALIDATOR),
                    "--sdk-root",
                    str(sdk_root),
                    "--minimum-system-version",
                    "11.0",
                    "--file-tool",
                    str(file_tool),
                    "--vtool",
                    str(vtool),
                ],
                text=True,
                capture_output=True,
            )

    def test_accepts_minos_at_the_declared_minimum(self):
        result = self.run_validator("minos 11.0")
        self.assertEqual(0, result.returncode, result.stderr)

    def test_rejects_minos_above_11(self):
        result = self.run_validator("minos 12.0")
        self.assertNotEqual(0, result.returncode)
        self.assertIn("12.0 exceeds 11.0", result.stderr)

    def test_rejects_missing_minos(self):
        result = self.run_validator("no build version")
        self.assertNotEqual(0, result.returncode)
        self.assertIn("does not report minos", result.stderr)


if __name__ == "__main__":
    unittest.main()
