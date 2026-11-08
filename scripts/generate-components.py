#!/usr/bin/env python3
"""Record components exposed by a staged FFmpeg binary and its parser registry."""

import argparse
import json
import os
import re
import subprocess
import sys
from pathlib import Path


NAME = re.compile(r"^[a-z0-9][a-z0-9_.-]*$")


def names(values):
    return sorted(set(value for value in values if NAME.fullmatch(value)))


def parse_flag_listing(output: str, kind: str) -> list[str]:
    found = []
    for line in output.splitlines():
        fields = line.split()
        if len(fields) < 2:
            continue
        flags, value = fields[:2]
        if kind == "codec" and not re.fullmatch(r"[VAS][A-Z.]{5}", flags):
            continue
        if kind == "format" and not re.fullmatch(r"[DE.]{1,3}", flags):
            continue
        if kind == "filter" and not re.fullmatch(r"[TSC.]{2,3}", flags):
            continue
        found.extend(value.split(","))
    return names(found)


def parse_plain_listing(output: str) -> list[str]:
    return names(line.strip() for line in output.splitlines())


def parse_parser_registry(content: str) -> list[str]:
    return names(re.findall(r"&ff_([a-z0-9_]+)_parser\s*,", content))


def parse_protocols(output: str) -> dict[str, list[str]]:
    result = {"input": [], "output": []}
    direction = None
    for line in output.splitlines():
        stripped = line.strip()
        if stripped == "Input:":
            direction = "input"
        elif stripped == "Output:":
            direction = "output"
        elif direction and NAME.fullmatch(stripped):
            result[direction].append(stripped)
    return {key: names(value) for key, value in result.items()}


def parse_devices(output: str) -> dict[str, list[str]]:
    result = {"input": [], "output": []}
    for line in output.splitlines():
        if len(line) < 5 or line[1] not in "D " or line[2] not in "E ":
            continue
        fields = line[3:].split()
        if not fields or not all(NAME.fullmatch(name) for name in fields[0].split(",")):
            continue
        value = fields[0]
        for name in value.split(","):
            if line[1] == "D":
                result["input"].append(name)
            if line[2] == "E":
                result["output"].append(name)
    return {key: names(value) for key, value in result.items()}


def run_listing(ffmpeg: Path, option: str) -> str:
    env = dict(os.environ)
    env["PATH"] = f"{ffmpeg.parent}{os.pathsep}{env.get('PATH', '')}"
    result = subprocess.run([str(ffmpeg), "-hide_banner", option], capture_output=True, text=True, env=env)
    if result.returncode:
        raise RuntimeError(f"{option} failed ({result.returncode}): {result.stderr}")
    return result.stdout


def make_components(ffmpeg: Path, parser_registry: Path) -> dict:
    options = {
        "decoders": ("-decoders", "codec"),
        "encoders": ("-encoders", "codec"),
        "demuxers": ("-demuxers", "format"),
        "muxers": ("-muxers", "format"),
        "filters": ("-filters", "filter"),
    }
    components = {key: parse_flag_listing(run_listing(ffmpeg, option), kind)
                  for key, (option, kind) in options.items()}
    components["parsers"] = parse_parser_registry(parser_registry.read_text())
    components["bsfs"] = parse_plain_listing(run_listing(ffmpeg, "-bsfs"))
    components["protocols"] = parse_protocols(run_listing(ffmpeg, "-protocols"))
    components["devices"] = parse_devices(run_listing(ffmpeg, "-devices"))
    components["hwaccels"] = parse_plain_listing(run_listing(ffmpeg, "-hwaccels"))
    return components


def main() -> int:
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--ffmpeg", type=Path, required=True)
    parser.add_argument("--parser-registry", type=Path, required=True)
    parser.add_argument("--output", type=Path, required=True)
    parser.add_argument("--platform-key", required=True)
    parser.add_argument("--feature-profile", required=True)
    parser.add_argument("--ffmpeg-version", required=True)
    args = parser.parse_args()
    try:
        components = make_components(args.ffmpeg, args.parser_registry)
    except (OSError, RuntimeError) as error:
        print(error, file=sys.stderr)
        return 1
    counts = {key: ({direction: len(items) for direction, items in value.items()}
                    if isinstance(value, dict) else len(value))
              for key, value in components.items()}
    document = {"featureProfile": args.feature_profile, "platform": args.platform_key,
                "ffmpegVersion": args.ffmpeg_version, "components": components, "counts": counts}
    args.output.write_text(json.dumps(document, indent=2, ensure_ascii=False) + "\n")
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
