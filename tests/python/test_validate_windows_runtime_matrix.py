from pathlib import Path
import unittest


REPO_ROOT = Path(__file__).resolve().parents[2]
BUILD_SCRIPT = REPO_ROOT / "scripts" / "build-windows-msvc.ps1"


class WindowsRuntimeMatrixTest(unittest.TestCase):
    def test_build_uses_x86_64_profile_overrides_and_architecture(self):
        script = BUILD_SCRIPT.read_text(encoding="utf-8")
        self.assertIn("$ProfileConfig.configure.windows_x86_64", script)
        self.assertIn("SDK_ARCH=$SdkArch", script)

    def test_windows_artifacts_run_capability_validation_around_manifest_generation(self):
        script = BUILD_SCRIPT.read_text(encoding="utf-8")
        stage_offset = script.index('scripts/stage-sdk.sh')
        manifest_offset = script.index('scripts/generate-manifest.cmake')
        validator_call = '& $Python $RuntimeCapabilityValidator'
        first_validator_call = script.index(validator_call)
        second_validator_call = script.rindex(validator_call)

        self.assertGreater(first_validator_call, stage_offset)
        self.assertLess(first_validator_call, manifest_offset)
        self.assertGreater(second_validator_call, manifest_offset)

    def test_build_uses_architecture_matched_msys2_pkg_config_for_aom(self):
        script = BUILD_SCRIPT.read_text(encoding="utf-8")

        self.assertIn('$env:MSYS2_LOCATION', script)
        self.assertIn('"clangarm64/bin/pkg-config.exe"', script)
        self.assertIn('"mingw64/bin/pkg-config.exe"', script)
        self.assertIn('"aom >= 2.0.0"', script)

    def test_bash_build_command_is_run_from_a_script_file(self):
        script = BUILD_SCRIPT.read_text(encoding="utf-8")

        self.assertIn("$ConfigureScriptPath", script)
        self.assertIn("Set-Content -LiteralPath $ConfigureScriptPath", script)
        self.assertIn('& msys2 -c "bash ', script)


if __name__ == "__main__":
    unittest.main()
