#!/bin/bash
set -euo pipefail

VERSION="${1:?Usage: $0 <version>}"
ARCH="${2:-arm64}"
DIST_DIR="dist"
BINARY=".build/release/symmeet"
ARCHIVE_NAME="symmeet_v${VERSION}_darwin_${ARCH}.tar.gz"

echo "Packaging CLI v${VERSION} for ${ARCH}..."

if [ ! -f "${BINARY}" ]; then
  echo "Error: ${BINARY} not found. Run build-release.sh first." >&2
  exit 1
fi

mkdir -p "${DIST_DIR}"
tar -czf "${DIST_DIR}/${ARCHIVE_NAME}" -C .build/release symmeet

echo "Created ${DIST_DIR}/${ARCHIVE_NAME}"
