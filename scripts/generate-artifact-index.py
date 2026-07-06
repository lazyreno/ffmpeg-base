#!/usr/bin/env python3
import argparse
import hashlib
import json
from pathlib import Path


REPO_ROOT = Path(__file__).resolve().parents[1]


def load_json(path):
    with path.open("r", encoding="utf-8") as handle:
        return json.load(handle)


def archive_sha256(path):
    digest = hashlib.sha256()
    with path.open("rb") as handle:
        for chunk in iter(lambda: handle.read(1024 * 1024), b""):
            digest.update(chunk)
    return digest.hexdigest()


def main():
    parser = argparse.ArgumentParser(description="Generate artifact-index.json for an SDK release.")
    parser.add_argument("--release-assets", required=True, type=Path)
    parser.add_argument("--output", required=True, type=Path)
    parser.add_argument("--base-url", required=True)
    parser.add_argument("--release-tag", required=True)
    args = parser.parse_args()

    sdk = load_json(REPO_ROOT / "config" / "sdk-version.json")
    source_lock = load_json(REPO_ROOT / "config" / "source-lock.json")
    platforms = load_json(REPO_ROOT / "config" / "platform-matrix.json")["platforms"]
    enabled_platforms = [platform for platform in platforms if platform["enabled"]]

    artifacts = []
    for platform in enabled_platforms:
        pattern = f"ffmpeg-sdk-{sdk['ffmpegVersion']}-v{sdk['sdkVersion']}-{platform['key']}.{platform['archiveExt']}"
        archive = args.release_assets / pattern
        checksum_file = args.release_assets / f"{pattern}.sha256"
        if not archive.exists():
            raise SystemExit(f"Missing SDK archive: {archive}")
        if not checksum_file.exists():
            raise SystemExit(f"Missing SDK checksum: {checksum_file}")

        expected_sha = checksum_file.read_text(encoding="utf-8").strip().split()[0]
        actual_sha = archive_sha256(archive)
        if actual_sha != expected_sha:
            raise SystemExit(f"Checksum mismatch for {archive.name}")

        artifacts.append({
            "platform": platform["key"],
            "os": platform["os"],
            "arch": platform["arch"],
            "triplet": platform["triplet"],
            "buildFamily": platform["buildFamily"],
            "archiveExt": platform["archiveExt"],
            "file": archive.name,
            "url": f"{args.base_url.rstrip('/')}/{archive.name}",
            "sha256": actual_sha,
            "size": archive.stat().st_size,
        })

    index = {
        "schemaVersion": 1,
        "name": "ffmpeg-base",
        "sdkVersion": sdk["sdkVersion"],
        "ffmpegVersion": sdk["ffmpegVersion"],
        "releaseTag": args.release_tag,
        "releaseChannel": sdk["releaseChannel"],
        "licenseMode": sdk["licenseMode"],
        "featureProfile": sdk["featureProfile"],
        "vcpkgBaseline": sdk["vcpkgBaseline"],
        "ffmpegSourceUrl": source_lock["url"],
        "ffmpegSourceSha256": source_lock["sha256"],
        "artifacts": artifacts,
    }

    args.output.parent.mkdir(parents=True, exist_ok=True)
    args.output.write_text(json.dumps(index, indent=2, sort_keys=True) + "\n", encoding="utf-8")


if __name__ == "__main__":
    main()
