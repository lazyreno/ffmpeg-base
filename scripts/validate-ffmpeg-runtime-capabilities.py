#!/usr/bin/env python3
import argparse
import json
import os
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


def parse_bsf_names(output: str) -> set[str]:
    return {
        name
        for line in output.splitlines()
        if (name := line.strip()) and re.fullmatch(r"[a-z][a-z0-9_]*", name)
    }


def validate_bsf_requirements(bsf_output: str, required_bsfs: list[str]) -> list[str]:
    available_bsfs = parse_bsf_names(bsf_output)
    return [f"missing runtime bitstream filter: {bsf}" for bsf in required_bsfs
            if bsf not in available_bsfs]


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


def validate_manifest_bsf_requirements(
    manifest: dict, available_bsfs: set[str], required_bsfs: list[str]
) -> list[str]:
    features = manifest.get("features")
    if not isinstance(features, list) or not all(isinstance(feature, str) for feature in features):
        return ["manifest features must be an array of strings"]

    diagnostics: list[str] = []
    for bsf in required_bsfs:
        feature = f"bsf-{bsf}"
        if feature not in features:
            diagnostics.append(f"manifest is missing required feature: {feature}")
        if feature in features and bsf not in available_bsfs:
            diagnostics.append(
                f"manifest claims {feature} but runtime bitstream filter is missing: {bsf}"
            )
    return diagnostics


def run_ffmpeg_encoder_listing(ffmpeg_path: Path) -> tuple[int, str]:
    environment = dict(os.environ)
    environment["PATH"] = f"{ffmpeg_path.parent}{os.pathsep}{environment.get('PATH', '')}"
    result = subprocess.run(
        [str(ffmpeg_path), "-hide_banner", "-encoders"],
        check=False,
        capture_output=True,
        text=True,
        cwd=ffmpeg_path.parent,
        env=environment,
    )
    return result.returncode, f"{result.stdout}\n{result.stderr}"


def run_ffmpeg_bsf_listing(ffmpeg_path: Path) -> tuple[int, str]:
    environment = dict(os.environ)
    environment["PATH"] = f"{ffmpeg_path.parent}{os.pathsep}{environment.get('PATH', '')}"
    result = subprocess.run(
        [str(ffmpeg_path), "-hide_banner", "-bsfs"],
        check=False,
        capture_output=True,
        text=True,
        cwd=ffmpeg_path.parent,
        env=environment,
    )
    return result.returncode, f"{result.stdout}\n{result.stderr}"


def parse_arguments() -> argparse.Namespace:
    parser = argparse.ArgumentParser(
        description="Validate required encoder capabilities from an FFmpeg runtime binary."
    )
    parser.add_argument("--ffmpeg", required=True, type=Path)
    parser.add_argument("--require-encoder", action="append", default=[], dest="required_encoders")
    parser.add_argument("--require-bsf", action="append", default=[], dest="required_bsfs")
    parser.add_argument("--manifest", type=Path)
    return parser.parse_args()


def main() -> int:
    arguments = parse_arguments()
    if not arguments.required_encoders and not arguments.required_bsfs:
        print("At least one --require-encoder or --require-bsf is required", file=sys.stderr)
        return 1
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
    bsf_return_code, bsf_output = run_ffmpeg_bsf_listing(arguments.ffmpeg)
    if bsf_return_code != 0:
        print(
            f"FFmpeg bitstream filter listing failed with exit code {bsf_return_code}:\n{bsf_output}",
            file=sys.stderr,
        )
        return 1
    diagnostics.extend(validate_bsf_requirements(bsf_output, arguments.required_bsfs))
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
        diagnostics.extend(
            validate_manifest_bsf_requirements(
                manifest,
                parse_bsf_names(bsf_output),
                arguments.required_bsfs,
            )
        )

    if diagnostics:
        print("\n".join(diagnostics), file=sys.stderr)
        return 1
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
