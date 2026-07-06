#!/usr/bin/env bash
set -euo pipefail

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
cd "${ROOT_DIR}"

SDK_ARCH="${SDK_ARCH:-arm64}"
case "${SDK_ARCH}" in
  arm64|x86_64) ;;
  *)
    echo "Unsupported macOS SDK architecture: ${SDK_ARCH}" >&2
    exit 2
    ;;
esac

HOST_ARCH="$(uname -m)"
if [[ "$(uname -s)" != "Darwin" ]]; then
  echo "build-macos.sh must run on macOS." >&2
  exit 1
fi

if [[ "${HOST_ARCH}" != "${SDK_ARCH}" ]]; then
  echo "macos-${SDK_ARCH} SDK builds require a ${SDK_ARCH} macOS runner; current runner is ${HOST_ARCH}." >&2
  exit 1
fi

PLATFORM_KEY="macos-${SDK_ARCH}"
VCPKG_TRIPLET="$(python3 - "${PLATFORM_KEY}" <<'PY'
import json
import sys

platform_key = sys.argv[1]
with open("config/platform-matrix.json", "r", encoding="utf-8") as handle:
    matrix = json.load(handle)
for platform in matrix["platforms"]:
    if platform["key"] == platform_key:
        print(platform["triplet"])
        break
else:
    raise SystemExit(f"Missing platform matrix entry for {platform_key}")
PY
)"
BUILD_ROOT="${BUILD_ROOT:-${ROOT_DIR}/build/${PLATFORM_KEY}}"
DIST_DIR="${DIST_DIR:-${ROOT_DIR}/dist}"
SDK_VERSION="$(python3 -c 'import json; print(json.load(open("config/sdk-version.json"))["sdkVersion"])' < /dev/null)"
FFMPEG_VERSION="$(python3 -c 'import json; print(json.load(open("config/sdk-version.json"))["ffmpegVersion"])' < /dev/null)"
LICENSE_MODE="$(python3 -c 'import json; print(json.load(open("config/sdk-version.json"))["licenseMode"])' < /dev/null)"
FEATURE_PROFILE="$(python3 -c 'import json; print(json.load(open("config/sdk-version.json"))["featureProfile"])' < /dev/null)"
VCPKG_BASELINE="$(python3 -c 'import json; print(json.load(open("config/sdk-version.json"))["vcpkgBaseline"])' < /dev/null)"
FEATURES_JSON="$(python3 -c 'import json; profile=json.load(open("config/ffmpeg-profile.json")); features=profile["features"]["common"] + profile["features"].get("macos", []); print(json.dumps(features, separators=(",", ":")))' < /dev/null)"
SOURCE_LOCK_TAG="$(python3 -c 'import json; print(json.load(open("config/source-lock.json"))["tag"])' < /dev/null)"
SOURCE_LOCK_URL="$(python3 -c 'import json; print(json.load(open("config/source-lock.json"))["url"])' < /dev/null)"
SOURCE_LOCK_SHA256="$(python3 -c 'import json; print(json.load(open("config/source-lock.json"))["sha256"])' < /dev/null)"
PROFILE_NAME="$(python3 -c 'import json; print(json.load(open("config/ffmpeg-profile.json"))["profile"])' < /dev/null)"
PROFILE_LICENSE_MODE="$(python3 -c 'import json; print(json.load(open("config/ffmpeg-profile.json"))["licenseMode"])' < /dev/null)"
PROFILE_CONFIGURE_FLAGS=()
while IFS= read -r profile_configure_flag; do
  if [[ -n "${profile_configure_flag}" ]]; then
    PROFILE_CONFIGURE_FLAGS+=("${profile_configure_flag}")
  fi
done < <(python3 -c 'import json; profile=json.load(open("config/ffmpeg-profile.json")); print("\n".join(profile["configure"]["common"] + profile["configure"].get("macos", [])))' < /dev/null)

if [[ "${PROFILE_NAME}" != "${FEATURE_PROFILE}" ]]; then
  echo "config/ffmpeg-profile.json profile ${PROFILE_NAME} does not match sdk-version featureProfile ${FEATURE_PROFILE}." >&2
  exit 1
fi
if [[ "${PROFILE_LICENSE_MODE}" != "${LICENSE_MODE}" ]]; then
  echo "config/ffmpeg-profile.json licenseMode ${PROFILE_LICENSE_MODE} does not match sdk-version licenseMode ${LICENSE_MODE}." >&2
  exit 1
fi

