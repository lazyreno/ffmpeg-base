# Release Process

The first public test flow uses GitHub Releases from the personal `ffmpeg-base` repository.

1. Update `config/sdk-version.json` when the SDK version, FFmpeg version, feature profile name, or license mode changes.
2. Update `config/ffmpeg-profile.json` when the FFmpeg feature profile or configure flags change.
3. Update `config/source-lock.json` when the upstream FFmpeg source tag or archive SHA256 changes.
4. Install codec dependencies through vcpkg manifest mode using `vcpkg.json`, `vcpkg-configuration.json`, and the platform triplet under `triplets/`.
5. Generate the GitHub Actions matrix from `config/platform-matrix.json` with `scripts/generate-github-matrix.py`.
6. Assemble each SDK into the standard layout documented in `docs/sdk-layout.md`.
7. Generate `manifest.json` from `templates/manifest.json.in`, including the FFmpeg source URL, source SHA256, and feature list loaded from `config/ffmpeg-profile.json`.
8. Archive the SDK as `ffmpeg-sdk-{ffmpegVersion}-v{sdkVersion}-{platform}.{archiveExt}`.
9. Compute SHA256 for each archive.
10. Generate `artifact-index.json` with `scripts/generate-artifact-index.py`.
11. Publish the SDK either by manually running `.github/workflows/build-desktop.yml` or by pushing a protected `v{sdkVersion}` tag. Both paths upload archives plus `artifact-index.json` to a GitHub Release tagged `v{sdkVersion}` and titled `FFmpeg SDK {ffmpegVersion} v{sdkVersion}`.
12. Update the client declaration file with the GitHub Release `artifact-index.json` URL and expected SDK version.

Published SDK archives are immutable. If any build input changes, publish a new SDK version instead of replacing an existing archive.

## GitHub Actions Flow

The active desktop workflow is `.github/workflows/build-desktop.yml`.

The workflow starts with `prepare-matrix`, which validates declarations and generates the build matrix from `config/platform-matrix.json`. `build-sdk` then runs the enabled platforms declared there. macOS platforms use the configured macOS runners. Windows platforms use `windows-2022` with MSVC plus MSYS2 for FFmpeg's configure/make environment. Each job installs the LGPL codec dependency set with vcpkg manifest mode, downloads the FFmpeg source archive locked by `config/source-lock.json`, verifies the source SHA256 before extraction, builds a minimal shared SDK, validates the SDK layout, then uploads the archive as a workflow artifact.

Windows ARM64 SDKs are cross-built on an x64 Windows runner. The workflow does not execute ARM64 `ffmpeg.exe` or `ffprobe.exe` on that runner; instead, layout validation performs static checks for required import libraries, FFmpeg DLLs, third-party runtime DLLs, manifest metadata, and license files. Windows x86_64 and macOS SDKs still execute `ffmpeg -version` and `ffprobe -version` during validation.

`main` push builds keep uploading a short-lived workflow artifact for CI inspection, but they do not publish a GitHub Release.

Manual `workflow_dispatch` runs and `v*` tag pushes publish a GitHub Release after all desktop artifacts are built. Tag-triggered releases must match `v{sdkVersion}` from `config/sdk-version.json`; the workflow rejects mismatched tags and existing releases so a published SDK cannot be replaced silently. The publish job uses a `sdkVersion` concurrency group, so two release attempts for the same SDK batch cannot publish at the same time. The release also includes `artifact-index.json`, which lets clients resolve the correct platform archive URL and checksum without hard-coding every asset URL.
