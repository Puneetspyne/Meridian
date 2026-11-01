#!/bin/sh
# Meridian installer. Usage:
#   curl -fsSL https://raw.githubusercontent.com/Puneetspyne/Meridian/main/scripts/install.sh | sh
#   sh install.sh [--trust] [--user]
# --trust  remove the quarantine attribute (Meridian is ad-hoc signed, not notarized)
# --user   install to ~/Applications instead of /Applications
REPO="Puneetspyne/Meridian"
TRUST=0
DEST=/Applications

die() { echo "meridian-install: error: $*" >&2; exit 1; }
say() { echo "meridian-install: $*"; }

for a in "$@"; do
  case "$a" in
    --trust) TRUST=1 ;;
    --user) DEST="$HOME/Applications" ;;
    -h|--help) sed -n '2,6p' "$0"; exit 0 ;;
    *) die "unknown argument: $a" ;;
  esac
done

[ "$(uname -s)" = Darwin ] || die "Meridian only runs on macOS"
[ "$(uname -m)" = arm64 ] || say "warning: this build targets Apple silicon; you are on $(uname -m)"
major="$(sw_vers -productVersion | cut -d. -f1)"
[ "$major" -ge 15 ] || die "macOS 15 or newer is required (found $(sw_vers -productVersion))"

work="$(mktemp -d)" || die "cannot create a temporary directory"
mnt=""
cleanup() {
  [ -n "$mnt" ] && hdiutil detach "$mnt" -quiet >/dev/null 2>&1
  rm -rf "$work"
}
trap cleanup EXIT INT TERM

say "looking up the latest release of $REPO"
curl -fsSL "https://api.github.com/repos/$REPO/releases/latest" -o "$work/release.json" \
  || die "could not reach the GitHub API (is there a published release yet?)"

urls="$(grep '"browser_download_url"' "$work/release.json" | sed 's/.*"\(https[^"]*\)".*/\1/')"
dmg_url="$(echo "$urls" | grep '\.dmg$' | head -n 1)"
sums_url="$(echo "$urls" | grep 'SHA256SUMS$' | head -n 1)"
[ -n "$dmg_url" ] || die "latest release has no .dmg asset"
[ -n "$sums_url" ] || die "latest release has no SHA256SUMS asset; refusing to install unverified"
dmg_name="$(basename "$dmg_url")"

say "downloading $dmg_name"
curl -fL --progress-bar "$dmg_url" -o "$work/$dmg_name" || die "download failed"
curl -fsSL "$sums_url" -o "$work/SHA256SUMS" || die "could not download SHA256SUMS"

expected="$(grep " $dmg_name\$" "$work/SHA256SUMS" | awk '{print $1}')"
[ -n "$expected" ] || die "$dmg_name is not listed in SHA256SUMS"
actual="$(shasum -a 256 "$work/$dmg_name" | awk '{print $1}')"
[ "$expected" = "$actual" ] || die "checksum mismatch (expected $expected, got $actual); not installing"
say "checksum verified"

mnt="$work/mnt"
mkdir -p "$mnt"
hdiutil attach "$work/$dmg_name" -mountpoint "$mnt" -nobrowse -quiet || die "could not mount the DMG"
[ -d "$mnt/Meridian.app" ] || die "Meridian.app not found inside the DMG"

mkdir -p "$DEST" 2>/dev/null
if [ ! -w "$DEST" ]; then
  say "$DEST is not writable, falling back to ~/Applications"
  DEST="$HOME/Applications"
  mkdir -p "$DEST" || die "cannot create $DEST"
fi

pkill -x Meridian 2>/dev/null
rm -rf "$DEST/Meridian.app"
cp -R "$mnt/Meridian.app" "$DEST/Meridian.app" || die "copy to $DEST failed"
say "installed $DEST/Meridian.app"

if [ "$TRUST" = 1 ]; then
  xattr -dr com.apple.quarantine "$DEST/Meridian.app" 2>/dev/null
  say "quarantine attribute removed (--trust)"
else
  say "Meridian is ad-hoc signed, not notarized. If macOS blocks it, right-click the app and choose Open, or re-run with --trust."
fi

open "$DEST/Meridian.app" || die "installed, but could not open the app"
say "done"
