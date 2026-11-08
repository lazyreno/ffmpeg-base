#!/usr/bin/env bash
set -euo pipefail

if [[ "${1:-}" != "--vcpkg-root" || -z "${2:-}" || "$#" -ne 2 ]]; then
  echo "Usage: bootstrap-pinned-vcpkg-macos.sh --vcpkg-root <checkout>" >&2
  exit 2
fi

vcpkg_root="$2"
metadata="${vcpkg_root}/scripts/vcpkg-tool-metadata.txt"
[[ -f "${metadata}" ]] || { echo "Missing pinned vcpkg tool metadata: ${metadata}" >&2; exit 1; }
# The checked-out vcpkg commit specifies both the tool release and its exact bytes.
source "${metadata}"
asset_dir="${RUNNER_TEMP:-${TMPDIR:-/tmp}}/vcpkg-tool-${VCPKG_TOOL_RELEASE_TAG}"
mkdir -p "${asset_dir}"
gh release download "${VCPKG_TOOL_RELEASE_TAG}" \
  --repo microsoft/vcpkg-tool \
  --pattern vcpkg-macos \
  --clobber \
  -D "${asset_dir}"

asset="${asset_dir}/vcpkg-macos"
actual_sha="$(shasum -a 512 "${asset}" | awk '{print $1}')"
if [[ "${actual_sha}" != "${VCPKG_MACOS_SHA}" ]]; then
  echo "Pinned vcpkg-macos SHA512 mismatch: ${actual_sha}" >&2
  exit 1
fi
install -m 755 "${asset}" "${vcpkg_root}/vcpkg"
"${vcpkg_root}/vcpkg" version --disable-metrics
