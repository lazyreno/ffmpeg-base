cmake_minimum_required(VERSION 3.22)

set(repo_root "${CMAKE_CURRENT_LIST_DIR}/../..")
set(workflow "${repo_root}/.github/workflows/build-desktop.yml")
set(version_file "${repo_root}/config/sdk-version.json")
set(profile_file "${repo_root}/config/ffmpeg-profile.json")
set(platform_file "${repo_root}/config/platform-matrix.json")
set(source_lock_file "${repo_root}/config/source-lock.json")
set(vcpkg_lock_file "${repo_root}/config/vcpkg-lock.json")
set(vcpkg_manifest "${repo_root}/vcpkg.json")
set(vcpkg_configuration "${repo_root}/vcpkg-configuration.json")
set(matrix_script "${repo_root}/scripts/generate-github-matrix.py")
set(artifact_index_script "${repo_root}/scripts/generate-artifact-index.py")
set(macos_build_script "${repo_root}/scripts/build-macos.sh")
set(windows_build_script "${repo_root}/scripts/build-windows-msvc.ps1")
set(stage_script "${repo_root}/scripts/stage-sdk.sh")
set(validate_script "${repo_root}/scripts/validate-sdk-layout.cmake")
set(generate_manifest_script "${repo_root}/scripts/generate-manifest.cmake")
set(manifest_template "${repo_root}/templates/manifest.json.in")

foreach(required_file IN ITEMS
    "${workflow}"
    "${version_file}"
    "${profile_file}"
    "${platform_file}"
    "${source_lock_file}"
    "${vcpkg_lock_file}"
    "${vcpkg_manifest}"
    "${vcpkg_configuration}"
    "${matrix_script}"
    "${artifact_index_script}"
    "${macos_build_script}"
    "${windows_build_script}"
    "${stage_script}"
    "${validate_script}"
    "${generate_manifest_script}"
    "${manifest_template}")
  if(NOT EXISTS "${required_file}")
    message(FATAL_ERROR "Required SDK production file is missing: ${required_file}")
  endif()
endforeach()

file(READ "${workflow}" workflow_content)
file(READ "${version_file}" version_content)
file(READ "${profile_file}" profile_content)
file(READ "${platform_file}" platform_content)
file(READ "${source_lock_file}" source_lock_content)
file(READ "${vcpkg_lock_file}" vcpkg_lock_content)
file(READ "${vcpkg_manifest}" vcpkg_manifest_content)
file(READ "${vcpkg_configuration}" vcpkg_configuration_content)
file(READ "${matrix_script}" matrix_script_content)
file(READ "${artifact_index_script}" artifact_index_script_content)
file(READ "${macos_build_script}" macos_build_script_content)
file(READ "${windows_build_script}" windows_build_script_content)
file(READ "${stage_script}" stage_script_content)
file(READ "${validate_script}" validate_script_content)
file(READ "${generate_manifest_script}" generate_manifest_script_content)
file(READ "${manifest_template}" manifest_template_content)

function(require_contains content pattern description)
  if(NOT "${content}" MATCHES "${pattern}")
    message(FATAL_ERROR "${description}")
  endif()
endfunction()

function(require_not_contains content pattern description)
  if("${content}" MATCHES "${pattern}")
    message(FATAL_ERROR "${description}")
  endif()
endfunction()

string(JSON sdk_version GET "${version_content}" sdkVersion)
string(JSON ffmpeg_version GET "${version_content}" ffmpegVersion)
string(JSON sdk_license GET "${version_content}" licenseMode)
string(JSON feature_profile GET "${version_content}" featureProfile)
string(JSON profile_name GET "${profile_content}" profile)
string(JSON profile_license GET "${profile_content}" licenseMode)
string(JSON source_lock_sha256 GET "${source_lock_content}" sha256)
string(JSON vcpkg_lock_repository GET "${vcpkg_lock_content}" repository)
string(JSON vcpkg_lock_commit GET "${vcpkg_lock_content}" commit)

if(NOT sdk_version STREQUAL "20260706.1")
  message(FATAL_ERROR "SDK version must stay on the first rebuilt repository release batch 20260706.1")