FFMPEG_TAG="${SOURCE_LOCK_TAG}"
if [[ "${FFMPEG_TAG}" != "n${FFMPEG_VERSION}" ]]; then
  echo "config/source-lock.json tag ${FFMPEG_TAG} does not match FFmpeg version ${FFMPEG_VERSION}." >&2
  exit 1
fi
SOURCE_ARCHIVE="${BUILD_ROOT}/downloads/ffmpeg-${FFMPEG_TAG}.tar.gz"
SOURCE_DIR="${BUILD_ROOT}/src/FFmpeg-${FFMPEG_TAG}"
INSTALL_PREFIX="${BUILD_ROOT}/install"
SDK_PARENT_DIR="${BUILD_ROOT}/sdk"
SDK_DIR_NAME="ffmpeg-sdk-${FFMPEG_VERSION}-v${SDK_VERSION}-${PLATFORM_KEY}"
SDK_ROOT="${SDK_PARENT_DIR}/${SDK_DIR_NAME}"
ARCHIVE_PATH="${DIST_DIR}/${SDK_DIR_NAME}.zip"
MACOS_MIN_VERSION="${MACOS_MIN_VERSION:-11.0}"

VCPKG_ROOT="${VCPKG_ROOT:-${VCPKG_INSTALLATION_ROOT:-}}"
if [[ -n "${VCPKG_INSTALLED_DIR:-}" ]]; then
  VCPKG_DEPENDENCY_ROOT="${VCPKG_INSTALLED_DIR}/${VCPKG_TRIPLET}"
elif [[ -n "${VCPKG_ROOT}" ]]; then
  VCPKG_DEPENDENCY_ROOT="${VCPKG_ROOT}/installed/${VCPKG_TRIPLET}"
else
  echo "VCPKG_INSTALLED_DIR or VCPKG_ROOT is required for macOS SDK dependency lookup." >&2
  exit 1
fi

dependency_prefix() {
  local env_name="$1"
  local package_name="$2"
  local header="$3"
  local value="${!env_name:-}"

  if [[ -z "${value}" ]]; then
    value="${VCPKG_DEPENDENCY_ROOT}"
  fi
  if [[ -z "${value}" || ! -f "${value}/${header}" || ! -d "${value}/lib" ]]; then
    echo "${package_name} headers and libraries are required for the desktop LGPL app SDK profile." >&2
    echo "Run vcpkg install --triplet ${VCPKG_TRIPLET}, or set ${env_name} to a prefix containing ${header} and lib/." >&2
    exit 1
  fi
  printf '%s\n' "${value}"
}

LAME_PREFIX="$(dependency_prefix LAME_PREFIX lame include/lame/lame.h)"
LIBVPX_PREFIX="$(dependency_prefix LIBVPX_PREFIX libvpx include/vpx/vpx_encoder.h)"
LIBAOM_PREFIX="$(dependency_prefix LIBAOM_PREFIX aom include/aom/aom_encoder.h)"
OPUS_PREFIX="$(dependency_prefix OPUS_PREFIX opus include/opus/opus.h)"
LIBVORBIS_PREFIX="$(dependency_prefix LIBVORBIS_PREFIX libvorbis include/vorbis/codec.h)"

EXTERNAL_PREFIXES=(
  "${LAME_PREFIX}"
  "${LIBVPX_PREFIX}"
  "${LIBAOM_PREFIX}"
  "${OPUS_PREFIX}"
  "${LIBVORBIS_PREFIX}"
)
EXTERNAL_CFLAGS=()
EXTERNAL_LDFLAGS=()
EXTERNAL_PKG_CONFIG_PATHS=()
for dependency_prefix_path in "${EXTERNAL_PREFIXES[@]}"; do
  EXTERNAL_CFLAGS+=("-I${dependency_prefix_path}/include")
  EXTERNAL_LDFLAGS+=("-L${dependency_prefix_path}/lib")
  EXTERNAL_PKG_CONFIG_PATHS+=("${dependency_prefix_path}/lib/pkgconfig")
  EXTERNAL_PKG_CONFIG_PATHS+=("${dependency_prefix_path}/share/pkgconfig")
done
export PKG_CONFIG_PATH="$(IFS=:; echo "${EXTERNAL_PKG_CONFIG_PATHS[*]}")${PKG_CONFIG_PATH:+:${PKG_CONFIG_PATH}}"

mkdir -p "${BUILD_ROOT}/downloads" "${BUILD_ROOT}/src" "${DIST_DIR}"
rm -rf "${INSTALL_PREFIX}" "${SDK_ROOT}" "${ARCHIVE_PATH}" "${ARCHIVE_PATH}.sha256"

