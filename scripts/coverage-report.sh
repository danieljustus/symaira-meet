#!/bin/bash
set -euo pipefail

# Export an lcov coverage report from SwiftPM's code-coverage output.
#
# Usage: scripts/coverage-report.sh [codecov-dir] [output.lcov]
#
# Expects `swift test --enable-code-coverage` to have run already. Requires
# full Xcode (llvm-profdata / llvm-cov via xcrun); Command Line Tools do not
# include XCTest, so the coverage run itself cannot be produced there.

REPO_ROOT="$(cd "$(dirname "$0")/.." && pwd)"
cd "$REPO_ROOT"

CODECOV_DIR="${1:-.build/debug/codecov}"
OUT="${2:-coverage.lcov}"

if [ ! -d "$CODECOV_DIR" ]; then
  echo "error: coverage directory '$CODECOV_DIR' not found." >&2
  echo "       Run 'swift test --enable-code-coverage' (or 'make coverage') first." >&2
  exit 1
fi

# Locate every SwiftPM test-bundle binary. Swift 6 emits one bundle per test
# target rather than a single *PackageTests bundle, so all of them must be
# passed to llvm-cov to retain coverage across the package.
TEST_BINS=()
while IFS= read -r -d '' test_bin; do
  TEST_BINS+=("$test_bin")
done < <(find .build -type f -path "*.xctest/Contents/MacOS/*" -print0)

if [ "${#TEST_BINS[@]}" -eq 0 ]; then
  echo "error: no .xctest bundle binaries found under .build." >&2
  echo "       Run 'swift test --enable-code-coverage' (or 'make coverage') first." >&2
  exit 1
fi

# SwiftPM writes raw profiles (*.profraw) into the codecov dir; newer
# toolchains may additionally pre-merge default.profdata. Merge the raw
# profiles when present so both layouts work.
PROFDATA="$CODECOV_DIR/coverage.profdata"
if ls "$CODECOV_DIR"/*.profraw >/dev/null 2>&1; then
  xcrun llvm-profdata merge "$CODECOV_DIR"/*.profraw -o "$PROFDATA"
elif [ -f "$CODECOV_DIR/default.profdata" ]; then
  PROFDATA="$CODECOV_DIR/default.profdata"
else
  echo "error: no .profraw or default.profdata files in '$CODECOV_DIR'." >&2
  exit 1
fi

LLVM_COV_ARGS=("${TEST_BINS[0]}")
for test_bin in "${TEST_BINS[@]:1}"; do
  LLVM_COV_ARGS+=( -object "$test_bin" )
done

xcrun llvm-cov export -format=lcov -instr-profile "$PROFDATA" "${LLVM_COV_ARGS[@]}" > "$OUT"
echo "wrote $OUT"
