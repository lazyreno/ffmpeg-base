import subprocess
import tempfile
import unittest
from pathlib import Path


ROOT = Path(__file__).resolve().parents[2]
MEDIAFOUNDATION_PATCH = ROOT / "scripts/patch-windows-mediafoundation.py"
RESPONSE_FILE_PATCH = ROOT / "scripts/patch-windows-response-file.py"
MEDIAFOUNDATION_SOURCE = (
    "#define COBJMACROS\n"
    "#if !defined(_WIN32_WINNT) || _WIN32_WINNT < 0x0602\n"
    "#undef _WIN32_WINNT\n"
    "#define _WIN32_WINNT 0x0602\n"
    "#endif\n"
    "\n"
    '#include "mf_utils.h"\n'
)


class WindowsPatchTest(unittest.TestCase):
    def test_mediafoundation_patch_sets_winver_to_ffmpeg_minimum(self):
        with tempfile.TemporaryDirectory() as temporary:
            source = Path(temporary) / "libavcodec" / "mf_utils.c"
            source.parent.mkdir()
            source.write_text(MEDIAFOUNDATION_SOURCE)

            result = subprocess.run(
                ["python3", str(MEDIAFOUNDATION_PATCH), temporary],
                capture_output=True,
                text=True,
            )

            self.assertEqual(0, result.returncode, result.stderr)
            patched = source.read_text()
            self.assertIn("#define WINVER 0x0602\n#endif\n\n#include", patched)
            self.assertIn("#define _WIN32_WINNT 0x0602", patched)

    def test_mediafoundation_patch_rejects_unexpected_source_without_changes(self):
        with tempfile.TemporaryDirectory() as temporary:
            source = Path(temporary) / "libavcodec" / "mf_utils.c"
            source.parent.mkdir()
            source.write_text("other source\n")

            result = subprocess.run(
                ["python3", str(MEDIAFOUNDATION_PATCH), temporary],
                capture_output=True,
                text=True,
            )

            self.assertNotEqual(0, result.returncode)
            self.assertEqual("other source\n", source.read_text())

    def test_response_file_patch_replaces_shell_echo_with_make_file_function(self):
        with tempfile.TemporaryDirectory() as temporary:
            library = Path(temporary) / "ffbuild" / "library.mak"
            library.parent.mkdir()
            library.write_text("\t$(Q)echo $$(filter %.o,$$^) > $$@.objs\n")

            result = subprocess.run(
                ["python3", str(RESPONSE_FILE_PATCH), temporary],
                capture_output=True,
                text=True,
            )

            self.assertEqual(0, result.returncode, result.stderr)
            self.assertEqual(
                "\t$(Q)$$(file >$$@.objs,$$(filter %.o,$$^))\n",
                library.read_text(),
            )

    def test_response_file_patch_rejects_unexpected_source_without_changes(self):
        with tempfile.TemporaryDirectory() as temporary:
            library = Path(temporary) / "ffbuild" / "library.mak"
            library.parent.mkdir()
            library.write_text("other recipe\n")

            result = subprocess.run(
                ["python3", str(RESPONSE_FILE_PATCH), temporary],
                capture_output=True,
                text=True,
            )

            self.assertNotEqual(0, result.returncode)
            self.assertEqual("other recipe\n", library.read_text())


if __name__ == "__main__":
    unittest.main()
