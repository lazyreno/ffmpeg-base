#!/usr/bin/env bash
set -euo pipefail

usage() {
  cat >&2 <<'EOF'
Usage: stage-sdk.sh --source <ffmpeg-source> --prefix <install-prefix> --output <sdk-root> --platform <platform> --arch <arch> --vcpkg-root <installed-triplet>
EOF
}

SOURCE_DIR=""
INSTALL_PREFIX=""
SDK_ROOT=""
SDK_PLATFORM=""
SDK_ARCH=""
VCPKG_DEPENDENCY_ROOT=""

while [[ $# -gt 0 ]]; do
  case "$1" in
    --source) SOURCE_DIR="$2"; shift 2 ;;
    --prefix) INSTALL_PREFIX="$2"; shift 2 ;;
    --output) SDK_ROOT="$2"; shift 2 ;;
    --platform) SDK_PLATFORM="$2"; shift 2 ;;
    --arch) SDK_ARCH="$2"; shift 2 ;;
    --vcpkg-root) VCPKG_DEPENDENCY_ROOT="$2"; shift 2 ;;
    *) usage; exit 2 ;;
  esac
done

[[ -n "${SOURCE_DIR}" && -d "${SOURCE_DIR}" ]] || { usage; exit 2; }
[[ -n "${INSTALL_PREFIX}" && -d "${INSTALL_PREFIX}" ]] || { usage; exit 2; }
[[ -n "${SDK_ROOT}" ]] || { usage; exit 2; }
[[ -d "${VCPKG_DEPENDENCY_ROOT}/share" ]] || { usage; exit 2; }
case "${SDK_PLATFORM}:${SDK_ARCH}" in
  macos:arm64|macos:x86_64|windows:x86_64|windows:arm64) ;;
  *)
    echo "Unsupported SDK platform/architecture: ${SDK_PLATFORM}/${SDK_ARCH}" >&2
    exit 2
    ;;
esac

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
rm -rf "${SDK_ROOT}"
mkdir -p "${SDK_ROOT}/bin" "${SDK_ROOT}/include" "${SDK_ROOT}/lib" "${SDK_ROOT}/cmake" "${SDK_ROOT}/licenses"

cp -R "${INSTALL_PREFIX}/include/." "${SDK_ROOT}/include/"
cp -R "${INSTALL_PREFIX}/lib/." "${SDK_ROOT}/lib/"

if [[ "${SDK_PLATFORM}" == "windows" ]]; then
  cp -p "${INSTALL_PREFIX}/bin/ffmpeg.exe" "${SDK_ROOT}/bin/ffmpeg.exe"
  cp -p "${INSTALL_PREFIX}/bin/ffprobe.exe" "${SDK_ROOT}/bin/ffprobe.exe"
  find "${INSTALL_PREFIX}/bin" -maxdepth 1 -type f -name "*.dll" \
    -exec cp -p {} "${SDK_ROOT}/bin/" \;
else
  cp -p "${INSTALL_PREFIX}/bin/ffmpeg" "${SDK_ROOT}/bin/ffmpeg"
  cp -p "${INSTALL_PREFIX}/bin/ffprobe" "${SDK_ROOT}/bin/ffprobe"
  chmod 755 "${SDK_ROOT}/bin/ffmpeg" "${SDK_ROOT}/bin/ffprobe" >/dev/null 2>&1 || true

  find "${INSTALL_PREFIX}/lib" -maxdepth 1 \( -type f -o -type l \) -name "*.dylib" \
    -exec cp -Pp {} "${SDK_ROOT}/bin/" \;
fi

