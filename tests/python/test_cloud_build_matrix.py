import json
import subprocess
import unittest
from pathlib import Path


ROOT = Path(__file__).resolve().parents[2]


class CloudBuildMatrixTest(unittest.TestCase):
    def test_generated_matrix_has_native_runners_without_legacy_profiles(self):
        result = subprocess.run(
            ["python3", str(ROOT / "scripts/generate-github-matrix.py")],
            cwd=ROOT,
            check=True,
            capture_output=True,
            text=True,
        )
        platforms = {item["key"]: item for item in json.loads(result.stdout)["include"]}
        self.assertEqual(
            {
                "macos-arm64": ("macos-15", "arm64-osx"),
                "macos-x86_64": ("macos-15-intel", "x64-osx"),
                "windows-x86_64": ("windows-2022", "x64-windows"),
                "windows-arm64": ("windows-11-arm", "arm64-windows"),
            },
            {key: (item["runner"], item["triplet"]) for key, item in platforms.items()},
        )
        for item in platforms.values():
            self.assertNotIn("profile", item)

    def test_manual_build_uses_generated_matrix_without_preflight_or_publish(self):
        workflow = (ROOT / ".github/workflows/build-desktop.yml").read_text()
        self.assertNotIn("preflight-sdk:", workflow)
        self.assertIn("needs: prepare-matrix", workflow)
        self.assertIn("if: github.event_name == 'workflow_dispatch'", workflow)
        self.assertNotIn("publish-release:", workflow)
        self.assertNotIn('      - "v*"', workflow)

    def test_build_prepares_pinned_tools_and_macos_autotools(self):
        workflow = (ROOT / ".github/workflows/build-desktop.yml").read_text()
        self.assertEqual(1, workflow.count("release: false"))
        self.assertEqual(1, workflow.count("scripts/bootstrap-pinned-vcpkg-macos.sh"))
        self.assertEqual(1, workflow.count("scripts/bootstrap-pinned-vcpkg-windows.py"))
        self.assertEqual(1, workflow.count("& $env:FFMPEG_NASM -v"))
        self.assertNotIn("\n          nasm -v\n", workflow)
        self.assertEqual(1, workflow.count("VCPKG_DOWNLOADS: ${{ github.workspace }}/.vcpkg-root/downloads"))
        self.assertEqual(1, workflow.count("python3 scripts/prefetch-vcpkg-tools.py"))
        self.assertEqual(1, workflow.count("python scripts/prefetch-vcpkg-tools.py"))
        self.assertIn("brew install autoconf autoconf-archive automake libtool", workflow)
        self.assertIn("glibtoolize", workflow)


if __name__ == "__main__":
    unittest.main()