if [[ ! -f "${SOURCE_ARCHIVE}" ]]; then
  curl --fail --show-error --location --retry 3 --retry-delay 5 \
    "${SOURCE_LOCK_URL}" \
    -o "${SOURCE_ARCHIVE}"
fi
ACTUAL_SOURCE_SHA256="$(shasum -a 256 "${SOURCE_ARCHIVE}" | awk '{print $1}')"
if [[ "${ACTUAL_SOURCE_SHA256}" != "${SOURCE_LOCK_SHA256}" ]]; then
  echo "FFmpeg source archive SHA256 mismatch for ${SOURCE_ARCHIVE}." >&2
  echo "Expected: ${SOURCE_LOCK_SHA256}" >&2
  echo "Actual  : ${ACTUAL_SOURCE_SHA256}" >&2
  exit 1
fi

rm -rf "${SOURCE_DIR}"
tar -xzf "${SOURCE_ARCHIVE}" -C "${BUILD_ROOT}/src"

export GIT_CEILING_DIRECTORIES="${BUILD_ROOT}/src"

configure_flags=(
  "--prefix=${INSTALL_PREFIX}"
  "--arch=${SDK_ARCH}"
  "--cc=clang"
  "--cxx=clang++"
  "--extra-cflags=-arch ${SDK_ARCH} ${EXTERNAL_CFLAGS[*]} -mmacosx-version-min=${MACOS_MIN_VERSION}"
  "--extra-cxxflags=-arch ${SDK_ARCH} ${EXTERNAL_CFLAGS[*]} -mmacosx-version-min=${MACOS_MIN_VERSION}"
  "--extra-ldflags=-arch ${SDK_ARCH} ${EXTERNAL_LDFLAGS[*]} -mmacosx-version-min=${MACOS_MIN_VERSION}"
  "${PROFILE_CONFIGURE_FLAGS[@]}"
)

if [[ "${SDK_ARCH}" == "x86_64" ]]; then
  configure_flags+=("--disable-x86asm")
fi

pushd "${SOURCE_DIR}" >/dev/null
./configure "${configure_flags[@]}"

make -j"$(sysctl -n hw.ncpu)"
make install
popd >/dev/null

"${ROOT_DIR}/scripts/stage-sdk.sh" \
  --source "${SOURCE_DIR}" \
  --prefix "${INSTALL_PREFIX}" \
  --output "${SDK_ROOT}" \
  --platform macos \
  --arch "${SDK_ARCH}"

cmake \
  -D TEMPLATE_FILE="${ROOT_DIR}/templates/manifest.json.in" \
  -D OUTPUT_FILE="${SDK_ROOT}/manifest.json" \
  -D SDK_VERSION="${SDK_VERSION}" \
  -D FFMPEG_VERSION="${FFMPEG_VERSION}" \
  -D SDK_PLATFORM="macos" \
  -D SDK_ARCH="${SDK_ARCH}" \
  -D SDK_COMPILER="$(clang --version | head -n 1)" \
  -D VCPKG_BASELINE="${VCPKG_BASELINE}" \
  -D VCPKG_TRIPLET="${VCPKG_TRIPLET}" \
  -D FFMPEG_SOURCE_URL="${SOURCE_LOCK_URL}" \
  -D FFMPEG_SOURCE_SHA256="${SOURCE_LOCK_SHA256}" \
  -D SDK_FEATURES_JSON="${FEATURES_JSON}" \
  -D LICENSE_MODE="${LICENSE_MODE}" \
  -D BUILD_ID="${GITHUB_RUN_ID:-local}-${GITHUB_RUN_ATTEMPT:-0}" \
  -D CREATED_AT="$(date -u '+%Y-%m-%dT%H:%M:%SZ')" \
  -P "${ROOT_DIR}/scripts/generate-manifest.cmake"

cmake \
  -D SDK_ROOT="${SDK_ROOT}" \
  -D SDK_PLATFORM="macos" \
  -D SDK_ARCH="${SDK_ARCH}" \
  -P "${ROOT_DIR}/scripts/validate-sdk-layout.cmake"

pushd "${SDK_PARENT_DIR}" >/dev/null
zip -qry "${ARCHIVE_PATH}" "${SDK_DIR_NAME}"
popd >/dev/null

shasum -a 256 "${ARCHIVE_PATH}" | awk '{print $1}' > "${ARCHIVE_PATH}.sha256"

echo "SDK archive: ${ARCHIVE_PATH}"
echo "SHA256     : $(cat "${ARCHIVE_PATH}.sha256")"
