import importlib.util
import sys
import tempfile
import unittest
from pathlib import Path


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


if __name__ == "__main__":
    unittest.main()
