#!/usr/bin/env python3
import argparse
import json
from pathlib import Path


REPO_ROOT = Path(__file__).resolve().parents[1]
REQUIRED_PLATFORM_KEYS = {
    "key",
    "os",
    "arch",
    "buildFamily",
    "runner",
    "triplet",
    "archiveExt",
    "enabled",
}


def load_json(path):
    with path.open("r", encoding="utf-8") as handle:
        return json.load(handle)


def validate_platform(platform):
    missing = sorted(REQUIRED_PLATFORM_KEYS - set(platform))
    if missing:
        raise SystemExit(f"{platform.get('key', '<unknown>')} is missing keys: {', '.join(missing)}")
    if platform["buildFamily"] not in {"macos", "windows-msvc"}:
        raise SystemExit(f"{platform['key']} has unsupported buildFamily: {platform['buildFamily']}")
    if platform["buildFamily"] == "windows-msvc" and not platform.get("msvcArch"):
        raise SystemExit(f"{platform['key']} must declare msvcArch")


def main():
    parser = argparse.ArgumentParser(description="Generate the GitHub Actions SDK build matrix.")
    parser.add_argument("--github-output", type=Path, help="Optional $GITHUB_OUTPUT file to append outputs to.")
    args = parser.parse_args()

    sdk = load_json(REPO_ROOT / "config" / "sdk-version.json")
    matrix_config = load_json(REPO_ROOT / "config" / "platform-matrix.json")
    enabled_platforms = []

    for platform in matrix_config["platforms"]:
        validate_platform(platform)
        if platform["enabled"]:
            enabled_platforms.append(platform)

    if not enabled_platforms:
        raise SystemExit("platform-matrix.json must enable at least one platform")

    matrix = {"include": enabled_platforms}
    matrix_json = json.dumps(matrix, separators=(",", ":"), sort_keys=True)
    sdk_version = sdk["sdkVersion"]

    if args.github_output:
        with args.github_output.open("a", encoding="utf-8") as handle:
            handle.write(f"matrix={matrix_json}\n")
            handle.write(f"sdk_version={sdk_version}\n")
    else:
        print(matrix_json)


if __name__ == "__main__":
    main()
