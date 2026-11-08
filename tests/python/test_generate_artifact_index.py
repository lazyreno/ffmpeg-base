import hashlib
import json
import subprocess
import sys
import tempfile
import unittest
from pathlib import Path


REPO_ROOT = Path(__file__).resolve().parents[2]
GENERATOR = REPO_ROOT / "scripts" / "generate-artifact-index.py"
PLATFORM_MATRIX = REPO_ROOT / "config" / "platform-matrix.json"
SDK_VERSION = REPO_ROOT / "config" / "sdk-version.json"


class GenerateArtifactIndexTest(unittest.TestCase):
    def test_generator_emits_schema_v2_minimum_version_without_artifact_profile(self):
        platforms = json.loads(PLATFORM_MATRIX.read_text(encoding="utf-8"))["platforms"]
        sdk = json.loads(SDK_VERSION.read_text(encoding="utf-8"))

        with tempfile.TemporaryDirectory() as temporary_directory:
            temporary_path = Path(temporary_directory)
            assets_directory = temporary_path / "release-assets"
            assets_directory.mkdir()
            expected_archives = {}

            for platform in platforms:
                if not platform["enabled"]:
                    continue

                archive_name = (
                    f"ffmpeg-sdk-{sdk['ffmpegVersion']}-v{sdk['sdkVersion']}-"
                    f"{platform['key']}.{platform['archiveExt']}"
                )
                archive_path = assets_directory / archive_name
                archive_path.write_bytes(f"fixture-{platform['key']}".encode("utf-8"))
                archive_hash = hashlib.sha256(archive_path.read_bytes()).hexdigest()
                expected_archives[platform["key"]] = (archive_name, archive_hash)
                (assets_directory / f"{archive_name}.sha256").write_text(
                    f"{archive_hash}  {archive_name}\n", encoding="utf-8"
                )

            output_path = temporary_path / "artifact-index.json"
            subprocess.run(
                [
                    sys.executable,
                    str(GENERATOR),
                    "--release-assets",
                    str(assets_directory),
                    "--output",
                    str(output_path),
                    "--base-url",
                    f"https://example.invalid/releases/v{sdk['sdkVersion']}",
                    "--release-tag",
                    f"v{sdk['sdkVersion']}",
                ],
                check=True,
                text=True,
                capture_output=True,
            )

            index = json.loads(output_path.read_text(encoding="utf-8"))
            self.assertEqual(2, index["schemaVersion"])

            by_platform = {entry["platform"]: entry for entry in index["artifacts"]}
            self.assertEqual("6.1", by_platform["windows-x86_64"]["minimumSystemVersion"])
            self.assertEqual("11.0", by_platform["macos-x86_64"]["minimumSystemVersion"])
            self.assertEqual("11.0", by_platform["macos-arm64"]["minimumSystemVersion"])
            self.assertEqual("10.0", by_platform["windows-arm64"]["minimumSystemVersion"])
            for platform_key, (archive_name, archive_hash) in expected_archives.items():
                self.assertNotIn("profile", by_platform[platform_key])
                self.assertEqual(archive_name, by_platform[platform_key]["file"])
                self.assertEqual(archive_hash, by_platform[platform_key]["sha256"])


if __name__ == "__main__":
    unittest.main()
