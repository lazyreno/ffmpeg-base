# ffmpeg-base

Cloud-built FFmpeg SDK artifacts for desktop clients.

This repository is the SDK production side of the desktop FFmpeg pipeline. It builds
locked FFmpeg SDK archives in CI, publishes immutable artifacts, and exposes CMake
package files consumed by client applications. Official clients must hydrate these
artifacts instead of discovering FFmpeg from a developer machine.

The production model is declaration-driven: SDK version metadata, FFmpeg profile,
platform matrix, and source archive lock live under `config/`; CI and release
artifacts are generated from those declarations.
