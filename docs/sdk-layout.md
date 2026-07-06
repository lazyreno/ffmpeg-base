# FFmpeg SDK Layout

Each published SDK artifact must extract to one root directory with the same layout on every platform.

```text
ffmpeg-sdk-{ffmpegVersion}-v{sdkVersion}-{platform}/
  bin/                  # ffmpeg, ffprobe, and dynamic runtime libraries
  include/              # FFmpeg public headers
  lib/                  # link libraries or import libraries
  cmake/                # CMake package files consumed by clients
    FFmpegConfig.cmake
    FFmpegTargets.cmake
    FFmpegRuntime.cmake
  licenses/             # FFmpeg and third-party license notices
    LICENSE.ffmpeg.txt
  manifest.json         # SDK traceability metadata
```

The client must consume SDKs through the CMake package under `cmake/`. It must not discover Homebrew, system PATH, or developer-machine FFmpeg builds for official builds.

SDK production must also avoid host package-manager drift. The current production flow installs third-party codec dependencies through vcpkg manifest mode using `vcpkg.json`, `vcpkg-configuration.json`, and the platform triplet under `triplets/`. The upstream FFmpeg source archive is locked in `config/source-lock.json` and must pass SHA256 verification before extraction.

The current production targets are `macos-arm64`, `macos-x86_64`, `windows-x86_64`, and `windows-arm64`. `config/platform-matrix.json` is the only source for enabled platforms, runners, build family, architecture, triplet, and archive extension. Additional platforms should be added there only after their CI build and packaging flow is verified.

The current feature profile is named in `config/sdk-version.json` as `lgpl-desktop-app-v1`, while the actual FFmpeg feature list and configure flags live in `config/ffmpeg-profile.json`. macOS and Windows share the same FFmpeg whitelist required by the desktop app for transcode, compression, GIF, audio extraction, and audio cutting, then add platform-native hardware acceleration extras. The shared profile includes LGPL-compatible/BSD external codecs such as LAME, libvpx, libaom, Opus, and Vorbis, but excludes GPL encoders such as libx264 and libx265. macOS enables VideoToolbox encoders and hwaccels for H.264/HEVC. Windows enables MediaFoundation encoders and D3D11VA hwaccels for H.264/HEVC, plus the D3D11 hardware-frame filters needed to move frames between CPU and GPU pipelines.

For macOS, dynamic libraries are copied to both `lib/` and `bin/`. The `lib/` copy is used for CMake imported targets, while the `bin/` copy is used by clients that bundle runtime files beside the app executable for local runs.

For Windows, MSVC import libraries are copied to `lib/`, while `.dll`, `ffmpeg.exe`, and `ffprobe.exe` are copied to `bin/`.

The manifest records the FFmpeg upstream version, SDK version, vcpkg baseline, vcpkg triplet, feature list, license mode, source archive URL, and source archive SHA256. These fields make a released SDK traceable even after the CI runner and temporary workflow artifacts are gone. Release-level clients should discover platform archives through `artifact-index.json`, which includes platform, OS, architecture, triplet, URL, SHA256, size, SDK version, FFmpeg version, license mode, feature profile, and source SHA256. Per-SDK `manifest.json` remains the traceability record inside each archive.
