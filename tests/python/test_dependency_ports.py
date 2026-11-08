import json
import unittest
from pathlib import Path


ROOT = Path(__file__).resolve().parents[2]
PORTS = "mp3lame libvpx aom opus libvorbis opencore-amr x264 x265 zlib bzip2 liblzma libiconv libxml2 dav1d libwebp libjxl openjpeg vo-amrwbenc speex libgsm libass freetype harfbuzz fontconfig fribidi soxr rubberband zimg svt-av1 libopenmpt libgme".split()
OVERLAYS = ("opencore-amr", "vo-amrwbenc", "libgsm", "zimg")


class DependencyPortsTest(unittest.TestCase):
    def test_direct_ports_and_overlay_sources_are_locked(self):
        manifest = json.loads((ROOT / "vcpkg.json").read_text())
        self.assertEqual(PORTS, manifest["dependencies"])
        self.assertEqual(len(PORTS), len(set(PORTS)))
        for name in OVERLAYS:
            with self.subTest(port=name):
                port = ROOT / "ports" / name
                self.assertEqual(name, json.loads((port / "vcpkg.json").read_text())["name"])
                recipe = (port / "portfile.cmake").read_text()
                self.assertRegex(recipe, r"SHA512\s+[a-f0-9]{128}")
                self.assertIn("vcpkg_install_copyright", recipe)
                if name in ("libgsm", "zimg"):
                    self.assertIn("-DBUILD_SHARED_LIBS=ON", recipe)

    def test_amr_nb_and_wb_have_one_port_and_two_checks(self):
        manifest = json.loads((ROOT / "vcpkg.json").read_text())
        self.assertEqual(1, manifest["dependencies"].count("opencore-amr"))
        recipe = (ROOT / "ports/opencore-amr/portfile.cmake").read_text()
        self.assertIn("vcpkg_install_make", recipe)
        build = (ROOT / "scripts/build-macos.sh").read_text()
        self.assertIn("opencore-amrwb/dec_if.h", build)
        self.assertIn("opencore-amrwb", build)


if __name__ == "__main__":
    unittest.main()
