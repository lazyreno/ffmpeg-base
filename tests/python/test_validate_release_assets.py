import importlib.util
import json
import tempfile
import unittest
import zipfile
from pathlib import Path


ROOT = Path(__file__).resolve().parents[2]
SCRIPT = ROOT / "scripts/validate-release-assets.py"


class ReleaseAssetsTest(unittest.TestCase):
    def test_rejects_macos_tools_without_execute_permission(self):
        spec = importlib.util.spec_from_file_location("release_assets", SCRIPT)
        module = importlib.util.module_from_spec(spec)
        spec.loader.exec_module(module)
        platform = {"key": "macos-arm64", "os": "macos", "arch": "arm64", "minimumSystemVersion": "11.0"}
        sdk = {"sdkVersion": "test", "featureProfile": "test", "ffmpegVersion": "8.1.2"}
        with tempfile.TemporaryDirectory() as temporary:
            archive = Path(temporary) / "release.zip"
            with zipfile.ZipFile(archive, "w") as output:
                output.writestr("sdk/manifest.json", json.dumps({
                    "sdkVersion": "test", "ffmpegVersion": "8.1.2", "featureProfile": "test",
                    "platform": "macos", "arch": "arm64", "minimumSystemVersion": "11.0",
                    "componentsFile": "components.json",
                }))
                output.writestr("sdk/components.json", json.dumps({
                    "featureProfile": "test", "platform": "macos-arm64",
                }))
                for tool in ("ffmpeg", "ffprobe"):
                    member = zipfile.ZipInfo(f"sdk/bin/{tool}")
                    member.create_system = 3
                    member.external_attr = 0o100644 << 16
                    output.writestr(member, b"tool")
            errors = module.validate_archive(archive, platform, sdk)
            for tool in ("ffmpeg", "ffprobe"):
                self.assertTrue(any(tool in error and "not executable" in error for error in errors))

    def test_rejects_archive_with_wrong_platform_manifest(self):
        spec = importlib.util.spec_from_file_location("release_assets", SCRIPT)
        module = importlib.util.module_from_spec(spec)
        spec.loader.exec_module(module)
        with tempfile.TemporaryDirectory() as temporary:
            archive = Path(temporary) / "release.zip"
            with zipfile.ZipFile(archive, "w") as output:
                output.writestr("sdk/manifest.json", json.dumps({"platform": "windows", "arch": "arm64"}))
                output.writestr("sdk/components.json", "{}")
            errors = module.validate_archive(archive, {"key": "macos-arm64", "os": "macos", "arch": "arm64", "minimumSystemVersion": "11.0"}, {"sdkVersion": "test", "featureProfile": "test", "ffmpegVersion": "8.1.2"})
            self.assertTrue(any("platform" in error for error in errors))


if __name__ == "__main__":
    unittest.main()
