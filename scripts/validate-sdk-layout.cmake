cmake_minimum_required(VERSION 3.21)

if(NOT DEFINED SDK_ROOT OR SDK_ROOT STREQUAL "")
    message(FATAL_ERROR "SDK_ROOT is required")
endif()

if(NOT DEFINED SDK_PLATFORM OR SDK_PLATFORM STREQUAL "")
    message(FATAL_ERROR "SDK_PLATFORM is required")
endif()

if(NOT DEFINED SDK_ARCH)
    set(SDK_ARCH "")
endif()

function(require_path path description)
    if(NOT EXISTS "${path}")
        message(FATAL_ERROR "${description} is required but was not found: ${path}")
    endif()
endfunction()

require_path("${SDK_ROOT}/bin" "SDK bin directory")
require_path("${SDK_ROOT}/include" "SDK include directory")
require_path("${SDK_ROOT}/lib" "SDK lib directory")
require_path("${SDK_ROOT}/cmake/FFmpegConfig.cmake" "FFmpegConfig.cmake")
require_path("${SDK_ROOT}/cmake/FFmpegTargets.cmake" "FFmpegTargets.cmake")
require_path("${SDK_ROOT}/cmake/FFmpegRuntime.cmake" "FFmpegRuntime.cmake")
require_path("${SDK_ROOT}/licenses" "SDK licenses directory")
require_path("${SDK_ROOT}/licenses/LICENSE.ffmpeg.txt" "FFmpeg license file")
require_path("${SDK_ROOT}/manifest.json" "SDK manifest")

function(validate_runtime_tool tool_path tool_name)
    execute_process(
        COMMAND "${tool_path}" -version
        RESULT_VARIABLE runtime_result
        OUTPUT_VARIABLE runtime_output
        ERROR_VARIABLE runtime_error
    )
    if(NOT runtime_result EQUAL 0)
        message(FATAL_ERROR
            "${tool_name} must run from the staged SDK:\n"
            "${runtime_output}\n${runtime_error}")
    endif()

    if(runtime_output MATCHES "version d[0-9a-f]+|version git-|version [0-9a-f]{7,}")
        message(FATAL_ERROR
            "${tool_name} version must come from the FFmpeg upstream release, "
            "not the ffmpeg-base repository:\n${runtime_output}")
    endif()
endfunction()

function(require_one_runtime_match pattern description)
    file(GLOB matching_runtime_files "${SDK_ROOT}/bin/${pattern}")
    if(NOT matching_runtime_files)
        message(FATAL_ERROR "${description} is required but no file matched: ${SDK_ROOT}/bin/${pattern}")
    endif()
endfunction()

function(validate_windows_static_runtime)
    foreach(component IN ITEMS
            avcodec
            avdevice
            avfilter
            avformat
            avutil
            swresample
            swscale)
        require_path("${SDK_ROOT}/lib/${component}.lib" "${component}.lib")
        require_one_runtime_match("${component}*.dll" "${component} runtime DLL")
    endforeach()

    foreach(third_party_pattern IN ITEMS
            "*mp3lame*.dll"
            "*vpx*.dll"
            "*aom*.dll"
            "*opus*.dll"
            "*vorbis*.dll"
            "*ogg*.dll")
        require_one_runtime_match("${third_party_pattern}" "third-party runtime DLL")
    endforeach()
endfunction()

if(SDK_PLATFORM STREQUAL "macos")
    require_path("${SDK_ROOT}/bin/ffmpeg" "ffmpeg executable")
    require_path("${SDK_ROOT}/bin/ffprobe" "ffprobe executable")
    require_path("${SDK_ROOT}/lib/libavcodec.dylib" "libavcodec.dylib")
    require_path("${SDK_ROOT}/lib/libavformat.dylib" "libavformat.dylib")
    require_path("${SDK_ROOT}/lib/libavutil.dylib" "libavutil.dylib")
    require_path("${SDK_ROOT}/lib/libswscale.dylib" "libswscale.dylib")
    require_path("${SDK_ROOT}/lib/libswresample.dylib" "libswresample.dylib")

    file(GLOB runtime_dylibs "${SDK_ROOT}/bin/*.dylib")
    if(NOT runtime_dylibs)
        message(FATAL_ERROR "macOS SDK must copy runtime dylibs into bin for client local runs")
    endif()

    find_program(OTOOL_EXECUTABLE otool)
    if(NOT OTOOL_EXECUTABLE)
        message(FATAL_ERROR "otool is required to validate macOS SDK runtime paths")
    endif()

    find_program(CODESIGN_EXECUTABLE codesign)
    if(NOT CODESIGN_EXECUTABLE)
        message(FATAL_ERROR "codesign is required to validate macOS SDK runtime signatures")
    endif()

    file(GLOB macos_runtime_files
        "${SDK_ROOT}/bin/ffmpeg"
        "${SDK_ROOT}/bin/ffprobe"
        "${SDK_ROOT}/bin/*.dylib"
        "${SDK_ROOT}/lib/*.dylib"
    )

    foreach(runtime_file IN LISTS macos_runtime_files)
        if(IS_SYMLINK "${runtime_file}")
            continue()
        endif()

        execute_process(
            COMMAND "${OTOOL_EXECUTABLE}" -L "${runtime_file}"
            RESULT_VARIABLE otool_result
            OUTPUT_VARIABLE otool_output
            ERROR_VARIABLE otool_error
        )
        if(NOT otool_result EQUAL 0)
            message(FATAL_ERROR "otool failed for ${runtime_file}:\n${otool_error}")
        endif()

        string(REGEX REPLACE "^[^\n]*\n" "" otool_dependencies "${otool_output}")
        if(otool_dependencies MATCHES "/Users/runner/|/opt/homebrew/|/usr/local/")
            message(FATAL_ERROR
                "macOS SDK runtime file contains host-specific dependency paths: "
                "${runtime_file}\n${otool_dependencies}")
        endif()

        execute_process(
            COMMAND "${CODESIGN_EXECUTABLE}" --verify --strict --verbose=2 "${runtime_file}"
            RESULT_VARIABLE codesign_result
            OUTPUT_VARIABLE codesign_output
            ERROR_VARIABLE codesign_error
        )
        if(NOT codesign_result EQUAL 0)
            message(FATAL_ERROR
                "macOS SDK runtime file has an invalid code signature: "
                "${runtime_file}\n${codesign_output}\n${codesign_error}")
        endif()
    endforeach()

    validate_runtime_tool("${SDK_ROOT}/bin/ffmpeg" "ffmpeg")
    validate_runtime_tool("${SDK_ROOT}/bin/ffprobe" "ffprobe")
