#!/usr/bin/env bash
# Builds the app and wraps it in dist/Meridian-<version>.dmg, then writes dist/SHA256SUMS.
set -euo pipefail
cd "$(dirname "$0")/.."

./scripts/build-app.sh
APP="build/Meridian.app"
VERSION="$(/usr/libexec/PlistBuddy -c 'Print :CFBundleShortVersionString' "$APP/Contents/Info.plist")"
DMG="dist/Meridian-$VERSION.dmg"

mkdir -p dist
rm -f "$DMG"
stage="$(mktemp -d)"
trap 'rm -rf "$stage"' EXIT
cp -R "$APP" "$stage/Meridian.app"
ln -s /Applications "$stage/Applications"

hdiutil create -volname Meridian -srcfolder "$stage" -fs HFS+ -format UDZO -ov "$DMG" >/dev/null

( cd dist && shasum -a 256 "Meridian-$VERSION.dmg" > SHA256SUMS )
echo "dmg: $(pwd)/$DMG"
echo "sha256: $(cut -d' ' -f1 dist/SHA256SUMS)"
