import json
import unittest
from pathlib import Path


ROOT = Path(__file__).resolve().parents[2]
EXTERNAL = (
    "zlib libmp3lame libvpx libaom libopus libvorbis libopencore-amrnb "
    "libx264 libx265 bzlib lzma iconv libxml2 libdav1d libwebp libjxl "
    "libopenjpeg libopencore-amrwb libvo-amrwbenc libspeex libgsm libass "
    "libfreetype libharfbuzz libfontconfig libfribidi libsoxr librubberband "
    "libzimg libsvtav1 libopenmpt libgme"
).split()
COMMON = [
    "--disable-autodetect", "--enable-gpl", "--enable-version3",
    "--enable-shared", "--disable-static", "--disable-doc",
    "--disable-debug", "--disable-ffplay",
]
MACOS = [
    "--enable-securetransport", "--enable-avfoundation",
    "--enable-indev=avfoundation", "--enable-audiotoolbox",
    "--enable-outdev=audiotoolbox", "--enable-videotoolbox",
    "--disable-xlib", "--disable-libxcb",
]
WINDOWS = [
    "--enable-schannel", "--enable-indev=gdigrab", "--enable-indev=dshow",
    "--enable-mediafoundation", "--enable-d3d11va",
]


def assert_no_native_component_whitelist(flags):
    forbidden = (
        "--disable-everything", "--disable-network", "--enable-small",
        "--disable-decoders", "--disable-encoders", "--disable-demuxers",
        "--disable-muxers", "--disable-parsers", "--disable-bsfs",
        "--disable-filters", "--disable-protocols", "--disable-indevs",
        "--disable-outdevs",
    )
    for flag in flags:
        if flag in forbidden or flag.startswith((
            "--enable-decoder=", "--enable-encoder=", "--enable-demuxer=",
            "--enable-muxer=", "--enable-parser=", "--enable-bsf=",
            "--enable-filter=", "--enable-protocol=",
        )):
            raise AssertionError(f"Native component whitelist remains: {flag}")


class FFmpegProfileTest(unittest.TestCase):
    def test_v2_profile_enables_exact_external_set_and_platform_interfaces(self):
        profile = json.loads((ROOT / "config/ffmpeg-profile.json").read_text())
        version = json.loads((ROOT / "config/sdk-version.json").read_text())
        self.assertEqual("gpl-desktop-media-v2", profile["profile"])
        self.assertEqual(profile["profile"], version["featureProfile"])
        self.assertEqual("gpl", profile["licenseMode"])
        self.assertEqual("gpl", version["licenseMode"])
        self.assertEqual("20261108.1", version["sdkVersion"])
        self.assertEqual(EXTERNAL, profile["externalDependencies"])
        self.assertEqual(32, len(set(profile["externalDependencies"])))
        self.assertEqual(COMMON + [f"--enable-{name}" for name in EXTERNAL],
                         profile["configure"]["common"])
        self.assertEqual(MACOS, profile["configure"]["macos"])
        self.assertEqual(WINDOWS, profile["configure"]["windows"])
        self.assertEqual(["--enable-dxva2"], profile["configure"]["windows_x86_64"])
        self.assertNotIn("features", profile)
        for flags in profile["configure"].values():
            assert_no_native_component_whitelist(flags)

    def test_native_component_blacklist_is_rejected(self):
        with self.assertRaisesRegex(AssertionError, "disable-network"):
            assert_no_native_component_whitelist(COMMON + ["--disable-network"])


if __name__ == "__main__":
    unittest.main()
