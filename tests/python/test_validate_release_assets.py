import importlib.util
import json
import tempfile
import unittest
import zipfile
from pathlib import Path


ROOT = Path(__file__).resolve().parents[2]
SCRIPT = ROOT / "scripts/validate-release-assets.py"


class ReleaseAssetsTest(unittest.TestCase):
    def test_rejects_archive_with_wrong_platform_manifest(self):
        spec = importlib.util.spec_from_file_location("release_assets", SCRIPT)
        module = importlib.util.module_from_spec(spec)
        spec.loader.exec_module(module)
        with tempfile.TemporaryDirectory() as temporary:
            archive = Path(temporary) / "release.zip"
            with zipfile.ZipFile(archive, "w") as output:
                output.writestr("sdk/manifest.json", json.dumps({"platform": "windows", "arch": "arm64"}))
                output.writestr("sdk/components.json", "{}")
            errors = module.validate_archive(archive, {"key": "macos-arm64", "os": "macos", "arch": "arm64", "minimumSystemVersion": "11.0"}, {"sdkVersion": "v2", "featureProfile": "v2", "ffmpegVersion": "8.1.2"})
            self.assertTrue(any("platform" in error for error in errors))


if __name__ == "__main__":
    unittest.main()
