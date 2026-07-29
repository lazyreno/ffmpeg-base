# AI Stem Export FFmpeg Capability Design

## 1. Purpose

The desktop AI stem editor exports an edited track or a mixed selection with an
FFmpeg filter graph. Each input may have a start offset, volume adjustment, and
equal-power pan before all audible tracks are mixed. The current desktop SDK
already provides the required input/output formats and codecs, but its minimal
feature profile does not include every audio filter used by that graph.

This change makes the complete stem-export graph a declared and tested
capability of `ffmpeg-base`.

## 2. Scope

The SDK adds four common audio filters:

| Filter | Stem-export responsibility |
|---|---|
| `adelay` | Applies each track's non-negative start offset. |
| `aformat` | Normalizes filter inputs to a stereo channel layout. |
| `pan` | Applies the editor's equal-power left/right pan coefficients. |
| `amix` | Mixes the audible tracks and keeps the longest resulting duration. |

The profile already includes `volume`, which applies per-track gain, and
`aresample`, which supports audio format negotiation and resampling within the
graph. Both remain required and are covered by validation.

`amerge` and `channelsplit` are outside the scope. The editor mixes independent
Stem files; it does not concatenate inputs into a multichannel stream or split
one multichannel stream into separate channels.

The change does not alter FFmpeg `8.1.2`, the GPL software-codec profile, the
vcpkg baseline, external dependencies, platform matrix, or release asset
schema.

## 3. Runtime Contract

The SDK must execute the graph shape produced by the desktop client:

```text
[input] adelay
        -> volume
        -> aformat=channel_layouts=stereo
        -> pan=stereo
        -> [per-track output]

[track 0][track 1]... -> amix=duration=longest -> encoded output
```

The representative cloud-build smoke test uses two deterministic PCM inputs,
different delays, gains, and pan positions, then produces AAC in an M4A
container. FFprobe must confirm a readable stereo AAC stream with positive
duration.

Existing SDK capabilities already cover the surrounding pipeline:

| Requirement | Existing SDK component |
|---|---|
| MP3 Stem input | MP3 demuxer and decoder |
| M4A/AAC Stem input | MOV demuxer and AAC decoder |
| WAV/PCM Stem input | WAV demuxer and PCM decoders |
| M4A export | AAC encoder and MP4/MOV muxer |
| MP3 export | libmp3lame encoder and MP3 muxer |
| WAV export | PCM encoders and WAV muxer |

## 4. Configuration

`config/ffmpeg-profile.json` adds the following common feature declarations:

```text
filter-adelay
filter-aformat
filter-amix
filter-pan
```

It adds the matching configure flags:

```text
--enable-filter=adelay
--enable-filter=aformat
--enable-filter=amix
--enable-filter=pan
```

The immutable SDK identity advances from `20260723.1` to `20260729.1`.
`featureProfile` remains `gpl-software-desktop-app-v1` because this is a
compatible capability expansion of the same profile rather than a new license
or codec policy.

## 5. Validation

Validation is layered so a missing filter cannot produce a seemingly valid SDK
artifact.

### 5.1 Declaration validation

`tests/cmake/test_release_workflow.cmake` requires all six filters used by the
graph (`adelay`, `aformat`, `volume`, `pan`, `amix`, and `aresample`) in both the
feature list and configure flags. It also protects SDK version `20260729.1`.

### 5.2 Configure registry validation

`scripts/validate-ffmpeg-components.cmake` reads FFmpeg's generated
`libavfilter/filter_list.c` and requires:

```text
ff_af_adelay
ff_af_aformat
ff_af_amix
ff_af_aresample
ff_af_pan
ff_af_volume
```

This check runs without executing the target binary, so it also protects the
Windows ARM64 cross-build.

### 5.3 Staged runtime validation

On macOS arm64, macOS x86_64, and Windows x86_64,
`scripts/validate-sdk-layout.cmake`:

1. verifies all six filters appear in `ffmpeg -filters`;
2. runs the representative two-track graph against generated PCM fixtures;
3. verifies the output with FFprobe.

Windows ARM64 uses declaration and generated-registry validation because the
x86_64 GitHub runner cannot execute the ARM64 binaries.

The smoke-test helper has Python unit tests for its command construction,
fixture generation, probe validation, and failure diagnostics.

## 6. Failure Handling

Any missing declaration, generated registry symbol, runtime filter, failed
FFmpeg command, unreadable output, non-stereo output, wrong codec, or
non-positive duration fails the corresponding matrix job. Because the build
matrix does not use fail-fast but requires every job to succeed, diagnostics
remain available for each platform while an invalid SDK cannot be treated as a
successful cloud build.

Failure diagnostics include the platform, failed stage, command exit status,
FFmpeg stderr, and FFprobe stderr. Temporary media is removed automatically.

## 7. Delivery

Implementation is based on the current `origin/main`, which already uses the
GPL software-codec profile.

The delivery sequence is:

1. add tests and observe the expected failures;
2. add the minimal profile and validation implementation;
3. run local declaration and unit tests;
4. commit the focused implementation;
5. push `main` to trigger the existing four-platform GitHub Actions build;
6. inspect the cloud run through completion.

The push-triggered run uploads short-lived workflow artifacts and does not
publish a GitHub Release. Publishing immutable `v20260729.1` artifacts remains
a separate manual release action.

## 8. Acceptance Criteria

- The profile enables exactly the four missing stem-export filters.
- Existing `volume` and `aresample` capabilities remain enabled.
- Configure-time registry validation covers the complete six-filter graph.
- Native staged SDK validation lists all six filters and executes the real
  two-track graph successfully.
- Windows ARM64 receives equivalent static registry protection.
- Local declaration and validator unit tests pass.
- A focused implementation commit is pushed to `origin/main`.
- All four cloud SDK matrix jobs complete successfully.
- No GitHub Release is created by this task.