rewrite_macos_runtime_paths() {
  local binary="$1"
  local dependency
  local dependency_path
  local dependency_name

  while IFS= read -r dependency; do
    dependency_path="$(awk '{print $1}' <<<"${dependency}")"
    if [[ "${dependency_path}" == "${INSTALL_PREFIX}/lib/"* ]]; then
      dependency_name="$(basename "${dependency_path}")"
      install_name_tool \
        -change "${dependency_path}" "@loader_path/${dependency_name}" \
        "${binary}"
    elif [[ "${dependency_path}" == "${VCPKG_DEPENDENCY_ROOT}/lib/"* ||
            "${dependency_path}" == @rpath/* ]]; then
      dependency_name="$(basename "${dependency_path}")"
      if [[ ! -f "${SDK_ROOT}/bin/${dependency_name}" ]]; then
        stage_macos_external_dependency "${VCPKG_DEPENDENCY_ROOT}/lib/${dependency_name}"
      fi
      install_name_tool \
        -change "${dependency_path}" "@loader_path/${dependency_name}" \
        "${binary}"
    elif [[ "${dependency_path}" == /System/Library/* ||
            "${dependency_path}" == /usr/lib/* ||
            "${dependency_path}" == @loader_path/* ]]; then
      continue
    else
      echo "Unexpected macOS runtime dependency in ${binary}: ${dependency_path}" >&2
      exit 1
    fi
  done < <(otool -L "${binary}" | tail -n +2)
}

ad_hoc_sign_macos_runtime_files() {
  local runtime_file

  command -v codesign >/dev/null 2>&1 || {
    echo "codesign is required to seal macOS SDK runtime files" >&2
    exit 2
  }

  while IFS= read -r runtime_file; do
    codesign --force --sign - "${runtime_file}" >/dev/null
  done < <(find "${SDK_ROOT}/bin" "${SDK_ROOT}/lib" -maxdepth 1 -type f \( -name "ffmpeg" -o -name "ffprobe" -o -name "*.dylib" \))
}

stage_macos_external_dependency() {
  local dependency_path="$1"
  local dependency_name
  local staged_path

  [[ -f "${dependency_path}" ]] || {
    echo "Missing vcpkg runtime dylib: ${dependency_path}" >&2
    exit 1
  }

  dependency_name="$(basename "${dependency_path}")"
  staged_path="${SDK_ROOT}/bin/${dependency_name}"
  if [[ ! -f "${staged_path}" ]]; then
    cp -p "${dependency_path}" "${staged_path}"
    chmod 755 "${staged_path}" >/dev/null 2>&1 || true
    install_name_tool -id "@loader_path/${dependency_name}" "${staged_path}"
  fi

}

if [[ "${SDK_PLATFORM}" == "macos" ]]; then
  while IFS= read -r dylib; do
    dylib_name="$(basename "${dylib}")"
    install_name_tool -id "@loader_path/${dylib_name}" "${dylib}"
  done < <(find "${SDK_ROOT}/bin" "${SDK_ROOT}/lib" -maxdepth 1 -type f -name "*.dylib")

  rewrite_macos_runtime_paths "${SDK_ROOT}/bin/ffmpeg"
  rewrite_macos_runtime_paths "${SDK_ROOT}/bin/ffprobe"

  processed_paths=$'\n'
  while true; do
    pending=0
    while IFS= read -r binary; do
      [[ "${processed_paths}" == *$'\n'"${binary}"$'\n'* ]] && continue
      rewrite_macos_runtime_paths "${binary}"
      processed_paths+="${binary}"$'\n'
      pending=1
    done < <(find "${SDK_ROOT}/bin" "${SDK_ROOT}/lib" -maxdepth 1 -type f -name "*.dylib")
    [[ "${pending}" -eq 1 ]] || break
  done

  # The CMake link directory and the executable directory must each resolve
  # @loader_path dependencies without referring back to the build machine.
  for binary in "${SDK_ROOT}/bin/"*.dylib; do
    [[ -f "${binary}" ]] || continue
    if [[ ! -e "${SDK_ROOT}/lib/$(basename "${binary}")" ]]; then
      cp -p "${binary}" "${SDK_ROOT}/lib/"
    fi
  done

  ad_hoc_sign_macos_runtime_files
fi

cp -p "${SOURCE_DIR}/LICENSE.md" "${SDK_ROOT}/licenses/LICENSE.ffmpeg.txt"
if [[ -d "${INSTALL_PREFIX}/licenses" ]]; then
  cp -R "${INSTALL_PREFIX}/licenses/." "${SDK_ROOT}/licenses/"
fi
for package_dir in "${VCPKG_DEPENDENCY_ROOT}"/share/*; do
  [[ -d "${package_dir}" ]] || continue
  [[ -s "${package_dir}/copyright" ]] || continue
  package_name="$(basename "${package_dir}")"
  mkdir -p "${SDK_ROOT}/licenses/${package_name}"
  cp -p "${package_dir}/copyright" "${SDK_ROOT}/licenses/${package_name}/LICENSE"
done
for license_file in COPYING.GPLv2 COPYING.GPLv3 COPYING.LGPLv2.1 COPYING.LGPLv3; do
  if [[ -f "${SOURCE_DIR}/${license_file}" ]]; then
    cp -p "${SOURCE_DIR}/${license_file}" "${SDK_ROOT}/licenses/${license_file}"
  fi
done

cp "${ROOT_DIR}/cmake-package/FFmpegConfig.cmake.in" "${SDK_ROOT}/cmake/FFmpegConfig.cmake"
if [[ "${SDK_PLATFORM}" == "windows" ]]; then
  executable_suffix=".exe"
  library_prefix=""
  library_suffix=".lib"
else
  executable_suffix=""
  library_prefix="lib"
  library_suffix=".dylib"
fi

sed \
  -e "s|@FFMPEG_EXECUTABLE_SUFFIX@|${executable_suffix}|g" \
  "${ROOT_DIR}/cmake-package/FFmpegRuntime.cmake.in" \
  > "${SDK_ROOT}/cmake/FFmpegRuntime.cmake"
sed \
  -e "s|@FFMPEG_SDK_COMPONENTS@|avcodec avformat avutil swscale swresample avdevice avfilter|g" \
  -e "s|@FFMPEG_LIBRARY_PREFIX@|${library_prefix}|g" \
  -e "s|@FFMPEG_LIBRARY_SUFFIX@|${library_suffix}|g" \
  "${ROOT_DIR}/cmake-package/FFmpegTargets.cmake.in" \
  > "${SDK_ROOT}/cmake/FFmpegTargets.cmake"
