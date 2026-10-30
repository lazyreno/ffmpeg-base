#!/usr/bin/env python3

import argparse
import json
import struct
import subprocess
import tempfile
from pathlib import Path


WIDTH = 64
HEIGHT = 48
FRAME_RATE = 20
FRAME_COUNT = 5


def riff_chunk(tag, payload):
    return tag + struct.pack("<I", len(payload)) + payload + b"\0" * (len(payload) % 2)


def write_rawvideo_avi(path):
    row_size = (WIDTH * 3 + 3) & ~3
    frame_size = row_size * HEIGHT
    header = struct.pack(
        "<14I", 1_000_000 // FRAME_RATE, frame_size * FRAME_RATE, 0, 0,
        FRAME_COUNT, 0, 1, frame_size, WIDTH, HEIGHT, 0, 0, 0, 0,
    )
    stream = struct.pack(
        "<4s4sIHH8I4h", b"vids", b"DIB ", 0, 0, 0,
        0, 1, FRAME_RATE, 0, FRAME_COUNT, frame_size, 0xFFFFFFFF, 0,
        0, 0, WIDTH, HEIGHT,
    )
    bitmap = struct.pack("<IiiHHIIiiII", 40, WIDTH, HEIGHT, 1, 24, 0, frame_size, 0, 0, 0, 0)
    stream_list = riff_chunk(b"LIST", b"strl" + riff_chunk(b"strh", stream) + riff_chunk(b"strf", bitmap))
    header_list = riff_chunk(b"LIST", b"hdrl" + riff_chunk(b"avih", header) + stream_list)
    frames = bytearray()
    for index in range(FRAME_COUNT):
        row = bytes((index * 40, 80, 160)) * WIDTH + b"\0" * (row_size - WIDTH * 3)
        frames.extend(riff_chunk(b"00db", row * HEIGHT))
    movie = riff_chunk(b"LIST", b"movi" + frames)
    path.write_bytes(riff_chunk(b"RIFF", b"AVI " + header_list + movie))


def failure_diagnostics(platform, reason, ffmpeg_result=None, ffprobe_result=None):
    lines = ["RawVideo transcode validation failed: " + reason, "platform=" + platform]
    for name, result in (("ffmpeg", ffmpeg_result), ("ffprobe", ffprobe_result)):
        lines.append(f"{name}_exit={result.returncode if result is not None else 'not-run'}")
        if result is not None:
            lines.extend((f"{name}_stdout={result.stdout}", f"{name}_stderr={result.stderr}"))
    return "\n".join(lines)


def run(command):
    return subprocess.run(command, text=True, capture_output=True, check=False, timeout=30)


def validate_transcode(ffmpeg, ffprobe, platform, directory):
    input_path = directory / "input-rawvideo.avi"
    output_path = directory / "output-h264.mp4"
    write_rawvideo_avi(input_path)
    encoded = run([
        str(ffmpeg), "-hide_banner", "-loglevel", "error", "-nostdin", "-y",
        "-i", str(input_path), "-map", "0:v:0", "-an",
        "-c:v", "libx264", "-pix_fmt", "yuv420p", str(output_path),
    ])
    if encoded.returncode != 0:
        raise RuntimeError(failure_diagnostics(platform, "FFmpeg returned a non-zero exit code", encoded))
    if not output_path.is_file() or output_path.stat().st_size == 0:
        raise RuntimeError(failure_diagnostics(platform, "FFmpeg produced no output file", encoded))

    probed = run([
        str(ffprobe), "-v", "error", "-print_format", "json", "-count_frames",
        "-show_entries", "stream=codec_name,pix_fmt,width,height,nb_read_frames:format=duration",
        str(output_path),
    ])
    if probed.returncode != 0:
        raise RuntimeError(failure_diagnostics(platform, "FFprobe returned a non-zero exit code", encoded, probed))
    try:
        payload = json.loads(probed.stdout)
        stream = payload["streams"][0]
        actual = (stream["codec_name"], stream["pix_fmt"], int(stream["width"]),
                  int(stream["height"]), int(stream["nb_read_frames"]))
        duration = float(payload["format"]["duration"])
    except (json.JSONDecodeError, KeyError, IndexError, TypeError, ValueError) as error:
        raise RuntimeError(failure_diagnostics(platform, f"Invalid FFprobe output: {error}", encoded, probed)) from error
    expected = ("h264", "yuv420p", WIDTH, HEIGHT, FRAME_COUNT)
    if actual != expected or abs(duration - FRAME_COUNT / FRAME_RATE) > 0.05:
        raise RuntimeError(failure_diagnostics(
            platform, f"Unexpected output: expected={expected}, actual={actual}, duration={duration}", encoded, probed,
        ))


def main():
    parser = argparse.ArgumentParser()
    parser.add_argument("--ffmpeg", required=True, type=Path)
    parser.add_argument("--ffprobe", required=True, type=Path)
    parser.add_argument("--platform", required=True)
    args = parser.parse_args()
    with tempfile.TemporaryDirectory(prefix="ffmpeg-rawvideo-") as temporary:
        validate_transcode(args.ffmpeg, args.ffprobe, args.platform, Path(temporary))
    print("Validated AVI RawVideo (bgr24) decoding and H.264 output.")


if __name__ == "__main__":
    main()
