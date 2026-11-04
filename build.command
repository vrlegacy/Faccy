#!/usr/bin/env bash
# Double-click in Finder to build Faccy, install it to /Applications,
# make a DMG for GitHub Releases, and open the app.
set -euo pipefail

cd "$(dirname "$0")"
ROOT="$(pwd)"
LSREGISTER="/System/Library/Frameworks/CoreServices.framework/Frameworks/LaunchServices.framework/Support/lsregister"

finish() {
    local status=$?
    echo
    if [[ $status -eq 0 ]]; then
        echo "✅ Done. Faccy is installed in /Applications."
    else
        echo "❌ Something went wrong (exit $status). Scroll up for the error."
    fi
    echo "Press any key to close this window."
    read -r -n 1 -s || true
}
trap finish EXIT

echo "▶︎ 1/5  Building…"
./scripts/build.sh release

echo "▶︎ 2/5  Making DMG…"
DMG="$(./scripts/make-dmg.sh)"
echo "      $DMG"

echo "▶︎ 3/5  Quitting any running Faccy…"
pkill -x Faccy 2>/dev/null || true
for _ in {1..20}; do
    pgrep -x Faccy >/dev/null || break
    sleep 0.25
done

echo "▶︎ 4/5  Installing to /Applications…"
rm -rf /Applications/Faccy.app
ditto dist/Faccy.app /Applications/Faccy.app

# Keep exactly one copy: drop the build copy so Spotlight and Launch Services
# don't show two Faccy apps.
"$LSREGISTER" -u "$ROOT/dist/Faccy.app" >/dev/null 2>&1 || true
rm -rf dist/Faccy.app
"$LSREGISTER" -f /Applications/Faccy.app >/dev/null 2>&1 || true

echo "▶︎ 5/5  Opening Faccy…"
open /Applications/Faccy.app
