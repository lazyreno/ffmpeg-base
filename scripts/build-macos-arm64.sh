#!/usr/bin/env bash
set -euo pipefail

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
SDK_ARCH=arm64 exec "${ROOT_DIR}/scripts/build-macos.sh" "$@"
