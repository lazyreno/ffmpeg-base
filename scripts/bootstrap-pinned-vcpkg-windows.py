#!/usr/bin/env python3
"""Install the pinned Windows vcpkg tool through GitHub's API."""

import argparse
import hashlib
import json
import shutil
import subprocess
import tempfile
from pathlib import Path


def main():
    parser = argparse.ArgumentParser()
    parser.add_argument("--vcpkg-root", type=Path, required=True)
    parser.add_argument("--lock-file", type=Path, required=True)
    parser.add_argument("--arch", choices=("arm64", "x86_64"), required=True)
    args = parser.parse_args()

    metadata = dict(line.split("=", 1) for line in
                    (args.vcpkg_root / "scripts/vcpkg-tool-metadata.txt").read_text().splitlines()
                    if "=" in line)
    lock = json.loads(args.lock_file.read_text())
    tag = metadata["VCPKG_TOOL_RELEASE_TAG"]
    if tag != lock["toolRelease"]:
        raise SystemExit(f"vcpkg tool release mismatch: {tag}")
    asset = "vcpkg-arm64.exe" if args.arch == "arm64" else "vcpkg.exe"
    with tempfile.TemporaryDirectory() as temporary:
        subprocess.run(["gh", "release", "download", tag, "--repo", "microsoft/vcpkg-tool",
                        "--pattern", asset, "-D", temporary], check=True)
        source = Path(temporary) / asset
        digest = hashlib.sha512(source.read_bytes()).hexdigest()
        if digest != lock["windowsToolSha512"][args.arch]:
            raise SystemExit(f"Pinned vcpkg.exe SHA512 mismatch: {digest}")
        shutil.copy2(source, args.vcpkg_root / "vcpkg.exe")
    subprocess.run([str(args.vcpkg_root / "vcpkg.exe"), "version", "--disable-metrics"], check=True)


if __name__ == "__main__":
    main()
