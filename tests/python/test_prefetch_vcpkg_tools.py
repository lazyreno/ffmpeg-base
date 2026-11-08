import hashlib
import json
import os
import subprocess
import tempfile
import unittest
from pathlib import Path


ROOT = Path(__file__).resolve().parents[2]
SCRIPT = ROOT / "scripts/prefetch-vcpkg-tools.py"


class PrefetchVcpkgToolsTest(unittest.TestCase):
    def test_caches_only_matching_pinned_archives(self):
        with tempfile.TemporaryDirectory() as temporary:
            base = Path(temporary)
            checkout = base / "vcpkg"
            (checkout / "scripts").mkdir(parents=True)
            assets = base / "assets"
            assets.mkdir()
            entries = []
            for name in ("cmake", "ninja"):
                asset = assets / f"{name}.zip"
                asset.write_bytes(name.encode())
                entries.append({
                    "name": name,
                    "os": "windows",
                    "arch": "arm64",
                    "url": f"https://github.com/owner/{name}/releases/download/v1/{name}.zip",
                    "archive": f"{name}-v1.zip",
                    "sha512": hashlib.sha512(asset.read_bytes()).hexdigest(),
                })
            (checkout / "scripts/vcpkg-tools.json").write_text(json.dumps({"tools": entries}))
            fake_bin = base / "fake-bin"
            fake_bin.mkdir()
            gh = fake_bin / "gh"
            gh.write_text('#!/bin/sh\nwhile [ "$#" -gt 0 ]; do\n  if [ "$1" = "--pattern" ]; then shift; asset="$1"; fi\n  if [ "$1" = "-D" ]; then shift; dest="$1"; fi\n  shift\ndone\ncp "$TEST_ASSETS/$asset" "$dest/$asset"\n')
            gh.chmod(0o755)
            env = dict(os.environ, PATH=f"{fake_bin}:{os.environ['PATH']}", TEST_ASSETS=str(assets))
            command = ["python3", str(SCRIPT), "--vcpkg-root", str(checkout), "--os", "windows", "--arch", "arm64"]
            valid = subprocess.run(command, env=env, capture_output=True, text=True)
            self.assertEqual(0, valid.returncode, valid.stderr)
            self.assertEqual(b"cmake", (checkout / "downloads/cmake-v1.zip").read_bytes())
            self.assertEqual(b"ninja", (checkout / "downloads/ninja-v1.zip").read_bytes())

            entries[0]["sha512"] = "0" * 128
            (checkout / "scripts/vcpkg-tools.json").write_text(json.dumps({"tools": entries}))
            (checkout / "downloads/cmake-v1.zip").unlink()
            invalid = subprocess.run(command, env=env, capture_output=True, text=True)
            self.assertNotEqual(0, invalid.returncode)
            self.assertIn("SHA512 mismatch", invalid.stderr)
            self.assertFalse((checkout / "downloads/cmake-v1.zip").exists())


if __name__ == "__main__":
    unittest.main()
