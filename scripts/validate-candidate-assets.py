#!/usr/bin/env python3
"""Check candidate ZIP contents against the v2 platform declarations."""

import argparse
import json
import sys
import zipfile
from pathlib import Path


ROOT = Path(__file__).resolve().parents[1]
FFMPEG_LIBRARIES = ("avcodec", "avformat", "avutil", "swscale", "swresample", "avdevice", "avfilter")


def validate_archive(archive: Path, platform: dict, sdk: dict) -> list[str]:
    errors = []
    try:
        with zipfile.ZipFile(archive) as package:
            members = set(package.namelist())
            roots = {name.split("/", 1)[0] for name in members if "/" in name}
            if len(roots) != 1:
                return [f"{archive.name}: expected one SDK root directory"]
            root = roots.pop()
            def read_json(name):
                return json.loads(package.read(f"{root}/{name}"))
            manifest = read_json("manifest.json")
            components = read_json("components.json")
            expected = {
                "sdkVersion": sdk["sdkVersion"],
                "ffmpegVersion": sdk["ffmpegVersion"],
                "featureProfile": sdk["featureProfile"],
                "platform": platform["os"],
                "arch": platform["arch"],
                "minimumSystemVersion": platform["minimumSystemVersion"],
                "componentsFile": "components.json",
            }
            for key, value in expected.items():
                if manifest.get(key) != value:
                    errors.append(f"{archive.name}: manifest {key} mismatch")
            if components.get("featureProfile") != sdk["featureProfile"] or components.get("platform") != platform["key"]:
                errors.append(f"{archive.name}: component profile or platform mismatch")
            for name in FFMPEG_LIBRARIES:
                lib_name = f"lib{name}.dylib" if platform["os"] == "macos" else f"{name}.lib"
                if f"{root}/lib/{lib_name}" not in members:
                    errors.append(f"{archive.name}: missing {lib_name}")
                if not any(member.startswith(f"{root}/include/lib{name}/") for member in members):
                    errors.append(f"{archive.name}: missing lib{name} headers")
            if not any(member.startswith(f"{root}/licenses/") for member in members):
                errors.append(f"{archive.name}: missing licenses")
    except (OSError, zipfile.BadZipFile, KeyError, json.JSONDecodeError) as error:
        errors.append(f"{archive.name}: unreadable candidate archive: {error}")
    return errors


def main() -> int:
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--assets", type=Path, required=True)
    args = parser.parse_args()
    sdk = json.loads((ROOT / "config/sdk-version.json").read_text())
    platforms = json.loads((ROOT / "config/platform-matrix.json").read_text())["platforms"]
    errors = []
    for platform in platforms:
        if not platform["enabled"]:
            continue
        name = f"ffmpeg-sdk-{sdk['ffmpegVersion']}-v{sdk['sdkVersion']}-{platform['key']}.{platform['archiveExt']}"
        errors += validate_archive(args.assets / name, platform, sdk)
    if errors:
        print("\n".join(errors), file=sys.stderr)
        return 1
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
