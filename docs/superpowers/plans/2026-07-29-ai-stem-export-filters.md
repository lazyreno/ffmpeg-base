# AI Stem Export FFmpeg Capabilities Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Publish a cloud-validated FFmpeg SDK build that can execute the desktop AI Stem editor's delay, gain, stereo-format, pan, and mix export graph.

**Architecture:** Keep the existing minimal declaration-driven FFmpeg profile and add only the four missing filters. Protect the capability at declaration time, after FFmpeg configure through its generated filter registry, and after SDK staging with a real two-input M4A export smoke test.

**Tech Stack:** FFmpeg 8.1.2, JSON feature declarations, CMake script tests, Python 3 standard library, GitHub Actions.

## Global Constraints

- SDK version is `20260729.1`.
- FFmpeg version remains `8.1.2`.
- Feature profile remains `gpl-software-desktop-app-v1`.
- License mode remains GPL.
- Add only `adelay`, `aformat`, `amix`, and `pan`; keep existing `aresample` and `volume`.
- Do not add `amerge`, `channelsplit`, external dependencies, or platform entries.
- Windows ARM64 must receive static generated-registry validation without executing target binaries.
- Push-triggered cloud compilation must not publish a GitHub Release.

---

### Task 1: Profile declaration and SDK identity

**Files:**
- Modify: `tests/cmake/test_release_workflow.cmake:88`
- Modify: `tests/cmake/test_release_workflow.cmake:122`
- Modify: `config/sdk-version.json:2`
- Modify: `config/ffmpeg-profile.json:107`
- Modify: `config/ffmpeg-profile.json:232`

**Interfaces:**
- Consumes: existing `config/sdk-version.json` and `config/ffmpeg-profile.json` declaration schema.
- Produces: common features `filter-adelay`, `filter-aformat`, `filter-amix`, `filter-pan` and matching `--enable-filter` flags.

- [ ] **Step 1: Write the failing declaration test**

Change the SDK assertion to:

```cmake
if(NOT sdk_version STREQUAL "20260729.1")
  message(FATAL_ERROR "SDK version must identify the AI stem export filter release 20260729.1")
endif()
```

Replace the current three-filter loop with:

```cmake
foreach(audio_filter IN ITEMS
    adelay
    aformat
    amix
    aresample
    pan
    volume
    atempo
    asetrate
    areverse)
  require_contains(
    "${profile_content}"
    "\"filter-${audio_filter}\""
    "FFmpeg feature profile must declare the ${audio_filter} filter")
  require_contains(
    "${profile_content}"
    "--enable-filter=${audio_filter}"
    "FFmpeg configure options must enable the ${audio_filter} filter")
endforeach()
```

- [ ] **Step 2: Run the declaration test and verify RED**

Run:

```bash
cmake -P tests/cmake/test_release_workflow.cmake
```

Expected: FAIL because `config/sdk-version.json` still contains `20260723.1`.

- [ ] **Step 3: Add the minimal profile declarations**

Set:

```json
"sdkVersion": "20260729.1"
```

Add these entries to `features.common` alongside the existing audio filters:

```json
"filter-adelay",
"filter-aformat",
"filter-amix",
"filter-pan",
```

Add these entries to `configure.common`:

```json
"--enable-filter=adelay",
"--enable-filter=aformat",
"--enable-filter=amix",
"--enable-filter=pan",
```

- [ ] **Step 4: Run the declaration test and verify GREEN**

Run:

```bash
python3 -m json.tool config/sdk-version.json >/dev/null
python3 -m json.tool config/ffmpeg-profile.json >/dev/null
cmake -P tests/cmake/test_release_workflow.cmake
```

Expected: all commands exit zero.

- [ ] **Step 5: Commit**

```bash
git add config/sdk-version.json config/ffmpeg-profile.json tests/cmake/test_release_workflow.cmake
git commit -m "build: enable AI stem export filters"
```

---

### Task 2: Configure-time filter registry protection

**Files:**
- Modify: `tests/cmake/test_release_workflow.cmake`
- Modify: `scripts/validate-ffmpeg-components.cmake`

**Interfaces:**
- Consumes: FFmpeg generated registry at `libavfilter/filter_list.c`.
- Produces: configure-time assertions for `ff_af_adelay`, `ff_af_aformat`, `ff_af_amix`, `ff_af_aresample`, `ff_af_pan`, and `ff_af_volume`.

- [ ] **Step 1: Write the failing governance test**

Add the filter registry path and every required symbol to
`component_validator_marker`:

```cmake
"libavfilter/filter_list.c"
"foreach\\(audio_filter IN ITEMS adelay aformat amix aresample pan volume\\)"
"ff_af_\\$\\{audio_filter\\}"
```

- [ ] **Step 2: Run the governance test and verify RED**

Run:

```bash
cmake -P tests/cmake/test_release_workflow.cmake
```

Expected: FAIL because `scripts/validate-ffmpeg-components.cmake` does not read
`libavfilter/filter_list.c`.

- [ ] **Step 3: Implement filter registry validation**

Add:

```cmake
set(filter_list "${SOURCE_DIR}/libavfilter/filter_list.c")
```

