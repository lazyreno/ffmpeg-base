import hashlib
import os
import subprocess
import tempfile
import unittest
from pathlib import Path


ROOT = Path(__file__).resolve().parents[2]
SCRIPT = ROOT / "scripts/bootstrap-pinned-vcpkg-macos.sh"


class BootstrapPinnedVcpkgMacosTest(unittest.TestCase):
    def test_installs_only_asset_matching_pinned_sha512(self):
        with tempfile.TemporaryDirectory() as temporary:
            base = Path(temporary)
            tool = base / "vcpkg-macos"
            tool.write_text("#!/bin/sh\necho pinned-tool\n")
            tool.chmod(0o755)
            checkout = base / "checkout"
            (checkout / "scripts").mkdir(parents=True)
            metadata = checkout / "scripts/vcpkg-tool-metadata.txt"
            digest = hashlib.sha512(tool.read_bytes()).hexdigest()
            metadata.write_text(f"VCPKG_TOOL_RELEASE_TAG=test-tag\nVCPKG_MACOS_SHA={digest}\n")
            fake_bin = base / "fake-bin"
            fake_bin.mkdir()
            gh = fake_bin / "gh"
            gh.write_text('#!/bin/sh\nwhile [ "$#" -gt 0 ]; do\n  if [ "$1" = "-D" ]; then shift; cp "$TEST_ASSET" "$1/vcpkg-macos"; exit; fi\n  shift\ndone\nexit 1\n')
            gh.chmod(0o755)
            env = dict(os.environ, PATH=f"{fake_bin}:{os.environ['PATH']}", TEST_ASSET=str(tool))
            command = ["bash", str(SCRIPT), "--vcpkg-root", str(checkout)]
            valid = subprocess.run(command, env=env, capture_output=True, text=True)
            self.assertEqual(0, valid.returncode, valid.stderr)
            self.assertIn("pinned-tool", valid.stdout)
            self.assertEqual(tool.read_bytes(), (checkout / "vcpkg").read_bytes())

            (checkout / "vcpkg").unlink()
            metadata.write_text("VCPKG_TOOL_RELEASE_TAG=test-tag\nVCPKG_MACOS_SHA=" + "0" * 128 + "\n")
            invalid = subprocess.run(command, env=env, capture_output=True, text=True)
            self.assertNotEqual(0, invalid.returncode)
            self.assertIn("SHA512 mismatch", invalid.stderr)
            self.assertFalse((checkout / "vcpkg").exists())


if __name__ == "__main__":
    unittest.main()
