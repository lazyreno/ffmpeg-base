import importlib.util
import json
import struct
import tempfile
import unittest
from pathlib import Path
from types import SimpleNamespace
from unittest.mock import patch


SCRIPT = Path(__file__).resolve().parents[2] / "scripts" / "validate-rawvideo-transcode.py"
SPEC = importlib.util.spec_from_file_location("rawvideo_validator", SCRIPT)
MODULE = importlib.util.module_from_spec(SPEC)
assert SPEC.loader is not None
SPEC.loader.exec_module(MODULE)


def process_result(returncode=0, stdout="", stderr=""):
    return SimpleNamespace(returncode=returncode, stdout=stdout, stderr=stderr)


class RawVideoValidatorTest(unittest.TestCase):
    def test_fixture_is_uncompressed_24bit_avi_with_complete_frames(self):
        with tempfile.TemporaryDirectory() as directory:
            path = Path(directory) / "input.avi"
            MODULE.write_rawvideo_avi(path)
            data = path.read_bytes()
        self.assertEqual(b"RIFF", data[:4])
        self.assertEqual(len(data) - 8, struct.unpack_from("<I", data, 4)[0])
        self.assertEqual(b"AVI ", data[8:12])
        bitmap = data.index(b"strf") + 8
        self.assertEqual((40, MODULE.WIDTH, MODULE.HEIGHT, 1, 24, 0),
                         struct.unpack_from("<IiiHHI", data, bitmap))
        offset = data.index(b"movi") + 4
        frames = 0
        while offset < len(data):
            self.assertEqual(b"00db", data[offset:offset + 4])
            size = struct.unpack_from("<I", data, offset + 4)[0]
            self.assertEqual(MODULE.WIDTH * MODULE.HEIGHT * 3, size)
            offset += 8 + size + size % 2
            frames += 1
        self.assertEqual(MODULE.FRAME_COUNT, frames)

    def test_missing_decoder_reports_actual_process_evidence(self):
        missing = process_result(234, stderr="Decoding requested, but no decoder found for: rawvideo")
        with tempfile.TemporaryDirectory() as directory, patch.object(MODULE, "run", return_value=missing):
            with self.assertRaisesRegex(RuntimeError, "no decoder found for: rawvideo") as failure:
                MODULE.validate_transcode(Path("ffmpeg"), Path("ffprobe"), "windows-x86_64", Path(directory))
        self.assertIn("platform=windows-x86_64", str(failure.exception))
        self.assertIn("ffmpeg_exit=234", str(failure.exception))
        self.assertIn("ffprobe_exit=not-run", str(failure.exception))

    def test_success_exit_without_output_is_rejected(self):
        with tempfile.TemporaryDirectory() as directory, patch.object(MODULE, "run", return_value=process_result()):
            with self.assertRaisesRegex(RuntimeError, "produced no output"):
                MODULE.validate_transcode(Path("ffmpeg"), Path("ffprobe"), "macos-arm64", Path(directory))

    def validate_mock_output(self, payload):
        def run(command):
            if command[0] == "ffmpeg":
                Path(command[-1]).write_bytes(b"encoded")
                return process_result()
            return process_result(stdout=json.dumps(payload))
        with tempfile.TemporaryDirectory() as directory, patch.object(MODULE, "run", side_effect=run):
            MODULE.validate_transcode(Path("ffmpeg"), Path("ffprobe"), "macos-arm64", Path(directory))

    def test_output_must_decode_all_expected_frames(self):
        stream = {"codec_name": "h264", "pix_fmt": "yuv420p", "width": MODULE.WIDTH,
                  "height": MODULE.HEIGHT, "nb_read_frames": str(MODULE.FRAME_COUNT)}
        payload = {"streams": [stream], "format": {"duration": str(MODULE.FRAME_COUNT / MODULE.FRAME_RATE)}}
        self.validate_mock_output(payload)
        stream["nb_read_frames"] = "1"
        with self.assertRaisesRegex(RuntimeError, "Unexpected output"):
            self.validate_mock_output(payload)

    def test_unreadable_probe_metadata_is_rejected(self):
        with self.assertRaisesRegex(RuntimeError, "Invalid FFprobe output"):
            self.validate_mock_output({"streams": [], "format": {}})


if __name__ == "__main__":
    unittest.main()
