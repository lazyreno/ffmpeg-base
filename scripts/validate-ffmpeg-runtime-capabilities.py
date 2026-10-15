#!/usr/bin/env python3
import argparse
import json
import re
import subprocess
import sys
from pathlib import Path


ENCODER_LINE = re.compile(r"^\s*[VAS][A-Z.]{5}\s+([^\s]+)")


def parse_encoder_names(output: str) -> set[str]:
    return {
        match.group(1)
        for line in output.splitlines()
        if (match := ENCODER_LINE.match(line)) is not None
    }


def validate_encoder_requirements(
    encoder_output: str, required_encoders: list[str]
) -> list[str]:
    available_encoders = parse_encoder_names(encoder_output)
    return [
        f"missing runtime encoder: {encoder}"
        for encoder in required_encoders
        if encoder not in available_encoders
    ]


def manifest_feature_name(encoder: str) -> str:
    return f"encoder-{encoder.replace('-', '_')}"


def validate_manifest_requirements(
    manifest: dict, available_encoders: set[str], required_encoders: list[str]
) -> list[str]:
    features = manifest.get("features")
    if not isinstance(features, list) or not all(isinstance(feature, str) for feature in features):
        return ["manifest features must be an array of strings"]

    diagnostics: list[str] = []
    for encoder in required_encoders:
        feature = manifest_feature_name(encoder)
        if feature not in features:
            diagnostics.append(f"manifest is missing required feature: {feature}")
        if feature in features and encoder not in available_encoders:
            diagnostics.append(
                f"manifest claims {feature} but runtime encoder is missing: {encoder}"
            )
    return diagnostics


def run_ffmpeg_encoder_listing(ffmpeg_path: Path) -> tuple[int, str]:
    result = subprocess.run(
        [str(ffmpeg_path), "-hide_banner", "-encoders"],
        check=False,
        capture_output=True,
        text=True,
    )
    return result.returncode, f"{result.stdout}\n{result.stderr}"


def parse_arguments() -> argparse.Namespace:
    parser = argparse.ArgumentParser(
        description="Validate required encoder capabilities from an FFmpeg runtime binary."
    )
    parser.add_argument("--ffmpeg", required=True, type=Path)
    parser.add_argument("--require-encoder", action="append", required=True, dest="required_encoders")
    parser.add_argument("--manifest", type=Path)
    return parser.parse_args()


def main() -> int:
    arguments = parse_arguments()
    return_code, encoder_output = run_ffmpeg_encoder_listing(arguments.ffmpeg)
    if return_code != 0:
        print(
            f"FFmpeg encoder listing failed with exit code {return_code}:\n{encoder_output}",
            file=sys.stderr,
        )
        return 1

    diagnostics = validate_encoder_requirements(
        encoder_output, arguments.required_encoders
    )
    if arguments.manifest is not None:
        try:
            manifest = json.loads(arguments.manifest.read_text(encoding="utf-8"))
        except (OSError, json.JSONDecodeError) as error:
            print(f"failed to read manifest {arguments.manifest}: {error}", file=sys.stderr)
            return 1
        diagnostics.extend(
            validate_manifest_requirements(
                manifest,
                parse_encoder_names(encoder_output),
                arguments.required_encoders,
            )
        )

    if diagnostics:
        print("\n".join(diagnostics), file=sys.stderr)
        return 1
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