Include `filter_list` in the required registry path loop, read its contents,
and require:

```cmake
foreach(audio_filter IN ITEMS adelay aformat amix aresample pan volume)
    require_registry_symbol(
        "${filter_list}" "${filter_list_content}"
        "ff_af_${audio_filter}" "${audio_filter} audio filter")
endforeach()
```

- [ ] **Step 4: Verify GREEN against declarations and an existing configured tree**

Run:

```bash
cmake -P tests/cmake/test_release_workflow.cmake
cmake \
  -D SOURCE_DIR="$PWD/build/macos-arm64/src/FFmpeg-n8.1.2" \
  -P scripts/validate-ffmpeg-components.cmake
```

Expected:

- governance test exits zero;
- configured-tree validation fails and names `ff_af_adelay`, proving the
  validator detects the currently missing capability.

- [ ] **Step 5: Commit**

```bash
git add scripts/validate-ffmpeg-components.cmake tests/cmake/test_release_workflow.cmake
git commit -m "test: validate configured stem export filters"
```

---

### Task 3: End-to-end Stem graph validator

**Files:**
- Create: `scripts/validate-ai-stem-export.py`
- Create: `tests/python/test_validate_ai_stem_export.py`
- Modify: `scripts/validate-sdk-layout.cmake`
- Modify: `tests/cmake/test_release_workflow.cmake`
- Modify: `.github/workflows/build-desktop.yml`

**Interfaces:**
- Consumes: staged `ffmpeg`, staged `ffprobe`, and a platform name.
- Produces: `validate_ai_stem_export(ffmpeg, ffprobe, platform)` process result
  and a command-line validator with `--ffmpeg`, `--ffprobe`, and `--platform`.

- [ ] **Step 1: Write failing Python unit tests**

Create `tests/python/test_validate_ai_stem_export.py` that imports the script
and verifies:

```python
class AiStemExportValidatorTest(unittest.TestCase):
    def test_filter_graph_matches_desktop_contract(self):
        graph = MODULE.build_filter_complex()
        for name in ("adelay=", "volume=", "aformat=", "pan=", "amix="):
            self.assertIn(name, graph)
        self.assertIn("duration=longest", graph)

    def test_pcm_fixture_is_non_empty_stereo_s16le(self):
        with tempfile.TemporaryDirectory() as directory:
            path = Path(directory) / "track.pcm"
            MODULE.write_pcm(path, frequency=440.0, duration_seconds=0.05)
            self.assertEqual(4800 * 2, path.stat().st_size)

    def test_ffmpeg_command_maps_filter_output_to_aac_m4a(self):
        command = MODULE.build_ffmpeg_command(
            Path("ffmpeg"), Path("a.pcm"), Path("b.pcm"), Path("out.m4a"))
        self.assertIn("-filter_complex", command)
        self.assertIn("[out]", command)
        self.assertIn("aac", command)
        self.assertEqual("mp4", command[-2])

    def test_probe_validation_requires_aac_stereo_and_positive_duration(self):
        MODULE.validate_probe_payload({
            "streams": [{"codec_name": "aac", "sample_rate": "48000", "channels": 2}],
            "format": {"duration": "0.25"},
        })
        with self.assertRaises(RuntimeError):
            MODULE.validate_probe_payload({
                "streams": [{"codec_name": "aac", "sample_rate": "48000", "channels": 1}],
                "format": {"duration": "0.25"},
            })
```

- [ ] **Step 2: Run Python tests and verify RED**

Run:

```bash
python3 -m unittest tests/python/test_validate_ai_stem_export.py -v
```

Expected: ERROR because `scripts/validate-ai-stem-export.py` does not exist.

- [ ] **Step 3: Implement the validator**

Create `scripts/validate-ai-stem-export.py` with:

```python
SAMPLE_RATE = 48_000
CHANNELS = 2

def build_filter_complex():
    return (
        "[0:a]adelay=delays=0:all=1,volume=0.8,"
        "aformat=channel_layouts=stereo,"
        "pan=stereo|c0=0.923879532511*c0|c1=0.382683432365*c1[s0];"
        "[1:a]adelay=delays=40:all=1,volume=0.5,"
        "aformat=channel_layouts=stereo,"
        "pan=stereo|c0=0.382683432365*c0|c1=0.923879532511*c1[s1];"
        "[s0][s1]amix=inputs=2:duration=longest[out]"
    )
```

`write_pcm()` writes deterministic signed 16-bit little-endian stereo sine
samples. `build_ffmpeg_command()` creates two raw PCM inputs and appends:

```python
[
    "-filter_complex", build_filter_complex(),
    "-map", "[out]",
    "-c:a", "aac",
    "-b:a", "256k",
    "-f", "mp4",
    str(output_path),
]
```

`validate_probe_payload()` requires AAC, 48 kHz, two channels, and duration
greater than zero. `main()` generates two fixtures in a temporary directory,
runs FFmpeg and FFprobe with captured output, raises diagnostics on failure,
and prints:

```text
Validated AI stem export filter graph.
```

