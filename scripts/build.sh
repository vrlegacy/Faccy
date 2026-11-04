#!/usr/bin/env bash
set -euo pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
CONFIG="release"
OPEN_AFTER_BUILD=0

for arg in "$@"; do
    case "$arg" in
        debug|release)
            CONFIG="$arg"
            ;;
        --open)
            OPEN_AFTER_BUILD=1
            ;;
        *)
            echo "Usage: scripts/build.sh [debug|release] [--open]" >&2
            exit 2
            ;;
    esac
done

echo "Building Faccy ($CONFIG)…"
swift build -c "$CONFIG" --package-path "$ROOT"

BIN_DIR="$(swift build -c "$CONFIG" --package-path "$ROOT" --show-bin-path)"
BIN="$BIN_DIR/Faccy"
APP="$ROOT/dist/Faccy.app"

if [[ ! -x "$BIN" ]]; then
    echo "Build finished but no executable was found at $BIN" >&2
    exit 1
fi

rm -rf "$APP"
mkdir -p "$APP/Contents/MacOS" "$APP/Contents/Resources"

cp "$BIN" "$APP/Contents/MacOS/Faccy"
cp "$ROOT/Support/Info.plist" "$APP/Contents/Info.plist"
printf 'APPL????' > "$APP/Contents/PkgInfo"

plutil -lint "$APP/Contents/Info.plist" >/dev/null
codesign --force --sign - "$APP" >/dev/null

echo "Built: $APP"
echo "Run:   open \"$APP\""

if [[ "$OPEN_AFTER_BUILD" -eq 1 ]]; then
    open "$APP"
fi
