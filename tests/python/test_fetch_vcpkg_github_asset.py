import hashlib
import importlib.util
import tempfile
import unittest
from pathlib import Path
from unittest.mock import patch


SCRIPT = Path(__file__).resolve().parents[2] / "scripts/fetch-vcpkg-github-asset.py"


class FetchVcpkgGithubAssetTest(unittest.TestCase):
    def test_archive_uses_codeload_and_preserves_pinned_bytes(self):
        spec = importlib.util.spec_from_file_location("fetch_asset", SCRIPT)
        module = importlib.util.module_from_spec(spec)
        spec.loader.exec_module(module)
        data = b"pinned source archive"
        with tempfile.TemporaryDirectory() as temporary:
            destination = Path(temporary) / "meson.tar.gz"
            with patch.object(module, "urlopen") as open_url:
                open_url.return_value.__enter__.return_value.read.return_value = data
                module.fetch(
                    "https://github.com/mesonbuild/meson/archive/1.9.0.tar.gz",
                    hashlib.sha512(data).hexdigest(), destination,
                )
                self.assertEqual(data, destination.read_bytes())
                self.assertEqual(
                    "https://codeload.github.com/mesonbuild/meson/tar.gz/1.9.0",
                    open_url.call_args.args[0],
                )

            destination.unlink()
            with patch.object(module, "urlopen") as open_url, patch.object(module, "sleep"):
                response = open_url.return_value
                response.__enter__.return_value.read.return_value = data
                open_url.side_effect = [TimeoutError("transient"), response]
                module.fetch("https://github.com/mesonbuild/meson/archive/1.9.0.tar.gz", hashlib.sha512(data).hexdigest(), destination)
                self.assertEqual(2, open_url.call_count)
                self.assertEqual(data, destination.read_bytes())

            destination.unlink()
            with patch.object(module, "urlopen") as open_url:
                open_url.return_value.__enter__.return_value.read.return_value = data
                with self.assertRaisesRegex(ValueError, "SHA512 mismatch"):
                    module.fetch("https://github.com/mesonbuild/meson/archive/1.9.0.tar.gz", "0" * 128, destination)
                self.assertFalse(destination.exists())


if __name__ == "__main__":
    unittest.main()
