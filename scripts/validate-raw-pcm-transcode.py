#!/usr/bin/env python3

import argparse
import json
import math
import struct
import subprocess
import tempfile
from dataclasses import dataclass
from pathlib import Path


SAMPLE_RATE = 48_000
CHANNELS = 2


@dataclass(frozen=True)
class TranscodeCase:
    input_format: str
    output_format: str
    output_codec: str


def build_cases():
    outputs = {
        "wav": None,
        "mp3": "mp3",
        "m4a": "aac",
    }
    wav_codecs = {
        "s16le": "pcm_s16le",
        "s24le": "pcm_s24le",
        "s32le": "pcm_s32le",
        "f32le": "pcm_f32le",
    }
    return [
        TranscodeCase(
            input_format,
            output_format,
            wav_codecs[input_format] if output_format == "wav" else output_codec,
        )
        for input_format in wav_codecs
        for output_format, output_codec in outputs.items()
    ]


def encode_sample(format_name, value):
    value = max(-1.0, min(1.0, value))
    if format_name == "s16le":
        return struct.pack("<h", round(value * 32767))
    if format_name == "s24le":
        return round(value * 8388607).to_bytes(3, "little", signed=True)
    if format_name == "s32le":
        return struct.pack("<i", round(value * 2147483647))
    if format_name == "f32le":
        return struct.pack("<f", value)
    raise ValueError(f"Unsupported PCM format: {format_name}")


def write_pcm(path, format_name, duration_seconds=0.25):
    frame_count = round(SAMPLE_RATE * duration_seconds)
    with path.open("wb") as handle:
        for frame in range(frame_count):
            sample = 0.5 * math.sin(2.0 * math.pi * 440.0 * frame / SAMPLE_RATE)
            encoded = encode_sample(format_name, sample)
            handle.write(encoded * CHANNELS)


def run(command, case):
    result = subprocess.run(command, text=True, capture_output=True, check=False)
    if result.returncode != 0:
        raise RuntimeError(
            f"Raw PCM validation failed: input={case.input_format}, "
            f"output={case.output_format}, exit={result.returncode}\n"
            f"stdout:\n{result.stdout}\nstderr:\n{result.stderr}"
        )
    return result.stdout


def validate_case(ffmpeg, ffprobe, directory, case):
    input_path = directory / f"input-{case.input_format}.pcm"
    output_path = directory / f"output-{case.input_format}.{case.output_format}"
    if not input_path.exists():
        write_pcm(input_path, case.input_format)

    codec_args = {
        "wav": ["-c:a", case.output_codec],
        "mp3": ["-c:a", "libmp3lame"],
        "m4a": ["-c:a", "aac"],
    }[case.output_format]
    run(
        [
            str(ffmpeg),
            "-hide_banner",
            "-loglevel",
            "error",
            "-nostdin",
            "-y",
            "-f",
            case.input_format,
            "-ar",
            str(SAMPLE_RATE),
            "-ac",
            str(CHANNELS),
            "-channel_layout",
            "stereo",
            "-i",
            str(input_path),
            "-map",
            "0:a:0",
            "-vn",
            *codec_args,
            str(output_path),
        ],
        case,
    )

    if not output_path.is_file() or output_path.stat().st_size == 0:
        raise RuntimeError(
            f"Raw PCM validation produced no output: input={case.input_format}, "
            f"output={case.output_format}"
        )

    probe_stdout = run(
        [
            str(ffprobe),
            "-v",
            "error",
            "-print_format",
            "json",
            "-show_entries",
            "stream=codec_name,sample_rate,channels:format=duration",
            str(output_path),
        ],
        case,
    )
    payload = json.loads(probe_stdout)
    stream = payload["streams"][0]
    duration = float(payload["format"]["duration"])
    actual = (
        stream["codec_name"],
        int(stream["sample_rate"]),
        int(stream["channels"]),
        duration,
    )
    expected = (case.output_codec, SAMPLE_RATE, CHANNELS)
    if actual[:3] != expected or actual[3] <= 0.0:
        raise RuntimeError(
            f"Unexpected probe result for input={case.input_format}, "
            f"output={case.output_format}: expected={expected} with positive duration, "
            f"actual={actual}"
        )


def main():
    parser = argparse.ArgumentParser()
    parser.add_argument("--ffmpeg", required=True, type=Path)
    parser.add_argument("--ffprobe", required=True, type=Path)
    args = parser.parse_args()

    with tempfile.TemporaryDirectory(prefix="ffmpeg-raw-pcm-") as temporary:
        directory = Path(temporary)
        for case in build_cases():
            validate_case(args.ffmpeg, args.ffprobe, directory, case)

    print("Validated 12 raw PCM transcode combinations.")


if __name__ == "__main__":
    main()
