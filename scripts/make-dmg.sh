#!/usr/bin/env bash
# Packages dist/Faccy.app into dist/Faccy-<version>.dmg with an
# Applications shortcut, ready to drag-install or attach to a release.
set -euo pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
APP="$ROOT/dist/Faccy.app"

if [[ ! -d "$APP" ]]; then
    echo "No app at $APP — run scripts/build.sh first." >&2
    exit 1
fi

VERSION="$(/usr/libexec/PlistBuddy -c 'Print :CFBundleShortVersionString' "$APP/Contents/Info.plist")"
DMG="$ROOT/dist/Faccy-$VERSION.dmg"
STAGING="$(mktemp -d)"
trap 'rm -rf "$STAGING"' EXIT

ditto "$APP" "$STAGING/Faccy.app"
ln -s /Applications "$STAGING/Applications"

rm -f "$DMG"
hdiutil create \
    -volname "Faccy $VERSION" \
    -srcfolder "$STAGING" \
    -fs HFS+ \
    -format UDZO \
    -ov \
    "$DMG" >/dev/null

echo "$DMG"
