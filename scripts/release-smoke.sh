#!/bin/bash
set -euo pipefail

DIST_DIR="${1:?Usage: $0 <dist-dir>}"

echo "Running release smoke tests on ${DIST_DIR}..."

# Verify checksums
if [ -f "${DIST_DIR}/checksums.txt" ]; then
  echo "Verifying checksums..."
  (cd "${DIST_DIR}" && shasum -a 256 -c checksums.txt)
  echo "Checksums verified."
fi

# Check CLI archive exists
CLI_ARCHIVE=$(ls "${DIST_DIR}"/symmeet_*.tar.gz 2>/dev/null | head -1)
if [ -z "${CLI_ARCHIVE}" ]; then
  echo "Error: No CLI archive found in ${DIST_DIR}" >&2
  exit 1
fi

echo "Found CLI archive: ${CLI_ARCHIVE}"

# Extract and verify CLI
WORK_DIR=$(mktemp -d)
trap "rm -rf ${WORK_DIR}" EXIT

tar -xzf "${CLI_ARCHIVE}" -C "${WORK_DIR}"
CLI_BINARY="${WORK_DIR}/symmeet"

if [ ! -x "${CLI_BINARY}" ]; then
  echo "Error: CLI binary is not executable" >&2
  exit 1
fi

# Verify version
VERSION_OUTPUT=$("${CLI_BINARY}" version --json 2>/dev/null)
echo "CLI version: ${VERSION_OUTPUT}"

# Verify help
"${CLI_BINARY}" --help >/dev/null 2>&1

echo "All smoke tests passed."
