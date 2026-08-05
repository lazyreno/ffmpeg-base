#!/usr/bin/env python3
import argparse
import re
import subprocess
import sys
from pathlib import Path


SUBSYSTEM_VERSION_PATTERN = re.compile(r"\b(\d+(?:\.\d+)*)\s+subsystem version\b", re.IGNORECASE)


class ValidationError(RuntimeError):
    pass


def parse_version(value):
    try:
        return tuple(int(part) for part in value.split("."))
    except ValueError as error:
        raise ValidationError(f"Invalid Windows subsystem version: {value}") from error


def validate_pe_subsystem_versions(sdk_root, maximum_subsystem_version, dumpbin):
    maximum_version = parse_version(maximum_subsystem_version)
    binary_dir = sdk_root / "bin"
    candidates = sorted(
        path
        for path in binary_dir.glob("*")
        if path.is_file() and path.suffix.lower() in {".dll", ".exe"}
    )
    if not candidates:
        raise ValidationError(f"{binary_dir} contains no .exe or .dll files")

    for path in candidates:
        result = subprocess.run(
            [str(dumpbin), "/headers", str(path)],
            text=True,
            capture_output=True,
            check=False,
        )
        if result.returncode != 0:
            raise ValidationError(f"dumpbin failed for {path}: {result.stderr.strip()}")

        match = SUBSYSTEM_VERSION_PATTERN.search(result.stdout)
        if not match:
            raise ValidationError(f"{path.name} does not report a subsystem version")
        actual_version = match.group(1)
        if parse_version(actual_version) > maximum_version:
            raise ValidationError(
                f"{path.name}: subsystem version {actual_version} exceeds {maximum_subsystem_version}"
            )


def main():
    parser = argparse.ArgumentParser(
        description="Validate staged Windows SDK PE subsystem versions."
    )
    parser.add_argument("--sdk-root", required=True, type=Path)
    parser.add_argument("--maximum-subsystem-version", required=True)
    parser.add_argument("--dumpbin", required=True, type=Path)
    arguments = parser.parse_args()

    try:
        validate_pe_subsystem_versions(
            arguments.sdk_root,
            arguments.maximum_subsystem_version,
            arguments.dumpbin,
        )
    except ValidationError as error:
        print(f"error: {error}", file=sys.stderr)
        return 1
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
