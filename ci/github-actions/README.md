# GitHub Actions

The active GitHub Actions workflow lives in `.github/workflows/build-desktop.yml`.

The workflow builds the enabled desktop entries from `config/platform-matrix.json`: `macos-arm64`, `macos-x86_64`, `windows-x86_64`, and `windows-arm64`.

Codec dependencies are installed with vcpkg manifest mode using the repository triplets. The FFmpeg upstream source archive is locked by `config/source-lock.json` and verified by SHA256 before extraction.

Pushes to `main` build the SDK and upload a short-lived workflow artifact for validation.

Manual runs from **Actions -> Build Desktop FFmpeg SDK -> Run workflow** also publish a GitHub Release.

The workflow produces:

- `ffmpeg-sdk-{ffmpegVersion}-v{sdkVersion}-macos-arm64.zip`
- `ffmpeg-sdk-{ffmpegVersion}-v{sdkVersion}-macos-arm64.zip.sha256`
- `ffmpeg-sdk-{ffmpegVersion}-v{sdkVersion}-macos-x86_64.zip`
- `ffmpeg-sdk-{ffmpegVersion}-v{sdkVersion}-macos-x86_64.zip.sha256`
- `ffmpeg-sdk-{ffmpegVersion}-v{sdkVersion}-windows-x86_64.zip`
- `ffmpeg-sdk-{ffmpegVersion}-v{sdkVersion}-windows-x86_64.zip.sha256`
- `ffmpeg-sdk-{ffmpegVersion}-v{sdkVersion}-windows-arm64.zip`
- `ffmpeg-sdk-{ffmpegVersion}-v{sdkVersion}-windows-arm64.zip.sha256`

For the current desktop release, the expected tag is `v20260706.1`.

Copy the GitHub Release URL plus SHA256 into the client repository declaration after the release is published.
