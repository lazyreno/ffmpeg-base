import json
from pathlib import Path
import unittest


REPO_ROOT = Path(__file__).resolve().parents[2]
PLATFORM_MATRIX = REPO_ROOT / "config" / "platform-matrix.json"
BUILD_SCRIPT = REPO_ROOT / "scripts" / "build-windows-msvc.ps1"


class WindowsRuntimeMatrixTest(unittest.TestCase):
    def test_windows_artifacts_use_native_runners_and_runtime_validation(self):
        platforms = json.loads(PLATFORM_MATRIX.read_text(encoding="utf-8"))["platforms"]
        by_key = {platform["key"]: platform for platform in platforms}

        self.assertEqual("windows-2022", by_key["windows-x86_64"]["runner"])
        self.assertEqual("windows-11-arm", by_key["windows-arm64"]["runner"])
        self.assertEqual("arm64", by_key["windows-arm64"]["msvcArch"])

        script = BUILD_SCRIPT.read_text(encoding="utf-8")
        stage_offset = script.index('scripts/stage-sdk.sh')
        manifest_offset = script.index('scripts/generate-manifest.cmake')
        validator_call = '& $Python $RuntimeCapabilityValidator'
        first_validator_call = script.index(validator_call)
        second_validator_call = script.rindex(validator_call)

        self.assertGreater(first_validator_call, stage_offset)
        self.assertLess(first_validator_call, manifest_offset)
        self.assertGreater(second_validator_call, manifest_offset)

    def test_arm64_build_uses_architecture_matched_pkg_config_for_aom(self):
        script = BUILD_SCRIPT.read_text(encoding="utf-8")

        self.assertIn(
            'return $_.FullName -match "\\\\(clangarm64|usr)\\\\bin\\\\"',
            script,
        )
        self.assertIn('"aom >= 2.0.0"', script)
        self.assertIn(
            '$SdkArch -eq "arm64" -and $_.FullName -match "\\\\clangarm64\\\\bin\\\\(pkg-config|pkgconf)\\.exe$"',
            script,
        )


if __name__ == "__main__":
    unittest.main()
