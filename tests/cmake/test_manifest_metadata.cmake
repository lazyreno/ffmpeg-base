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
        -D "FEATURE_PROFILE=gpl-desktop-media"
        -D "SDK_EXTERNAL_DEPENDENCIES_JSON=[\"zlib\"]"
        -D "LICENSE_MODE=gpl"
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
if(profile_error STREQUAL "NOTFOUND")
    message(FATAL_ERROR "Manifest must not contain an artifact profile")
endif()
string(JSON minimum_version ERROR_VARIABLE minimum_version_error GET "${manifest_json}" minimumSystemVersion)
if(NOT minimum_version_error STREQUAL "NOTFOUND")
    message(FATAL_ERROR "Manifest must contain minimumSystemVersion: ${minimum_version_error}")
endif()
if(NOT minimum_version STREQUAL "11.0")
    message(FATAL_ERROR "Manifest must preserve minimum system version")
endif()
string(JSON feature_profile GET "${manifest_json}" featureProfile)
if(NOT feature_profile STREQUAL "gpl-desktop-media")
    message(FATAL_ERROR "Manifest must use the configured feature profile")
endif()
string(JSON legacy_features ERROR_VARIABLE features_error GET "${manifest_json}" features)
if(features_error STREQUAL "NOTFOUND")
    message(FATAL_ERROR "Manifest must not contain legacy features")
endif()
string(JSON components_file GET "${manifest_json}" componentsFile)
if(NOT components_file STREQUAL "components.json")
    message(FATAL_ERROR "Manifest must reference components.json")
endif()
