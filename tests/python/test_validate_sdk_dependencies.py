import importlib.util
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
            (root / "installed" / "share" / "libjxl").mkdir(parents=True)
            (root / "sdk" / "licenses").mkdir(parents=True)
            errors = module.validate_licenses(root / "sdk", root / "installed")
            self.assertTrue(any("libjxl" in error for error in errors))


if __name__ == "__main__":
    unittest.main()
