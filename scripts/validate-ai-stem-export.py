#!/usr/bin/env python3

import argparse
import json
import math
import struct
import subprocess
import tempfile
from pathlib import Path


SAMPLE_RATE = 48_000
CHANNELS = 2


def build_filter_complex():
    return (
        "[0:a]adelay=delays=0:all=1,volume=0.8,"
        "aformat=channel_layouts=stereo,"
        "pan=stereo|c0=0.923879532511*c0|"
        "c1=0.382683432365*c1[s0];"
        "[1:a]adelay=delays=40:all=1,volume=0.5,"
        "aformat=channel_layouts=stereo,"
        "pan=stereo|c0=0.382683432365*c0|"
        "c1=0.923879532511*c1[s1];"
        "[s0][s1]amix=inputs=2:duration=longest[out]"
    )


def write_pcm(path, frequency, duration_seconds=0.25):
    frame_count = round(SAMPLE_RATE * duration_seconds)
    with path.open("wb") as handle:
        for frame in range(frame_count):
            value = 0.4 * math.sin(
                2.0 * math.pi * frequency * frame / SAMPLE_RATE
            )
            sample = struct.pack("<h", round(value * 32767))
            handle.write(sample * CHANNELS)


def build_ffmpeg_command(ffmpeg, first_input, second_input, output):
    command = [
        str(ffmpeg),
        "-hide_banner",
        "-loglevel",
        "error",
        "-nostdin",
        "-y",
    ]
    for input_path in (first_input, second_input):
        command.extend(
            [
                "-f",
                "s16le",
                "-ar",
                str(SAMPLE_RATE),
                "-ac",
                str(CHANNELS),
                "-channel_layout",
                "stereo",
                "-i",
                str(input_path),
            ]
        )
    command.extend(
        [
            "-filter_complex",
            build_filter_complex(),
            "-map",
            "[out]",
            "-c:a",
            "aac",
            "-b:a",
            "256k",
            "-f",
            "mp4",
            str(output),
        ]
    )
    return command


def build_ffprobe_command(ffprobe, output):
    return [
        str(ffprobe),
        "-v",
        "error",
        "-select_streams",
        "a:0",
        "-print_format",
        "json",
        "-show_entries",
        "stream=codec_name,sample_rate,channels:format=duration",
        str(output),
    ]


def run(command):
    return subprocess.run(
        command,
        text=True,
        capture_output=True,
        check=False,
    )


def format_failure_diagnostics(
    platform,
    stage,
    reason,
    ffmpeg_result=None,
    ffprobe_result=None,
):
    def process_lines(tool_name, result):
        if result is None:
            return [
                f"{tool_name}_exit=not-run",
                f"{tool_name}_stdout=<not run>",
                f"{tool_name}_stderr=<not run>",
            ]
        return [
            f"{tool_name}_exit={result.returncode}",
            f"{tool_name}_stdout={result.stdout}",
            f"{tool_name}_stderr={result.stderr}",
        ]

    lines = [
        f"AI stem export validation failed: {reason}",
        f"platform={platform}",
        f"stage={stage}",
    ]
    lines.extend(process_lines("ffmpeg", ffmpeg_result))
    lines.extend(process_lines("ffprobe", ffprobe_result))
    return "\n".join(lines)


def validate_probe_payload(payload):
    try:
        stream = payload["streams"][0]
        actual = (
            stream["codec_name"],
            int(stream["sample_rate"]),
            int(stream["channels"]),
            float(payload["format"]["duration"]),
        )
    except (KeyError, IndexError, TypeError, ValueError) as error:
        raise RuntimeError(
            f"FFprobe output could not be interpreted: {error}"
        ) from error

    expected = ("aac", SAMPLE_RATE, CHANNELS)
    if actual[:3] != expected or actual[3] <= 0.0:
        raise RuntimeError(
            "Unexpected probe result: "
            f"expected={expected} with positive duration, actual={actual}"
        )


def validate_ai_stem_export(ffmpeg, ffprobe, platform):
    with tempfile.TemporaryDirectory(
        prefix="ffmpeg-ai-stem-export-"
    ) as temporary:
        directory = Path(temporary)
        first_input = directory / "vocals.pcm"
        second_input = directory / "instrumental.pcm"
        output = directory / "mix.m4a"
        write_pcm(first_input, frequency=440.0)
        write_pcm(
            second_input,
            frequency=660.0,
            duration_seconds=0.28,
        )

        ffmpeg_result = run(
            build_ffmpeg_command(
                ffmpeg,
                first_input,
                second_input,
                output,
            )
        )
        if ffmpeg_result.returncode != 0:
            raise RuntimeError(
                format_failure_diagnostics(
                    platform,
                    "ffmpeg",
                    "FFmpeg returned a non-zero exit code",
                    ffmpeg_result,
                )
            )
        if not output.is_file() or output.stat().st_size == 0:
            raise RuntimeError(
                format_failure_diagnostics(
                    platform,
                    "ffmpeg",
                    "FFmpeg produced no output file",
                    ffmpeg_result,
                )
            )

        ffprobe_result = run(
            build_ffprobe_command(ffprobe, output)
        )
        if ffprobe_result.returncode != 0:
            raise RuntimeError(
                format_failure_diagnostics(
                    platform,
                    "ffprobe",
                    "FFprobe returned a non-zero exit code",
                    ffmpeg_result,
                    ffprobe_result,
                )
            )
        try:
            payload = json.loads(ffprobe_result.stdout)
            validate_probe_payload(payload)
        except (json.JSONDecodeError, RuntimeError) as error:
            raise RuntimeError(
                format_failure_diagnostics(
                    platform,
                    "probe",
                    str(error),
                    ffmpeg_result,
                    ffprobe_result,
                )
            ) from error


def main():
    parser = argparse.ArgumentParser()
    parser.add_argument("--ffmpeg", required=True, type=Path)
    parser.add_argument("--ffprobe", required=True, type=Path)
    parser.add_argument("--platform", required=True)
    args = parser.parse_args()

    validate_ai_stem_export(
        args.ffmpeg,
        args.ffprobe,
        args.platform,
    )
    print("Validated AI stem export filter graph.")


if __name__ == "__main__":
    main()
