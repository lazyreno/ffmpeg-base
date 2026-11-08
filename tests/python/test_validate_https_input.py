import importlib.util
import unittest
from pathlib import Path


SCRIPT = Path(__file__).resolve().parents[2] / "scripts/validate-https-input.py"


class HttpsInputTest(unittest.TestCase):
    def test_https_command_uses_local_url_and_disables_fixture_cert_verification(self):
        spec = importlib.util.spec_from_file_location("https_input", SCRIPT)
        module = importlib.util.module_from_spec(spec)
        spec.loader.exec_module(module)
        command = module.https_command(Path("ffmpeg"), 12345)
        self.assertIn("-tls_verify", command)
        self.assertIn("0", command)
        self.assertIn("https://127.0.0.1:12345/sample.wav", command)


if __name__ == "__main__":
    unittest.main()
