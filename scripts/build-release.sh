#!/bin/bash
set -euo pipefail

VERSION="${1:?Usage: $0 <version>}"
ARCH="${2:-arm64}"
DIST_DIR="dist"

echo "Building release artifacts for v${VERSION} (${ARCH})..."

mkdir -p "${DIST_DIR}"

# Build the CLI in release mode
SYMMEET_VERSION="${VERSION}" swift build -c release --product symmeet 2>&1

echo "Build complete."