endif()
if(NOT ffmpeg_version STREQUAL "8.1.2")
  message(FATAL_ERROR "SDK must lock FFmpeg 8.1.2 until a deliberate version bump")
endif()
if(NOT feature_profile STREQUAL profile_name)
  message(FATAL_ERROR "sdk-version featureProfile must match config/ffmpeg-profile.json profile")
endif()
if(NOT sdk_license STREQUAL profile_license OR NOT sdk_license STREQUAL "lgpl")
  message(FATAL_ERROR "SDK version and FFmpeg profile must agree on LGPL license mode")
endif()
string(LENGTH "${source_lock_sha256}" source_lock_sha256_length)
if(NOT source_lock_sha256_length EQUAL 64 OR NOT source_lock_sha256 MATCHES "^[0-9a-f]+$")
  message(FATAL_ERROR "Source lock must record a lowercase SHA256 for the upstream FFmpeg source archive")
endif()
if(NOT vcpkg_lock_repository STREQUAL "https://github.com/microsoft/vcpkg.git")
  message(FATAL_ERROR "vcpkg lock must pin the official Microsoft vcpkg repository")
endif()
if(NOT vcpkg_lock_commit STREQUAL "1b31135aadd41bfd2c9e76d06b5f815e54a0adea")
  message(FATAL_ERROR "vcpkg lock must pin the verified vcpkg registry commit")
endif()
require_contains("${version_content}" "${vcpkg_lock_commit}" "sdk-version.json vcpkgBaseline must match vcpkg lock commit")
require_contains("${vcpkg_configuration_content}" "${vcpkg_lock_commit}" "vcpkg configuration baseline must match vcpkg lock commit")

require_not_contains("${version_content}" "\"defaultFeatures\"" "sdk-version.json must not own FFmpeg feature lists")
require_not_contains("${version_content}" "\"platformFeatureExtras\"" "sdk-version.json must not own platform FFmpeg feature extras")

foreach(platform_key IN ITEMS
    macos-arm64
    macos-x86_64
    windows-x86_64
    windows-arm64)
  require_contains("${platform_content}" "\"key\"[ \t\r\n]*:[ \t\r\n]*\"${platform_key}\"" "Platform matrix must declare ${platform_key}")
  require_not_contains("${workflow_content}" "platform:[ \t\r\n]*${platform_key}" "Workflow must not hard-code static platform matrix entry ${platform_key}")
endforeach()

foreach(platform_field IN ITEMS
    "\"buildFamily\""
    "\"runner\""
    "\"triplet\""
    "\"archiveExt\"")
  require_contains("${platform_content}" "${platform_field}" "Platform matrix must own platform field ${platform_field}")
endforeach()
require_contains("${platform_content}" "\"msvcArch\"" "Windows platform entries must declare msvcArch")

foreach(triplet_name IN ITEMS
    macos-arm64
    macos-x64
    windows-x64-msvc
    windows-arm64-msvc)
  if(NOT EXISTS "${repo_root}/triplets/${triplet_name}.cmake")
    message(FATAL_ERROR "Missing vcpkg triplet file: triplets/${triplet_name}.cmake")
  endif()
endforeach()

require_not_contains("${platform_content}" "\"triplet\"[ \t\r\n]*:[ \t\r\n]*\"[^\"]*_[^\"]*\"" "vcpkg triplet names must not contain underscores")

foreach(workflow_marker IN ITEMS
    "workflow_dispatch:"
    "pull_request:"
    "prepare-matrix:"
    "build-sdk:"
    "fromJson\\(needs\\.prepare-matrix\\.outputs\\.matrix\\)"
    "vcpkg_commit"
    "config/vcpkg-lock.json"
    "scripts/generate-github-matrix.py"
    "scripts/generate-artifact-index.py"
    "ffmpeg-sdk-release-\\$\\{\\{ needs\\.prepare-matrix\\.outputs\\.sdk_version \\}\\}"
    "contents: read"
    "contents: write"
    "vcpkg.json"
    "vcpkg-configuration.json"
    "triplets/\\*\\*"
    "tests/\\*\\*"
    "actions/checkout@v5"
    "Checkout pinned vcpkg"
    "bootstrap-vcpkg"
    "--vcpkg-root"
    "--overlay-triplets"
    "--x-install-root"
    "gh release view"
    "gh release create"
    "artifact-index.json")
  require_contains("${workflow_content}" "${workflow_marker}" "Workflow is missing governance marker: ${workflow_marker}")
