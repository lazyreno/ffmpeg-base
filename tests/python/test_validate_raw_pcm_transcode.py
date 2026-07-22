import importlib.util
import sys
import tempfile
import unittest
from pathlib import Path
from types import SimpleNamespace


SCRIPT = Path(__file__).resolve().parents[2] / "scripts" / "validate-raw-pcm-transcode.py"
SPEC = importlib.util.spec_from_file_location("raw_pcm_validator", SCRIPT)
MODULE = importlib.util.module_from_spec(SPEC)
assert SPEC.loader is not None
sys.modules[SPEC.name] = MODULE
SPEC.loader.exec_module(MODULE)


class RawPcmValidatorTest(unittest.TestCase):
    def test_matrix_contains_four_inputs_and_three_outputs(self):
        cases = MODULE.build_cases()

        self.assertEqual(12, len(cases))
        self.assertEqual(
            {"s16le", "s24le", "s32le", "f32le"},
            {case.input_format for case in cases},
        )
        self.assertEqual(
            {"wav", "mp3", "m4a"},
            {case.output_format for case in cases},
        )

    def test_pcm_generation_matches_frame_width(self):
        bytes_per_sample = {
            "s16le": 2,
            "s24le": 3,
            "s32le": 4,
            "f32le": 4,
        }

        with tempfile.TemporaryDirectory() as directory:
            for format_name, width in bytes_per_sample.items():
                path = Path(directory) / f"input.{format_name}"
                MODULE.write_pcm(path, format_name, duration_seconds=0.01)
                self.assertEqual(480 * 2 * width, path.stat().st_size)

    def test_failure_diagnostics_include_platform_and_both_processes(self):
        case = MODULE.TranscodeCase("s16le", "wav", "pcm_s16le")
        ffmpeg_result = SimpleNamespace(
            returncode=234,
            stdout="",
            stderr="Unknown input format: s16le",
        )
        ffprobe_result = SimpleNamespace(
            returncode=1,
            stdout="",
            stderr="output is unreadable",
        )

        diagnostics = MODULE.format_failure_diagnostics(
            "macos-arm64",
            case,
            "probe validation failed",
            ffmpeg_result,
            ffprobe_result,
        )

        self.assertIn("platform=macos-arm64", diagnostics)
        self.assertIn("input=s16le", diagnostics)
        self.assertIn("output=wav", diagnostics)
        self.assertIn("ffmpeg_exit=234", diagnostics)
        self.assertIn("Unknown input format: s16le", diagnostics)
        self.assertIn("ffprobe_exit=1", diagnostics)
        self.assertIn("output is unreadable", diagnostics)


if __name__ == "__main__":
    unittest.main()
