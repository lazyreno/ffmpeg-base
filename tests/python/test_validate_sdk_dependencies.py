import importlib.util
import subprocess
import tempfile
import unittest
from pathlib import Path
from unittest.mock import patch


ROOT = Path(__file__).resolve().parents[2]
SCRIPT = ROOT / "scripts/validate-sdk-dependencies.py"


class DependencyValidatorTest(unittest.TestCase):
    def test_macos_rejects_second_level_host_dependency(self):
        spec = importlib.util.spec_from_file_location("dependency_validator", SCRIPT)
        module = importlib.util.module_from_spec(spec)
        spec.loader.exec_module(module)
        with tempfile.TemporaryDirectory() as temporary:
            sdk = Path(temporary) / "sdk"
            (sdk / "bin").mkdir(parents=True)
            (sdk / "bin" / "ffmpeg").touch()
            (sdk / "bin" / "libfirst.dylib").touch()
            links = {
                "ffmpeg": ["@loader_path/libfirst.dylib"],
                "libfirst.dylib": ["/Users/runner/vcpkg/lib/libsecond.dylib"],
            }
            with patch.object(module, "macos_links", side_effect=lambda p: links[p.name]):
                errors = module.validate_macos_closure(sdk)
            self.assertTrue(any("libsecond.dylib" in error for error in errors))

    def test_missing_copyright_is_an_error(self):
        spec = importlib.util.spec_from_file_location("dependency_validator", SCRIPT)
        module = importlib.util.module_from_spec(spec)
        spec.loader.exec_module(module)
        with tempfile.TemporaryDirectory() as temporary:
            root = Path(temporary)
            copyright_file = root / "installed" / "share" / "libjxl" / "copyright"
            copyright_file.parent.mkdir(parents=True)
            copyright_file.write_text("libjxl license")
            (root / "sdk" / "licenses").mkdir(parents=True)
            errors = module.validate_licenses(root / "sdk", root / "installed")
            self.assertTrue(any("libjxl" in error for error in errors))

    def test_stage_and_validate_ignore_vcpkg_metadata_directories(self):
        spec = importlib.util.spec_from_file_location("dependency_validator", SCRIPT)
        module = importlib.util.module_from_spec(spec)
        spec.loader.exec_module(module)
        with tempfile.TemporaryDirectory() as temporary:
            root = Path(temporary)
            source = root / "source"
            install = root / "install"
            vcpkg = root / "vcpkg"
            sdk = root / "sdk"
            source.mkdir()
            (source / "LICENSE.md").write_text("FFmpeg license")
            for directory in (install / "include", install / "lib", install / "bin"):
                directory.mkdir(parents=True)
            for executable in ("ffmpeg.exe", "ffprobe.exe"):
                (install / "bin" / executable).write_bytes(b"test")
            copyright_file = vcpkg / "share" / "libjxl" / "copyright"
            copyright_file.parent.mkdir(parents=True)
            copyright_file.write_text("libjxl license")
            for metadata in ("hwy", "iconv", "libiconv"):
                (vcpkg / "share" / metadata).mkdir()
            result = subprocess.run(
                ["bash", str(ROOT / "scripts/stage-sdk.sh"), "--source", str(source),
                 "--prefix", str(install), "--output", str(sdk), "--platform", "windows",
                 "--arch", "x86_64", "--vcpkg-root", str(vcpkg)],
                capture_output=True, text=True,
            )
            self.assertEqual(0, result.returncode, result.stderr)
            self.assertEqual("libjxl license", (sdk / "licenses" / "libjxl" / "LICENSE").read_text())
            self.assertEqual([], module.validate_licenses(sdk, vcpkg))


if __name__ == "__main__":
    unittest.main()
