# Handoff: infra (packaging, CI, docs)

## Delivered
Resources/Info.plist, Resources/AppIcon.icns (generated, committed so builds are reproducible),
scripts/make-icon.swift, build-app.sh, package-dmg.sh, install.sh, .github/workflows/ci.yml,
ISSUE_TEMPLATE/{bug,sensor-mapping}.yml, PULL_REQUEST_TEMPLATE.md, CONTRIBUTING.md, SECURITY.md,
THIRD_PARTY_NOTICES.md, docs/PRIVACY.md.

## Verified (this Mac, CLT only, Swift 6.2.1)
- `plutil -lint Resources/Info.plist`: OK.
- `swift scripts/make-icon.swift out.png`: wrote 1024x1024 PNG; viewed it (squircle, near-black, glowing meridian
  ellipse, equator, teal dot); also viewed at 64 px, still legible.
- `SCRATCH=.build/infra ./scripts/build-app.sh`: built build/Meridian.app (MacOS/Meridian, MacOS/meridianctl,
  Resources/AppIcon.icns, Info.plist, PkgInfo), ad-hoc signed, `codesign --verify --deep --strict` passes.
- `open build/Meridian.app`: `pgrep -x Meridian` found the process; `pkill -x Meridian` stopped it.
- `SCRATCH=.build/infra ./scripts/package-dmg.sh`: dist/Meridian-0.1.0.dmg, sha256
  01259dc957fd6fbbecfa182aca153a5d2c48d512e8555c11d4343b5522e2dd4c (will change per build); `shasum -c SHA256SUMS`
  OK; `hdiutil attach` shows Meridian.app and an Applications symlink; signature verifies from the mounted image; detached.
- A first package attempt failed because another agent's in-progress MeridianWeather edit did not compile; the retry passed.

## Not verified
- ci.yml and install.sh network path (no release exists yet; `sh -n` syntax check only). The Xcode_16* glob in ci.yml
  assumes the macos-15 image keeps an Xcode 16.x; adjust if the image changes.
- `--install` flag (would replace ~/Applications/Meridian.app) was not run.
- `meridianctl contribute` is referenced by docs/templates; it did not exist yet in Sources when written.

## Release process
1. Bump CFBundleShortVersionString/CFBundleVersion in Resources/Info.plist, commit to main.
2. `git tag v0.1.0 && git push origin v0.1.0`.
3. CI job `package` runs scripts/package-dmg.sh and publishes the DMG plus SHA256SUMS via softprops/action-gh-release.
4. Users install with `curl -fsSL https://raw.githubusercontent.com/Puneetspyne/Meridian/main/scripts/install.sh | sh`
   (add `-s -- --trust` to strip quarantine). The app is ad-hoc signed, not notarized; first launch needs right-click Open
   unless `--trust` is used.