- [ ] **Step 4: Run Python tests and verify GREEN**

Run:

```bash
python3 -m unittest tests/python/test_validate_ai_stem_export.py -v
```

Expected: all tests pass.

- [ ] **Step 5: Write failing CMake wiring tests**

Update `tests/cmake/test_release_workflow.cmake` to require:

```cmake
"python3 -m unittest tests/python/test_validate_ai_stem_export\\.py -v"
"validate-ai-stem-export\\.py"
"validate_ai_stem_export"
"validate_stem_export_filters"
"foreach\\(audio_filter IN ITEMS adelay aformat amix aresample pan volume\\)"
```

- [ ] **Step 6: Run the governance test and verify RED**

Run:

```bash
cmake -P tests/cmake/test_release_workflow.cmake
```

Expected: FAIL because workflow and staged-SDK validation are not wired.

- [ ] **Step 7: Wire native runtime validation**

Add the Python unit suite to the workflow declaration checks:

```yaml
python3 -m unittest tests/python/test_validate_ai_stem_export.py -v
```

In `scripts/validate-sdk-layout.cmake`, add:

```cmake
function(validate_stem_export_filters tool_path)
    foreach(audio_filter IN ITEMS adelay aformat amix aresample pan volume)
        validate_runtime_component("${tool_path}" "-filters" "${audio_filter}" "filter")
    endforeach()
endfunction()

function(validate_ai_stem_export ffmpeg_path ffprobe_path platform_name)
    find_program(PYTHON_EXECUTABLE NAMES python3 python REQUIRED)
    execute_process(
        COMMAND "${PYTHON_EXECUTABLE}"
            "${CMAKE_CURRENT_LIST_DIR}/validate-ai-stem-export.py"
            --ffmpeg "${ffmpeg_path}"
            --ffprobe "${ffprobe_path}"
            --platform "${platform_name}"
        RESULT_VARIABLE stem_export_result
        OUTPUT_VARIABLE stem_export_output
        ERROR_VARIABLE stem_export_error)
    if(NOT stem_export_result EQUAL 0)
        message(FATAL_ERROR
            "AI stem export validation failed:\n"
            "${stem_export_output}\n${stem_export_error}")
    endif()
    message(STATUS "${stem_export_output}")
endfunction()
```

Call both functions beside the existing raw PCM checks for macOS and for
Windows when `SDK_ARCH` is not `arm64`.

- [ ] **Step 8: Verify all local tests**

Run:

```bash
python3 -m unittest discover -s tests/python -p 'test_*.py' -v
cmake -P tests/cmake/test_release_workflow.cmake
git diff --check
```

Expected: all commands exit zero.

- [ ] **Step 9: Commit**

```bash
git add \
  .github/workflows/build-desktop.yml \
  scripts/validate-ai-stem-export.py \
  scripts/validate-sdk-layout.cmake \
  tests/cmake/test_release_workflow.cmake \
  tests/python/test_validate_ai_stem_export.py
git commit -m "test: exercise AI stem export graph"
```

---

### Task 4: Final verification and cloud build

**Files:**
- Verify only; no production files added.

**Interfaces:**
- Consumes: committed `main` at SDK version `20260729.1`.
- Produces: a push-triggered GitHub Actions run with four successful SDK jobs.

- [ ] **Step 1: Run final local verification**

```bash
python3 -m json.tool config/sdk-version.json >/dev/null
python3 -m json.tool config/ffmpeg-profile.json >/dev/null
python3 -m unittest discover -s tests/python -p 'test_*.py' -v
cmake -P tests/cmake/test_release_workflow.cmake
git diff --check
git status --short --branch
```

Expected: tests pass, no diff errors, and the worktree is clean.

- [ ] **Step 2: Review the committed delta**

```bash
git log --oneline origin/main..HEAD
git diff --stat origin/main...HEAD
git diff origin/main...HEAD -- \
  config/sdk-version.json \
  config/ffmpeg-profile.json \
  scripts/validate-ffmpeg-components.cmake \
  scripts/validate-ai-stem-export.py \
  scripts/validate-sdk-layout.cmake \
  tests/cmake/test_release_workflow.cmake \
  tests/python/test_validate_ai_stem_export.py \
  .github/workflows/build-desktop.yml
```

Expected: only the approved design, implementation plan, filter capability,
and validation changes are present.

- [ ] **Step 3: Push and identify the cloud run**

```bash
git push origin main
gh run list \
  --repo lazyreno/ffmpeg-base \
  --workflow "Build Desktop FFmpeg SDK" \
  --branch main \
  --event push \
  --limit 1
```

Expected: the newest run targets the pushed commit and is queued or in
progress.

- [ ] **Step 4: Watch the cloud build to completion**

```bash
gh run watch <run-id> \
  --repo lazyreno/ffmpeg-base \
  --exit-status
```

Expected: `prepare-matrix` and all four platform SDK jobs succeed;
`publish-release` is skipped because this is a push-triggered run.

- [ ] **Step 5: Confirm no Release was created**

```bash
gh release view v20260729.1 --repo lazyreno/ffmpeg-base
```

Expected: command reports that the release was not found.