elseif(SDK_PLATFORM STREQUAL "windows")
    require_path("${SDK_ROOT}/bin/ffmpeg.exe" "ffmpeg.exe")
    require_path("${SDK_ROOT}/bin/ffprobe.exe" "ffprobe.exe")

    file(GLOB runtime_dlls "${SDK_ROOT}/bin/*.dll")
    if(NOT runtime_dlls)
        message(FATAL_ERROR "Windows SDK must copy runtime DLLs into bin for client local runs")
    endif()

    validate_windows_static_runtime()

    if(NOT SDK_ARCH STREQUAL "arm64")
        validate_runtime_tool("${SDK_ROOT}/bin/ffmpeg.exe" "ffmpeg.exe")
        validate_runtime_tool("${SDK_ROOT}/bin/ffprobe.exe" "ffprobe.exe")
    endif()
else()
    message(FATAL_ERROR "Unsupported SDK_PLATFORM: ${SDK_PLATFORM}")
endif()

file(READ "${SDK_ROOT}/manifest.json" manifest_json)
set(repo_root "${CMAKE_CURRENT_LIST_DIR}/..")
file(READ "${repo_root}/config/sdk-version.json" sdk_version_json)
file(READ "${repo_root}/config/source-lock.json" source_lock_json)

function(require_manifest_string key)
    string(JSON manifest_value ERROR_VARIABLE manifest_error GET "${manifest_json}" "${key}")
    if(NOT manifest_error STREQUAL "NOTFOUND")
        message(FATAL_ERROR "manifest.json is missing ${key}: ${manifest_error}")
    endif()
endfunction()

function(require_manifest_equals key expected_value)
    string(JSON manifest_value ERROR_VARIABLE manifest_error GET "${manifest_json}" "${key}")
    if(NOT manifest_error STREQUAL "NOTFOUND")
        message(FATAL_ERROR "manifest.json is missing ${key}: ${manifest_error}")
    endif()
    if(NOT manifest_value STREQUAL "${expected_value}")
        message(FATAL_ERROR
            "manifest.json ${key} mismatch.\n"
            "Expected: ${expected_value}\n"
            "Actual  : ${manifest_value}")
    endif()
endfunction()

foreach(required_json_key IN ITEMS
        name
        sdkVersion
        ffmpegVersion
        platform
        arch
        compiler
        vcpkgBaseline
        vcpkgTriplet
        ffmpegSourceUrl
        ffmpegSourceSha256
        features
        licenseMode
        buildId
        createdAt)
    require_manifest_string("${required_json_key}")
endforeach()

string(JSON expected_sdk_version GET "${sdk_version_json}" sdkVersion)
string(JSON expected_ffmpeg_version GET "${sdk_version_json}" ffmpegVersion)
string(JSON expected_vcpkg_baseline GET "${sdk_version_json}" vcpkgBaseline)
string(JSON expected_license_mode GET "${sdk_version_json}" licenseMode)
string(JSON expected_source_url GET "${source_lock_json}" url)
string(JSON expected_source_sha256 GET "${source_lock_json}" sha256)

if(SDK_PLATFORM STREQUAL "macos")
    set(expected_triplet "macos-${SDK_ARCH}")
elseif(SDK_PLATFORM STREQUAL "windows")
    set(expected_triplet "windows-${SDK_ARCH}-msvc")
endif()

require_manifest_equals("name" "ffmpeg-base")
require_manifest_equals("sdkVersion" "${expected_sdk_version}")
require_manifest_equals("ffmpegVersion" "${expected_ffmpeg_version}")
require_manifest_equals("platform" "${SDK_PLATFORM}")
require_manifest_equals("arch" "${SDK_ARCH}")
require_manifest_equals("vcpkgBaseline" "${expected_vcpkg_baseline}")
require_manifest_equals("vcpkgTriplet" "${expected_triplet}")
require_manifest_equals("ffmpegSourceUrl" "${expected_source_url}")
require_manifest_equals("ffmpegSourceSha256" "${expected_source_sha256}")
require_manifest_equals("licenseMode" "${expected_license_mode}")
