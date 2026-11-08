import importlib.util
import subprocess
import unittest
from pathlib import Path
from unittest.mock import patch


SCRIPT = Path(__file__).resolve().parents[2] / "scripts/validate-media-coverage.py"


class MediaCoverageTest(unittest.TestCase):
    def test_failed_transcode_reports_case_and_exit_code(self):
        spec = importlib.util.spec_from_file_location("media_coverage", SCRIPT)
        module = importlib.util.module_from_spec(spec)
        spec.loader.exec_module(module)
        failure = subprocess.CompletedProcess(["ffmpeg"], 7, "", "bad codec")
        with patch.object(module.subprocess, "run", return_value=failure):
            with self.assertRaisesRegex(RuntimeError, "prores.*7.*bad codec"):
                module.run_case("prores", ["ffmpeg"], Path("."))


if __name__ == "__main__":
    unittest.main()
