import subprocess
import tempfile
import unittest
from pathlib import Path


ROOT = Path(__file__).resolve().parents[2]
SCRIPT = ROOT / "scripts/patch-windows-response-file.py"


class WindowsResponseFilePatchTest(unittest.TestCase):
    def test_replaces_shell_echo_with_make_file_function(self):
        with tempfile.TemporaryDirectory() as temporary:
            library = Path(temporary) / "ffbuild" / "library.mak"
            library.parent.mkdir()
            library.write_text("\t$(Q)echo $$(filter %.o,$$^) > $$@.objs\n")
            result = subprocess.run(["python3", str(SCRIPT), temporary], capture_output=True, text=True)
            self.assertEqual(0, result.returncode, result.stderr)
            self.assertEqual("\t$(Q)$$(file >$$@.objs,$$(filter %.o,$$^))\n", library.read_text())

    def test_rejects_unexpected_source(self):
        with tempfile.TemporaryDirectory() as temporary:
            library = Path(temporary) / "ffbuild" / "library.mak"
            library.parent.mkdir()
            library.write_text("other recipe\n")
            result = subprocess.run(["python3", str(SCRIPT), temporary], capture_output=True, text=True)
            self.assertNotEqual(0, result.returncode)
            self.assertEqual("other recipe\n", library.read_text())


if __name__ == "__main__":
    unittest.main()
