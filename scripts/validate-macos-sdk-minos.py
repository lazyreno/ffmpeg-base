#!/usr/bin/env python3
import argparse
import re
import subprocess
import sys
from pathlib import Path


MINOS_PATTERN = re.compile(r"\bminos\s+(\d+(?:\.\d+)*)\b")


class ValidationError(RuntimeError):
    pass


def parse_version(value):
    try:
        return tuple(int(part) for part in value.split("."))
    except ValueError as error:
        raise ValidationError(f"Invalid macOS version: {value}") from error


def is_macho(path, file_tool):
    result = subprocess.run(
        [str(file_tool), "-b", str(path)], text=True, capture_output=True, check=False
    )
    if result.returncode != 0:
        raise ValidationError(f"file failed for {path}: {result.stderr.strip()}")
    return "Mach-O" in result.stdout


def validate_machos(sdk_root, minimum_system_version, file_tool, vtool):
    expected_version = parse_version(minimum_system_version)
    candidates = []
    for directory_name in ("bin", "lib"):
        directory = sdk_root / directory_name
        if not directory.exists():
            continue
        candidates.extend(path for path in directory.rglob("*") if path.is_file() and not path.is_symlink())

    for path in candidates:
        if not is_macho(path, file_tool):
            continue

        result = subprocess.run(
            [str(vtool), "-show-build", str(path)], text=True, capture_output=True, check=False
        )
        if result.returncode != 0:
            raise ValidationError(f"vtool failed for {path}: {result.stderr.strip()}")

        versions = MINOS_PATTERN.findall(result.stdout)
        if not versions:
            raise ValidationError(f"{path} does not report minos")
        for actual_version in versions:
            if parse_version(actual_version) > expected_version:
                raise ValidationError(
                    f"{path}: minos {actual_version} exceeds {minimum_system_version}"
                )


def main():
    parser = argparse.ArgumentParser(description="Validate staged macOS SDK Mach-O minimum versions.")
    parser.add_argument("--sdk-root", required=True, type=Path)
    parser.add_argument("--minimum-system-version", required=True)
    parser.add_argument("--file-tool", required=True, type=Path)
    parser.add_argument("--vtool", required=True, type=Path)
    arguments = parser.parse_args()

    try:
        validate_machos(
            arguments.sdk_root,
            arguments.minimum_system_version,
            arguments.file_tool,
            arguments.vtool,
        )
    except ValidationError as error:
        print(f"error: {error}", file=sys.stderr)
        return 1
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
