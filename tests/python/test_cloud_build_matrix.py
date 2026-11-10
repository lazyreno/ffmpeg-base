import json
import subprocess
import unittest
from pathlib import Path


ROOT = Path(__file__).resolve().parents[2]


class CloudBuildMatrixTest(unittest.TestCase):
    def test_generated_matrix_has_native_runners(self):
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
    def test_build_prepares_pinned_tools_and_macos_autotools(self):
        workflow = (ROOT / ".github/workflows/build-desktop.yml").read_text()
        self.assertEqual(1, workflow.count("release: false"))
        self.assertEqual(1, workflow.count("scripts/bootstrap-pinned-vcpkg-macos.sh"))
        self.assertEqual(1, workflow.count("scripts/bootstrap-pinned-vcpkg-windows.py"))
        self.assertEqual(1, workflow.count("& $env:FFMPEG_NASM -v"))
        self.assertEqual(1, workflow.count("VCPKG_DOWNLOADS: ${{ github.workspace }}/.vcpkg-root/downloads"))
        self.assertIn("uses: actions/cache/restore@v4", workflow)
        self.assertIn("uses: actions/cache/save@v4", workflow)
        self.assertEqual(1, workflow.count("if: steps.vcpkg-cache.outputs.cache-hit != 'true'"))
        self.assertLess(workflow.index("uses: actions/cache/save@v4"), workflow.index("- name: Build macOS SDK"))
        self.assertEqual(1, workflow.count("python3 scripts/prefetch-vcpkg-tools.py"))
        self.assertEqual(1, workflow.count("python scripts/prefetch-vcpkg-tools.py"))
        self.assertIn("brew install autoconf autoconf-archive automake libtool", workflow)
        self.assertIn("glibtoolize", workflow)
        self.assertIn("X_VCPKG_ASSET_SOURCES", workflow)
        self.assertIn("fetch-vcpkg-github-asset.py", workflow)
        self.assertIn("(Get-Command python -ErrorAction Stop).Source", workflow)
        self.assertIn('$env:X_VCPKG_ASSET_SOURCES = "x-script,$python', workflow)

    def test_sdk_transfer_archive_uses_cross_platform_paths(self):
        workflow = (ROOT / ".github/workflows/build-desktop.yml").read_text()
        self.assertIn('-cf "./${SDK_ARTIFACT_NAME}.tar"', workflow)
        self.assertIn('path: ${{ github.workspace }}/${{ steps.sdk-artifact.outputs.name }}.tar', workflow)

    def test_windows_pkg_config_is_installed_independently_of_vcpkg_cache(self):
        workflow = (ROOT / ".github/workflows/build-desktop.yml").read_text()
        self.assertIn("mingw-w64-clang-aarch64-pkgconf", workflow)
        self.assertIn("mingw-w64-x86_64-pkgconf", workflow)
        self.assertIn("MSYS2_LOCATION: ${{ steps.msys2.outputs.msys2-location }}", workflow)


if __name__ == "__main__":
    unittest.main()
