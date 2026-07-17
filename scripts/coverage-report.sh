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

# Locate the package test bundle binary (name-agnostic across package renames).
TEST_BIN="$(find .build -type f -path "*PackageTests.xctest/Contents/MacOS/*PackageTests" | head -1)"
if [ -z "$TEST_BIN" ]; then
  echo "error: no *PackageTests.xctest binary found under .build." >&2
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

xcrun llvm-cov export -format=lcov -instr-profile "$PROFDATA" "$TEST_BIN" > "$OUT"
echo "wrote $OUT"
