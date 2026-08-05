import subprocess
import sys
import tempfile
import unittest
from pathlib import Path


REPO_ROOT = Path(__file__).resolve().parents[2]
VALIDATOR = REPO_ROOT / "scripts" / "validate-windows-sdk-subsystem.py"


class ValidateWindowsSdkSubsystemTest(unittest.TestCase):
    def run_validator(self, executable_output, dll_output):
        with tempfile.TemporaryDirectory() as temporary_directory:
            temporary_path = Path(temporary_directory)
            sdk_root = temporary_path / "sdk"
            executable_path = sdk_root / "bin" / "ffmpeg.exe"
            dll_path = sdk_root / "bin" / "avcodec-62.dll"
            executable_path.parent.mkdir(parents=True)
            executable_path.write_bytes(b"executable fixture")
            dll_path.write_bytes(b"dll fixture")

            dumpbin = temporary_path / "dumpbin"
            dumpbin.write_text(
                "#!/bin/sh\n"
                "case \"$2\" in\n"
                f"  *avcodec-62.dll) printf '%s\\n' '{dll_output}' ;;\n"
                f"  *) printf '%s\\n' '{executable_output}' ;;\n"
                "esac\n",
                encoding="utf-8",
            )
            dumpbin.chmod(dumpbin.stat().st_mode | 0o111)

            return subprocess.run(
                [
                    sys.executable,
                    str(VALIDATOR),
                    "--sdk-root",
                    str(sdk_root),
                    "--maximum-subsystem-version",
                    "6.1",
                    "--dumpbin",
                    str(dumpbin),
                ],
                text=True,
                capture_output=True,
            )

    def test_accepts_windows_7_subsystem_for_executable_and_dll(self):
        result = self.run_validator("6.01 subsystem version", "6.01 subsystem version")
        self.assertEqual(0, result.returncode, result.stderr)

    def test_rejects_dll_targeting_newer_than_windows_7(self):
        result = self.run_validator("6.01 subsystem version", "6.02 subsystem version")
        self.assertNotEqual(0, result.returncode)
        self.assertIn("avcodec-62.dll: subsystem version 6.02 exceeds 6.1", result.stderr)

    def test_rejects_binary_without_subsystem_version(self):
        result = self.run_validator("headers without a version", "6.01 subsystem version")
        self.assertNotEqual(0, result.returncode)
        self.assertIn("ffmpeg.exe does not report a subsystem version", result.stderr)


if __name__ == "__main__":
    unittest.main()