endforeach()

require_not_contains("${workflow_content}" "build-macos:" "Workflow must not keep the old static macOS build job")
require_not_contains("${workflow_content}" "build-windows:" "Workflow must not keep the old static Windows build job")
require_not_contains("${workflow_content}" "actions/checkout@v4" "Workflow must not use Node 20 actions/checkout@v4")
require_not_contains("${workflow_content}" "ilammy/msvc-dev-cmd" "Workflow must not use the deprecated Node-based MSVC setup action")
require_not_contains("${workflow_content}" "(^|[ \t\r\n])vcpkg install" "Workflow must not invoke runner PATH vcpkg")
require_not_contains("${workflow_content}" "import hashlib" "Workflow must not inline artifact-index generation logic")
require_not_contains("${workflow_content}" "brew install|brew --prefix" "Workflow must not use Homebrew for production dependencies")
require_contains("${workflow_content}" "github\\.event_name == 'workflow_dispatch' \\|\\| startsWith\\(github\\.ref, 'refs/tags/v'\\)" "Release publishing must only run for manual dispatch or v* tags")
require_contains("${workflow_content}" "GITHUB_REF_NAME.*release_tag" "Tag-triggered releases must validate tag name against sdkVersion")

foreach(matrix_script_marker IN ITEMS
    "platform-matrix.json"
    "sdk-version.json"
    "vcpkg-lock.json"
    "buildFamily"
    "runner"
    "msvcArch"
    "TRIPLET_PATTERN"
    "github-output"
    "vcpkg_commit"
    "\"include\"")
  require_contains("${matrix_script_content}" "${matrix_script_marker}" "Matrix script is missing marker: ${matrix_script_marker}")
endforeach()

foreach(index_script_marker IN ITEMS
    "artifact-index.json"
    "schemaVersion"
    "releaseTag"
    "releaseChannel"
    "licenseMode"
    "featureProfile"
    "vcpkgBaseline"
    "ffmpegSourceUrl"
    "ffmpegSourceSha256"
    "platform-matrix.json"
    "\"os\""
    "\"arch\""
    "\"triplet\""
    "\"url\""
    "\"sha256\""
    "\"size\"")
  require_contains("${artifact_index_script_content}" "${index_script_marker}" "Artifact index script is missing marker: ${index_script_marker}")
endforeach()

foreach(vcpkg_package IN ITEMS mp3lame libvpx aom opus libvorbis)
  require_contains("${vcpkg_manifest_content}" "\"${vcpkg_package}\"" "vcpkg manifest must declare ${vcpkg_package}")
endforeach()

foreach(profile_flag IN ITEMS
    "--disable-autodetect"
    "--disable-everything"
    "--disable-network"
    "--enable-libmp3lame"
    "--enable-libvpx"
    "--enable-libaom"
    "--enable-libopus"
    "--enable-libvorbis"
    "--enable-demuxer=mov"
    "--enable-muxer=mp4"
    "--enable-decoder=h264"
    "--enable-parser=h264"
    "--enable-filter=scale"
    "--enable-videotoolbox"
    "--enable-audiotoolbox"
    "--enable-mediafoundation"
    "--enable-d3d11va"
    "--enable-filter=scale_d3d11")
  require_contains("${profile_content}" "${profile_flag}" "FFmpeg profile is missing required configure flag: ${profile_flag}")
endforeach()

foreach(forbidden_flag IN ITEMS
    "--enable-gpl"
    "--enable-version3"
    "--enable-libx264"
    "--enable-libx265"
    "--enable-libdav1d"
    "--enable-libvmaf")
  require_not_contains("${profile_content}" "${forbidden_flag}" "LGPL FFmpeg profile must not enable forbidden flag ${forbidden_flag}")
  require_not_contains("${macos_build_script_content}" "${forbidden_flag}" "macOS build script must not enable forbidden flag ${forbidden_flag}")
  require_not_contains("${windows_build_script_content}" "${forbidden_flag}" "Windows build script must not enable forbidden flag ${forbidden_flag}")
endforeach()

