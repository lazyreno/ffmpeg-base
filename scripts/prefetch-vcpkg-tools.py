#!/usr/bin/env python3
"""Cache the pinned vcpkg CMake and Ninja archives through GitHub's API."""

import argparse
import hashlib
import json
import subprocess
import tempfile
from pathlib import Path
from urllib.parse import urlparse


def main():
    parser = argparse.ArgumentParser()
    parser.add_argument("--vcpkg-root", type=Path, required=True)
    parser.add_argument("--os", choices=("macos", "windows"), required=True)
    parser.add_argument("--arch", choices=("arm64", "x86_64"), required=True)
    args = parser.parse_args()

    metadata = json.loads((args.vcpkg_root / "scripts/vcpkg-tools.json").read_text())
    target_os = "osx" if args.os == "macos" else "windows"
    arch_names = {"arm64": ("arm64",), "x86_64": ("amd64", "x64")}[args.arch]
    downloads = args.vcpkg_root / "downloads"
    downloads.mkdir(exist_ok=True)

    for name in ("cmake", "ninja"):
        matches = [entry for entry in metadata["tools"]
                   if entry["name"] == name and entry["os"] == target_os
                   and ("arch" not in entry or entry["arch"] in arch_names)]
        if len(matches) != 1:
            raise SystemExit(f"Expected one pinned {name} archive for {target_os}/{args.arch}, found {len(matches)}")
        entry = matches[0]
        url = urlparse(entry["url"])
        parts = url.path.strip("/").split("/")
        if url.hostname != "github.com" or len(parts) != 6 or parts[2:4] != ["releases", "download"]:
            raise SystemExit(f"Unsupported pinned {name} release URL: {entry['url']}")
        owner, repo, _, _, tag, asset = parts
        with tempfile.TemporaryDirectory() as temporary:
            subprocess.run(["gh", "release", "download", tag, "--repo", f"{owner}/{repo}",
                            "--pattern", asset, "-D", temporary], check=True)
            source = Path(temporary) / asset
            digest = hashlib.sha512(source.read_bytes()).hexdigest()
            if digest != entry["sha512"]:
                raise SystemExit(f"Pinned {name} SHA512 mismatch: {digest}")
            (downloads / entry["archive"]).write_bytes(source.read_bytes())
        print(f"Cached pinned {name}: {entry['archive']}")


if __name__ == "__main__":
    main()
