import subprocess
import tempfile
import unittest
from pathlib import Path


ROOT = Path(__file__).resolve().parents[2]
SCRIPT = ROOT / "scripts/patch-windows-mediafoundation.py"
SOURCE = (
    "#define COBJMACROS\n"
    "#if !defined(_WIN32_WINNT) || _WIN32_WINNT < 0x0602\n"
    "#undef _WIN32_WINNT\n"
    "#define _WIN32_WINNT 0x0602\n"
    "#endif\n"
    "\n"
    '#include "mf_utils.h"\n'
)


class WindowsMediaFoundationPatchTest(unittest.TestCase):
    def test_sets_winver_to_match_ffmpeg_mediafoundation_minimum(self):
        with tempfile.TemporaryDirectory() as temporary:
            source = Path(temporary) / "libavcodec" / "mf_utils.c"
            source.parent.mkdir()
            source.write_text(SOURCE)
            result = subprocess.run(["python3", str(SCRIPT), temporary], capture_output=True, text=True)
            self.assertEqual(0, result.returncode, result.stderr)
            patched = source.read_text()
            self.assertIn("#define WINVER 0x0602\n#endif\n\n#include", patched)
            self.assertIn("#define _WIN32_WINNT 0x0602", patched)

    def test_rejects_unexpected_source(self):
        with tempfile.TemporaryDirectory() as temporary:
            source = Path(temporary) / "libavcodec" / "mf_utils.c"
            source.parent.mkdir()
            source.write_text("other source\n")
            result = subprocess.run(["python3", str(SCRIPT), temporary], capture_output=True, text=True)
            self.assertNotEqual(0, result.returncode)
            self.assertEqual("other source\n", source.read_text())


if __name__ == "__main__":
    unittest.main()
