import importlib.util
import json
from pathlib import Path
import unittest


REPO_ROOT = Path(__file__).resolve().parents[2]
VALIDATOR_PATH = REPO_ROOT / "scripts" / "validate-ffmpeg-runtime-capabilities.py"


def load_validator():
    spec = importlib.util.spec_from_file_location("ffmpeg_runtime_capabilities", VALIDATOR_PATH)
    module = importlib.util.module_from_spec(spec)
    assert spec.loader is not None
    spec.loader.exec_module(module)
    return module


ENCODER_OUTPUT = """\
Encoders:
 V....D libaom-av1            (codec av1)
 V....D libvpx-vp9           (codec vp9)
 V....D libvpx-vp9-alt       (codec vp9)
 A....D libopus               (codec opus)
"""
BSF_OUTPUT = """\
Bitstream filters:
aac_adtstoasc
h264_metadata
hevc_metadata
"""


class RuntimeCapabilityValidatorTest(unittest.TestCase):
    def test_extracts_exact_encoder_names(self):
        validator = load_validator()

        self.assertEqual(
            {"libaom-av1", "libvpx-vp9", "libvpx-vp9-alt", "libopus"},
            validator.parse_encoder_names(ENCODER_OUTPUT),
        )

    def test_reports_missing_required_vp9_encoder(self):
        validator = load_validator()

        diagnostics = validator.validate_encoder_requirements(
            " V....D libaom-av1            (codec av1)\n", ["libvpx-vp9"]
        )

        self.assertEqual(["missing runtime encoder: libvpx-vp9"], diagnostics)

    def test_rejects_manifest_vp9_claim_when_runtime_lacks_encoder(self):
        validator = load_validator()
        manifest = json.loads('{"features": ["encoder-libvpx_vp9"]}')

        diagnostics = validator.validate_manifest_requirements(
            manifest,
            {"libaom-av1"},
            ["libvpx-vp9"],
        )

        self.assertEqual(
            ["manifest claims encoder-libvpx_vp9 but runtime encoder is missing: libvpx-vp9"],
            diagnostics,
        )

    def test_extracts_and_requires_exact_bitstream_filter_names(self):
        validator = load_validator()

        self.assertEqual(
            {"aac_adtstoasc", "h264_metadata", "hevc_metadata"},
            validator.parse_bsf_names(BSF_OUTPUT),
        )
        self.assertEqual(
            ["missing runtime bitstream filter: hevc_metadata"],
            validator.validate_bsf_requirements(
                "Bitstream filters:\nh264_metadata\n", ["h264_metadata", "hevc_metadata"]
            ),
        )

    def test_rejects_manifest_bitstream_filter_claim_when_runtime_lacks_it(self):
        validator = load_validator()
        manifest = {"features": ["bsf-h264_metadata", "bsf-hevc_metadata"]}

        diagnostics = validator.validate_manifest_bsf_requirements(
            manifest, {"h264_metadata"}, ["h264_metadata", "hevc_metadata"]
        )

        self.assertEqual(
            ["manifest claims bsf-hevc_metadata but runtime bitstream filter is missing: hevc_metadata"],
            diagnostics,
        )


if __name__ == "__main__":
    unittest.main()
