# Contributing to Meridian

Thanks for helping. Meridian is a macOS 15+ menu bar and notch system monitor, MIT licensed.

## Build with the Command Line Tools only

You do not need Xcode.app. Install the tools with `xcode-select --install`, then:

```
swift build                       # debug build
swift build -c release            # release build
swift run Meridian --mock --scenario hot   # run the app on fake data
swift run meridianctl snapshot    # one live telemetry snapshot as JSON
./scripts/build-app.sh            # assemble build/Meridian.app (ad-hoc signed)
./scripts/build-app.sh --install  # also install to ~/Applications and relaunch
./scripts/package-dmg.sh          # dist/Meridian-<version>.dmg and SHA256SUMS
```

Set `SCRATCH=.build/mine` to keep `build-app.sh` from colliding with another build in the same checkout.

## Tests

```
./scripts/test.sh
```

The script works around the Command Line Tools shipping Swift Testing outside the default search path. It
also works when Xcode is installed. Kit and parser tests are pure; sensor tests assert shape, not values.

## Snapshot renderer

The UI is verified by rendering every surface to PNG:

```
swift run Meridian --snapshot snapshots
```

Look at the images before you open a PR that changes UI, and attach the relevant ones.

## Module ownership

Each module has one owner at a time. See [docs/ARCHITECTURE.md](docs/ARCHITECTURE.md). Do not edit another
module's files; if you need a contract change, add to `MeridianKit` additively and say so in the PR.

## Design rules

Follow [docs/DESIGN.md](docs/DESIGN.md).

## Commit style

Short imperative subject, scoped by area when useful: `sensors: decode flt SMC keys`. One logical change
per commit. Explain why in the body when it is not obvious.

## Contribute a chip's sensor mapping

Temperature, fan and power keys differ per chip. To help your Mac:

1. Run `meridianctl contribute` (inside the app bundle: `Meridian.app/Contents/MacOS/meridianctl`).
2. Open a "Sensor mapping" issue and paste the JSON.

## License note

Meridian is MIT. Do not copy code from GPL projects such as boring.notch or Atoll, not even small pieces.
MIT-licensed sources such as Stats or macmon may be adapted with attribution in
[THIRD_PARTY_NOTICES.md](THIRD_PARTY_NOTICES.md), which currently lists none (adapted ideas only).
