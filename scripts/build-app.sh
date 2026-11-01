#!/usr/bin/env bash
# Builds build/Meridian.app with the Command Line Tools only (no Xcode).
#   ./scripts/build-app.sh             build and ad-hoc sign build/Meridian.app
#   ./scripts/build-app.sh --install   also copy to ~/Applications and relaunch
# Env: SCRATCH  SwiftPM scratch path (default .build/release-app), keeps builds from colliding.
set -euo pipefail
cd "$(dirname "$0")/.."

SCRATCH="${SCRATCH:-.build/release-app}"
INSTALL=0
for a in "$@"; do
  case "$a" in
    --install) INSTALL=1 ;;
    -h|--help) sed -n '2,5p' "$0"; exit 0 ;;
    *) echo "unknown argument: $a" >&2; exit 2 ;;
  esac
done

echo "==> swift build -c release (scratch: $SCRATCH)"
swift build -c release --scratch-path "$SCRATCH"
BIN="$(swift build -c release --scratch-path "$SCRATCH" --show-bin-path)"
for exe in Meridian meridianctl; do
  [[ -x "$BIN/$exe" ]] || { echo "error: $BIN/$exe was not built" >&2; exit 1; }
done

APP="build/Meridian.app"
rm -rf "$APP"
mkdir -p "$APP/Contents/MacOS" "$APP/Contents/Resources"
cp "$BIN/Meridian" "$APP/Contents/MacOS/Meridian"
cp "$BIN/meridianctl" "$APP/Contents/MacOS/meridianctl"
cp Resources/Info.plist "$APP/Contents/Info.plist"
printf 'APPL????' > "$APP/Contents/PkgInfo"

# Icon: generated from the Core Graphics script when Resources/AppIcon.icns is missing.
ICNS="Resources/AppIcon.icns"
if [[ ! -f "$ICNS" ]]; then
  echo "==> generating AppIcon.icns"
  tmp="$(mktemp -d)"
  trap 'rm -rf "$tmp"' EXIT
  swift scripts/make-icon.swift "$tmp/icon.png" >/dev/null
  set_dir="$tmp/AppIcon.iconset"
  mkdir -p "$set_dir"
  for sz in 16 32 128 256 512; do
    sips -z $sz $sz "$tmp/icon.png" --out "$set_dir/icon_${sz}x${sz}.png" >/dev/null
    sips -z $((sz*2)) $((sz*2)) "$tmp/icon.png" --out "$set_dir/icon_${sz}x${sz}@2x.png" >/dev/null
  done
  iconutil -c icns "$set_dir" -o "$ICNS"
fi
cp "$ICNS" "$APP/Contents/Resources/AppIcon.icns"

# Ad-hoc signature: no developer account needed. Users trust it once via right-click Open.
codesign --force --deep --sign - "$APP"
codesign --verify --deep --strict "$APP"

echo "built: $(pwd)/$APP"

if [[ "$INSTALL" == 1 ]]; then
  mkdir -p "$HOME/Applications"
  pkill -x Meridian 2>/dev/null || true
  sleep 1
  rm -rf "$HOME/Applications/Meridian.app"
  cp -R "$APP" "$HOME/Applications/Meridian.app"
  echo "installed: $HOME/Applications/Meridian.app"
  open "$HOME/Applications/Meridian.app"
fi
