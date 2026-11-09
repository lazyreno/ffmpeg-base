#!/usr/bin/env python3
"""Check the staged SDK's runtime library closure and installed port licenses."""

import argparse
import os
import re
import subprocess
import sys
from pathlib import Path


FFMPEG_LIBRARIES = ("avcodec", "avformat", "avutil", "swscale", "swresample", "avdevice", "avfilter")


def macos_links(binary: Path) -> list[str]:
    result = subprocess.run(["otool", "-L", str(binary)], capture_output=True, text=True, check=True)
    return [line.strip().split(" (", 1)[0] for line in result.stdout.splitlines()[1:] if line.strip()]


def validate_macos_closure(sdk: Path) -> list[str]:
    bin_dir = sdk / "bin"
    binaries = [bin_dir / "ffmpeg", bin_dir / "ffprobe"]
    binaries += list(bin_dir.glob("*.dylib")) + list((sdk / "lib").glob("*.dylib"))
    errors = []
    for binary in binaries:
        if binary.is_symlink() or not binary.is_file():
            continue
        try:
            links = macos_links(binary)
        except (OSError, subprocess.CalledProcessError) as error:
            errors.append(f"otool failed for {binary}: {error}")
            continue
        for link in links:
            if link.startswith(("/usr/lib/", "/System/Library/")):
                continue
            if link.startswith("@loader_path/"):
                name = link.removeprefix("@loader_path/")
                if not (binary.parent / name).exists():
                    errors.append(f"missing macOS dependency {link} for {binary}")
                continue
            errors.append(f"unbundled macOS dependency {link} for {binary}")
    return errors


def windows_links(binary: Path) -> list[str]:
    result = subprocess.run(["dumpbin", "/dependents", str(binary)], capture_output=True, text=True, check=True)
    return re.findall(r"^\s*([A-Za-z0-9_.-]+\.dll)\s*$", result.stdout, re.I | re.M)


def validate_windows_closure(sdk: Path) -> list[str]:
    bin_dir = sdk / "bin"
    system_dir = Path(os.environ.get("SystemRoot", "C:/Windows")) / "System32"
    errors = []
    for binary in (*bin_dir.glob("*.exe"), *bin_dir.glob("*.dll")):
        try:
            links = windows_links(binary)
        except (OSError, subprocess.CalledProcessError) as error:
            errors.append(f"dumpbin failed for {binary}: {error}")
            continue
        for name in links:
            if (bin_dir / name).exists() or (system_dir / name).exists() or name.lower().startswith(("api-ms-win-", "ext-ms-win-")):
                continue
            errors.append(f"missing Windows dependency {name} for {binary}")
    return errors


def validate_licenses(sdk: Path, installed: Path) -> list[str]:
    errors = []
    for package in (installed / "share").iterdir():
        if not package.is_dir():
            continue
        if not (package / "copyright").is_file():
            continue
        if not (sdk / "licenses" / package.name / "LICENSE").is_file():
            errors.append(f"missing vcpkg copyright for {package.name}")
    return errors


def validate_layout(sdk: Path, platform: str) -> list[str]:
    errors = []
    for name in FFMPEG_LIBRARIES:
        header = sdk / "include" / f"lib{name}"
        library = sdk / "lib" / (f"lib{name}.dylib" if platform == "macos" else f"{name}.lib")
        if not header.is_dir() or not library.exists():
            errors.append(f"missing FFmpeg {name} headers or library")
    for name in ("FFmpegConfig.cmake", "FFmpegTargets.cmake", "FFmpegRuntime.cmake"):
        if not (sdk / "cmake" / name).is_file():
            errors.append(f"missing CMake package {name}")
    for name in ("doc", "docs", "examples", "fate", "src", "downloads"):
        if (sdk / name).exists():
            errors.append(f"production SDK contains build-only {name}")
    return errors


def main() -> int:
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--sdk-root", type=Path, required=True)
    parser.add_argument("--platform", choices=("macos", "windows"), required=True)
    parser.add_argument("--vcpkg-root", type=Path, required=True)
    parser.add_argument("--triplet", required=True)
    args = parser.parse_args()
    installed = args.vcpkg_root / args.triplet
    if not (installed / "share").is_dir():
        parser.error(f"missing installed vcpkg triplet: {installed}")
    errors = validate_layout(args.sdk_root, args.platform)
    errors += validate_licenses(args.sdk_root, installed)
    errors += (validate_macos_closure(args.sdk_root) if args.platform == "macos"
               else validate_windows_closure(args.sdk_root))
    if errors:
        print("\n".join(errors), file=sys.stderr)
        return 1
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
