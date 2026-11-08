import importlib.util
import tempfile
import unittest
from pathlib import Path


ROOT = Path(__file__).resolve().parents[2]
SCRIPT = ROOT / "scripts/generate-components.py"


class GenerateComponentsTest(unittest.TestCase):
    @classmethod
    def setUpClass(cls):
        spec = importlib.util.spec_from_file_location("generate_components", SCRIPT)
        cls.module = importlib.util.module_from_spec(spec)
        spec.loader.exec_module(cls.module)

    def test_protocol_and_device_directions_stay_separate(self):
        protocols = self.module.parse_protocols("Supported file protocols:\nInput:\n  file\n  https\nOutput:\n  file\n  rtmp\n")
        self.assertEqual({"input": ["file", "https"], "output": ["file", "rtmp"]}, protocols)
        devices = self.module.parse_devices("Devices:\n D. = Demuxing supported\n .E = Muxing supported\n ---\n D  lavfi   filter\n  E audiotoolbox audio\n")
        self.assertEqual({"input": ["lavfi"], "output": ["audiotoolbox"]}, devices)

    def test_registry_and_listing_strip_headers_and_duplicates(self):
        parser_registry = "static const AVCodecParser * const parser_list[] = {\n    &ff_h264_parser,\n    &ff_aac_parser,\n    &ff_h264_parser,\n};"
        self.assertEqual(["aac", "h264"], self.module.parse_parser_registry(parser_registry))
        listing = "Decoders:\n V..... = Video\n ------\n V..... prores ProRes\n V..... prores ProRes\n"
        self.assertEqual(["prores"], self.module.parse_flag_listing(listing, "codec"))


if __name__ == "__main__":
    unittest.main()
