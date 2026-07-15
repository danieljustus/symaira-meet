#!/bin/bash
set -euo pipefail

DIST_DIR="${1:?Usage: $0 <dist-dir>}"
CHECKSUM_FILE="${DIST_DIR}/checksums.txt"

echo "Generating checksums for ${DIST_DIR}..."

> "${CHECKSUM_FILE}"

for file in "${DIST_DIR}"/*.tar.gz "${DIST_DIR}"/*.dmg; do
  [ -f "$file" ] || continue
  shasum -a 256 "$file" >> "${CHECKSUM_FILE}"
done

echo "Checksums written to ${CHECKSUM_FILE}"
cat "${CHECKSUM_FILE}"
