import hashlib
import json
import os
import subprocess
import tempfile
import unittest
from pathlib import Path


ROOT = Path(__file__).resolve().parents[2]
SCRIPT = ROOT / "scripts/bootstrap-pinned-vcpkg-windows.py"


class BootstrapPinnedVcpkgWindowsTest(unittest.TestCase):
    def test_downloads_matching_asset_and_rejects_mismatch(self):
        with tempfile.TemporaryDirectory() as temporary:
            base = Path(temporary)
            checkout = base / "checkout"
            (checkout / "scripts").mkdir(parents=True)
            (checkout / "scripts/vcpkg-tool-metadata.txt").write_text("VCPKG_TOOL_RELEASE_TAG=test-tag\n")
            asset = base / "vcpkg-arm64.exe"
            asset.write_text("#!/bin/sh\necho pinned-windows-tool\n")
            asset.chmod(0o755)
            lock = base / "vcpkg-lock.json"
            lock.write_text(json.dumps({"toolRelease": "test-tag", "windowsToolSha512": {"arm64": hashlib.sha512(asset.read_bytes()).hexdigest()}}))
            fake_bin = base / "fake-bin"
            fake_bin.mkdir()
            gh = fake_bin / "gh"
            gh.write_text('#!/bin/sh\nwhile [ "$#" -gt 0 ]; do\n  if [ "$1" = "-D" ]; then shift; cp "$TEST_ASSET" "$1/vcpkg-arm64.exe"; exit; fi\n  shift\ndone\nexit 1\n')
            gh.chmod(0o755)
            env = dict(os.environ, PATH=f"{fake_bin}:{os.environ['PATH']}", TEST_ASSET=str(asset))
            command = ["python3", str(SCRIPT), "--vcpkg-root", str(checkout), "--lock-file", str(lock), "--arch", "arm64"]
            valid = subprocess.run(command, env=env, capture_output=True, text=True)
            self.assertEqual(0, valid.returncode, valid.stderr)
            self.assertIn("pinned-windows-tool", valid.stdout)
            self.assertEqual(asset.read_bytes(), (checkout / "vcpkg.exe").read_bytes())

            (checkout / "vcpkg.exe").unlink()
            lock.write_text(json.dumps({"toolRelease": "test-tag", "windowsToolSha512": {"arm64": "0" * 128}}))
            invalid = subprocess.run(command, env=env, capture_output=True, text=True)
            self.assertNotEqual(0, invalid.returncode)
            self.assertIn("SHA512 mismatch", invalid.stderr)
            self.assertFalse((checkout / "vcpkg.exe").exists())


if __name__ == "__main__":
    unittest.main()
