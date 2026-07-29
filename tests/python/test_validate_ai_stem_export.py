import importlib.util
import sys
import tempfile
import unittest
from pathlib import Path
from types import SimpleNamespace


SCRIPT = (
    Path(__file__).resolve().parents[2]
    / "scripts"
    / "validate-ai-stem-export.py"
)
SPEC = importlib.util.spec_from_file_location(
    "ai_stem_export_validator",
    SCRIPT,
)
MODULE = importlib.util.module_from_spec(SPEC)
assert SPEC.loader is not None
sys.modules[SPEC.name] = MODULE
SPEC.loader.exec_module(MODULE)


class AiStemExportValidatorTest(unittest.TestCase):
    def test_filter_graph_matches_desktop_contract(self):
        graph = MODULE.build_filter_complex()

        for name in (
            "adelay=",
            "volume=",
            "aformat=",
            "pan=",
            "amix=",
        ):
            self.assertIn(name, graph)
        self.assertIn("duration=longest", graph)

    def test_pcm_fixture_is_non_empty_stereo_s16le(self):
        with tempfile.TemporaryDirectory() as directory:
            path = Path(directory) / "track.pcm"

            MODULE.write_pcm(
                path,
                frequency=440.0,
                duration_seconds=0.05,
            )

            self.assertEqual(4800 * 2, path.stat().st_size)

    def test_ffmpeg_command_maps_filter_output_to_aac_m4a(self):
        command = MODULE.build_ffmpeg_command(
            Path("ffmpeg"),
            Path("a.pcm"),
            Path("b.pcm"),
            Path("out.m4a"),
        )

        self.assertIn("-filter_complex", command)
        self.assertIn("[out]", command)
        self.assertIn("aac", command)
        self.assertEqual("mp4", command[-2])

    def test_probe_validation_requires_expected_audio_stream(self):
        MODULE.validate_probe_payload(
            {
                "streams": [
                    {
                        "codec_name": "aac",
                        "sample_rate": "48000",
                        "channels": 2,
                    }
                ],
                "format": {"duration": "0.25"},
            }
        )

        invalid_payloads = (
            {
                "streams": [
                    {
                        "codec_name": "mp3",
                        "sample_rate": "48000",
                        "channels": 2,
                    }
                ],
                "format": {"duration": "0.25"},
            },
            {
                "streams": [
                    {
                        "codec_name": "aac",
                        "sample_rate": "44100",
                        "channels": 2,
                    }
                ],
                "format": {"duration": "0.25"},
            },
            {
                "streams": [
                    {
                        "codec_name": "aac",
                        "sample_rate": "48000",
                        "channels": 1,
                    }
                ],
                "format": {"duration": "0.25"},
            },
            {
                "streams": [
                    {
                        "codec_name": "aac",
                        "sample_rate": "48000",
                        "channels": 2,
                    }
                ],
                "format": {"duration": "0"},
            },
        )
        for payload in invalid_payloads:
            with self.subTest(payload=payload):
                with self.assertRaises(RuntimeError):
                    MODULE.validate_probe_payload(payload)

    def test_failure_diagnostics_include_platform_and_process_output(self):
        ffmpeg_result = SimpleNamespace(
            returncode=234,
            stdout="progress",
            stderr="No such filter: adelay",
        )
        ffprobe_result = SimpleNamespace(
            returncode=1,
            stdout="",
            stderr="output is unreadable",
        )

        diagnostics = MODULE.format_failure_diagnostics(
            "windows-x86_64",
            "probe",
            "output validation failed",
            ffmpeg_result,
            ffprobe_result,
        )

        self.assertIn("platform=windows-x86_64", diagnostics)
        self.assertIn("stage=probe", diagnostics)
        self.assertIn("ffmpeg_exit=234", diagnostics)
        self.assertIn("No such filter: adelay", diagnostics)
        self.assertIn("ffprobe_exit=1", diagnostics)
        self.assertIn("output is unreadable", diagnostics)


if __name__ == "__main__":
    unittest.main()
