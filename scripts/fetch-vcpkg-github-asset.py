#!/usr/bin/env python3
"""Fetch vcpkg's pinned GitHub archives through a direct asset endpoint."""

import hashlib
import os
import subprocess
import sys
import tempfile
from pathlib import Path
from time import sleep
from urllib.parse import urlparse
from urllib.request import urlopen


def fetch(url, expected_sha512, destination):
    parsed = urlparse(url)
    parts = parsed.path.strip("/").split("/")
    if parsed.hostname != "github.com" or len(parts) < 4 or not expected_sha512:
        raise ValueError("Not a pinned GitHub asset")

    owner, repo = parts[:2]
    if parts[2] == "archive" and parts[-1].endswith(".tar.gz"):
        ref = "/".join(parts[3:])[:-7]
        source_url = f"https://codeload.github.com/{owner}/{repo}/tar.gz/{ref}"
        for attempt in range(3):
            try:
                with urlopen(source_url, timeout=90) as response:
                    payload = response.read()
                break
            except OSError:
                if attempt == 2:
                    raise
                sleep(attempt + 1)
    elif len(parts) == 6 and parts[2:4] == ["releases", "download"]:
        with tempfile.TemporaryDirectory() as directory:
            subprocess.run(["gh", "release", "download", parts[4], "--repo", f"{owner}/{repo}",
                            "--pattern", parts[5], "-D", directory], check=True)
            payload = (Path(directory) / parts[5]).read_bytes()
    else:
        raise ValueError("Not a supported GitHub asset")

    digest = hashlib.sha512(payload).hexdigest()
    if digest != expected_sha512:
        raise ValueError(f"SHA512 mismatch for {url}: {digest}")
    destination = Path(destination)
    destination.parent.mkdir(parents=True, exist_ok=True)
    with tempfile.NamedTemporaryFile(dir=destination.parent, delete=False) as temporary:
        temporary.write(payload)
        temporary_path = temporary.name
    os.replace(temporary_path, destination)


if __name__ == "__main__":
    try:
        fetch(sys.argv[1], sys.argv[2], sys.argv[3])
    except (IndexError, OSError, ValueError, subprocess.CalledProcessError) as error:
        print(error, file=sys.stderr)
        sys.exit(1)
