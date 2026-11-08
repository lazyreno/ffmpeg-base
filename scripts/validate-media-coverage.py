#!/usr/bin/env python3
"""Exercise representative v2 input, processing, and output commands."""

import argparse
import subprocess
import sys
import tempfile
from pathlib import Path


def run_case(name: str, command: list[str], cwd: Path) -> None:
    result = subprocess.run(command, cwd=cwd, capture_output=True, text=True)
    if result.returncode:
        raise RuntimeError(f"{name} exited {result.returncode}: {result.stderr}")
    print(f"{name}: OK")


def main() -> int:
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--ffmpeg", type=Path, required=True)
    parser.add_argument("--ffprobe", type=Path, required=True)
    args = parser.parse_args()
    ffmpeg = str(args.ffmpeg.resolve())
    ffprobe = str(args.ffprobe.resolve())
    with tempfile.TemporaryDirectory(prefix="ffmpeg-sdk-v2-") as temp:
        work = Path(temp)
        video = [ffmpeg, "-hide_banner", "-v", "error", "-y", "-f", "lavfi", "-i", "testsrc2=size=64x64:rate=1", "-frames:v", "1"]
        audio = [ffmpeg, "-hide_banner", "-v", "error", "-y", "-f", "lavfi", "-i", "sine=frequency=440:sample_rate=16000", "-t", "0.2"]
        cases = [
            ("prores encode", video + ["-c:v", "prores_ks", "-pix_fmt", "yuv422p10le", "prores.mov"]),
            ("rawvideo encode", video + ["-c:v", "rawvideo", "-f", "nut", "rawvideo.nut"]),
            ("IMA ADPCM encode", audio + ["-c:a", "adpcm_ima_wav", "adpcm.wav"]),
            ("FFV1 Matroska output", video + ["-c:v", "ffv1", "lossless.mkv"]),
            ("H264 MP4 output", video + ["-c:v", "libx264", "-pix_fmt", "yuv420p", "h264.mp4"]),
            ("WebP output", video + ["-c:v", "libwebp", "frame.webp"]),
            ("JPEG XL output", video + ["-c:v", "libjxl", "frame.jxl"]),
            ("OpenJPEG output", video + ["-c:v", "libopenjpeg", "-f", "image2", "frame.j2k"]),
            ("AV1 output", video + ["-c:v", "libaom-av1", "-cpu-used", "8", "av1.ivf"]),
            ("zscale processing", video + ["-vf", "zscale=w=64:h=64", "-f", "null", "-"]),
            ("drawtext processing", video + ["-vf", "drawtext=text=SDK", "-f", "null", "-"]),
            ("SoXR processing", audio + ["-af", "aresample=resampler=soxr:osr=8000", "-f", "null", "-"]),
            ("Rubber Band processing", audio + ["-af", "rubberband=tempo=1.1", "-f", "null", "-"]),
        ]
        try:
            for name, command in cases:
                run_case(name, command, work)
            (work / "subtitle.srt").write_text("1\n00:00:00,000 --> 00:00:01,000\nSDK\n")
            run_case("subtitles processing", video + ["-vf", "subtitles=subtitle.srt", "-f", "null", "-"], work)
            for name in ("prores.mov", "rawvideo.nut", "adpcm.wav"):
                run_case(f"{name} decode", [ffmpeg, "-hide_banner", "-v", "error", "-i", name, "-f", "null", "-"], work)
                run_case(f"{name} probe", [ffprobe, "-v", "error", "-show_entries", "format=format_name", "-of", "default=noprint_wrappers=1", name], work)
        except RuntimeError as error:
            print(error, file=sys.stderr)
            return 1
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