foreach(script_content IN ITEMS "${macos_build_script_content}" "${windows_build_script_content}")
  require_contains("${script_content}" "config/ffmpeg-profile\\.json" "Build scripts must load FFmpeg flags from config/ffmpeg-profile.json")
  require_contains("${script_content}" "PROFILE|Profile" "Build scripts must treat the FFmpeg profile as a named production input")
  require_not_contains("${script_content}" "platformFeatureExtras" "Build scripts must not read removed sdk-version platformFeatureExtras")
  require_not_contains("${script_content}" "defaultFeatures" "Build scripts must not read removed sdk-version defaultFeatures")
endforeach()

require_contains("${macos_build_script_content}" "curl --fail --show-error --location --retry 3" "macOS source download must fail loudly and retry transient network errors")
require_contains("${macos_build_script_content}" "VCPKG_TRIPLET" "macOS build must use the matrix-owned vcpkg triplet")
require_contains("${macos_build_script_content}" "GIT_CEILING_DIRECTORIES" "macOS SDK build must prevent FFmpeg version.sh from reading ffmpeg-base git metadata")
require_contains("${macos_build_script_content}" "--disable-x86asm" "macOS x86_64 build must not depend on unpinned nasm")
require_not_contains("${macos_build_script_content}" "brew --prefix" "macOS build must not discover production dependencies through Homebrew")

require_contains("${windows_build_script_content}" "--toolchain=msvc" "Windows SDK build must use FFmpeg's MSVC toolchain")
require_contains("${windows_build_script_content}" "--cc=clang-cl" "Windows SDK build must use clang-cl with the MSVC ABI")
require_contains("${windows_build_script_content}" "\\$FfmpegArch = \"x86_64\"" "Windows build must map x86_64 to FFmpeg x86_64")
require_contains("${windows_build_script_content}" "\\$FfmpegArch = \"aarch64\"" "Windows build must map arm64 to FFmpeg aarch64")
require_contains("${windows_build_script_content}" "\\$VcpkgTriplet = \"windows-x64-msvc\"" "Windows build must map x86_64 to repository vcpkg triplet")
require_contains("${windows_build_script_content}" "\\$VcpkgTriplet = \"windows-arm64-msvc\"" "Windows build must map arm64 to repository vcpkg triplet")
require_contains("${windows_build_script_content}" "MaximumRetryCount 3" "Windows source download must retry transient network errors")
require_not_contains("${windows_build_script_content}" "VcpkgDependencyTriplet" "Windows build must not reference the removed VcpkgDependencyTriplet variable")

foreach(manifest_var IN ITEMS
    FFMPEG_SOURCE_URL
    FFMPEG_SOURCE_SHA256
    SDK_FEATURES_JSON
    LICENSE_MODE)
  require_contains("${generate_manifest_script_content}" "${manifest_var}" "Manifest generation must require ${manifest_var}")
  require_contains("${macos_build_script_content}" "${manifest_var}" "macOS build must pass ${manifest_var} to manifest generation")
  require_contains("${windows_build_script_content}" "${manifest_var}" "Windows build must pass ${manifest_var} to manifest generation")
endforeach()

foreach(manifest_key IN ITEMS
    ffmpegSourceUrl
    ffmpegSourceSha256
    features
    licenseMode)
  require_contains("${manifest_template_content}" "${manifest_key}" "Manifest template must include ${manifest_key}")
endforeach()

foreach(validation_marker IN ITEMS
    "require_manifest_equals"
    "sdkVersion"
    "ffmpegVersion"
    "vcpkgBaseline"
    "ffmpegSourceSha256"
    "licenseMode"
    "NOT SDK_ARCH STREQUAL \"arm64\""
    "validate_windows_static_runtime")
  require_contains("${validate_script_content}" "${validation_marker}" "SDK validation is missing marker: ${validation_marker}")
endforeach()

foreach(stage_marker IN ITEMS
    "install_name_tool"
    "@loader_path"
    "codesign"
    "ffmpeg.exe"
    "@FFMPEG_EXECUTABLE_SUFFIX@|\\.exe"
    "\\.lib")
  require_contains("${stage_script_content}" "${stage_marker}" "SDK staging is missing marker: ${stage_marker}")
endforeach()
