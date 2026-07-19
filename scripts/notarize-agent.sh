#!/bin/bash
set -euo pipefail

REPO_ROOT="$(cd "$(dirname "$0")/.." && pwd)"
cd "$REPO_ROOT"

DIST_DIR="${1:?Usage: $0 <dist-dir>}"
DIST_DIR="$(cd "$DIST_DIR" && pwd)"

if [ "${SYMMEET_DRY_RUN:-0}" = "1" ]; then
  echo "==> Dry-run mode: skipping notarization."
  exit 0
fi

if [ -z "${APPLE_ID:-}" ] || [ -z "${APPLE_TEAM_ID:-}" ] || [ -z "${APPLE_APP_PASSWORD:-}" ]; then
  echo "==> APPLE_ID, APPLE_TEAM_ID, or APPLE_APP_PASSWORD not set: skipping notarization."
  exit 0
fi

DMG=$(find "$DIST_DIR" -maxdepth 1 -type f -name '*.dmg' -print -quit)
if [ -z "$DMG" ]; then
  echo "Error: No DMG found in ${DIST_DIR}" >&2
  exit 1
fi

APP=$(find "$DIST_DIR" -maxdepth 1 -type d -name '*.app' -print -quit)

echo "==> Submitting DMG for notarization..."
NOTARY_JSON=$(mktemp)
trap 'rm -f "$NOTARY_JSON"' EXIT
xcrun notarytool submit "$DMG" \
  --apple-id "$APPLE_ID" \
  --team-id "$APPLE_TEAM_ID" \
  --password "$APPLE_APP_PASSWORD" \
  --wait \
  --output-format json > "$NOTARY_JSON"

NOTARY_STATUS=$(python3 -c 'import json,sys; print(json.load(open(sys.argv[1]))["status"])' "$NOTARY_JSON")
if [ "$NOTARY_STATUS" != "Accepted" ]; then
  echo "Error: Apple notarization finished with status ${NOTARY_STATUS}" >&2
  exit 1
fi

if [ -n "$APP" ]; then
  echo "==> Stapling ${APP}..."
  xcrun stapler staple "$APP"

  echo "==> Rebuilding DMG with stapled app..."
  DMG_NAME=$(basename "$DMG")
  DMG_STAGE=$(mktemp -d)
  trap "rm -rf '$DMG_STAGE'" EXIT

  ln -s /Applications "$DMG_STAGE/Applications"
  cp -R "$APP" "$DMG_STAGE/"

  hdiutil create \
    -volname "SymMeetAgent" \
    -srcfolder "$DMG_STAGE" \
    -ov -format UDZO \
    "$DIST_DIR/$DMG_NAME" \
    2>/dev/null

  rm -rf "$DMG_STAGE"

  echo "==> Stapling DMG..."
  xcrun stapler staple "$DIST_DIR/$DMG_NAME"
fi

echo "==> Notarization complete."
