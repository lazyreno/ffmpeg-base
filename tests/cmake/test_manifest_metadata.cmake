cmake_minimum_required(VERSION 3.21)

set(repo_root "${CMAKE_CURRENT_LIST_DIR}/../..")
set(test_root "${CMAKE_CURRENT_BINARY_DIR}/manifest-metadata-test")
set(manifest_output "${test_root}/manifest.json")

file(REMOVE_RECURSE "${test_root}")
file(MAKE_DIRECTORY "${test_root}")

execute_process(
    COMMAND "${CMAKE_COMMAND}"
        -D "TEMPLATE_FILE=${repo_root}/templates/manifest.json.in"
        -D "OUTPUT_FILE=${manifest_output}"
        -D "SDK_VERSION=20260729.1"
        -D "FFMPEG_VERSION=8.1.2"
        -D "SDK_PLATFORM=macos"
        -D "SDK_ARCH=arm64"
        -D "SDK_COMPILER=AppleClang fixture"
        -D "VCPKG_BASELINE=fixture-baseline"
        -D "VCPKG_TRIPLET=arm64-osx"
        -D "FFMPEG_SOURCE_URL=https://example.invalid/ffmpeg.tar.xz"
        -D "FFMPEG_SOURCE_SHA256=1111111111111111111111111111111111111111111111111111111111111111"
        -D "SDK_FEATURES_JSON=[]"
        -D "LICENSE_MODE=gpl"
        -D "ARTIFACT_PROFILE=legacy"
        -D "MINIMUM_SYSTEM_VERSION=11.0"
        -D "BUILD_ID=fixture-1"
        -D "CREATED_AT=2026-08-05T00:00:00Z"
        -P "${repo_root}/scripts/generate-manifest.cmake"
    RESULT_VARIABLE generation_result
    OUTPUT_VARIABLE generation_output
    ERROR_VARIABLE generation_error)
if(NOT generation_result EQUAL 0)
    message(FATAL_ERROR "Manifest generation failed:\n${generation_output}\n${generation_error}")
endif()

file(READ "${manifest_output}" manifest_json)
string(JSON profile ERROR_VARIABLE profile_error GET "${manifest_json}" profile)
if(NOT profile_error STREQUAL "NOTFOUND")
    message(FATAL_ERROR "Manifest must contain profile: ${profile_error}")
endif()
string(JSON minimum_version ERROR_VARIABLE minimum_version_error GET "${manifest_json}" minimumSystemVersion)
if(NOT minimum_version_error STREQUAL "NOTFOUND")
    message(FATAL_ERROR "Manifest must contain minimumSystemVersion: ${minimum_version_error}")
endif()
if(NOT profile STREQUAL "legacy" OR NOT minimum_version STREQUAL "11.0")
    message(FATAL_ERROR "Manifest must preserve legacy profile and minimum system version")
endif()
