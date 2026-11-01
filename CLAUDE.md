# Meridian: conventions for agents and contributors

Read in this order: `docs/ARCHITECTURE.md` (modules, ownership, data flow), `docs/DESIGN.md` (every visual
and interaction rule), then the handoff for the area you touch in `docs/handoffs/`.

## What this is
A macOS 15+ app that shows the one thing that matters about your Mac in the notch or a screen corner:
system health (CPU, memory, temperatures, fans, power, disk, network, battery), time (timers, next meeting,
world clocks), coding-agent sessions and weather. Open source, MIT, no telemetry.

## Hard constraints
- Builds with the Xcode Command Line Tools alone: `swift build`. No Xcode project, no CocoaPods, no SwiftPM
  dependencies. Tests run with `./scripts/test.sh` (Swift Testing from the Command Line Tools).
- Swift 5 language mode (set in Package.swift), AppKit for windows and panels, SwiftUI for content.
- Every colour, radius, font and spring comes from `Sources/Meridian/Design/Tokens.swift`. No hardcoded values in views.
- Private APIs (SMC, IOHIDEventSystemClient, IOReport) are resolved with `dlsym` and fail soft to `nil`. Never crash on a missing symbol.
- `MeridianKit` has no AppKit. Modules (`MeridianTime`, `MeridianAgents`, `MeridianWeather`, `MeridianSensors`) have no AppKit either.
- Signals are the only vocabulary between modules and UI. Stable ids (`time.timer.<id>`, `agents.session.<id>`).
- No network calls except Open-Meteo when weather is on. No analytics, ever.
- Do not copy code from GPL projects (boring.notch, Atoll). MIT sources (Stats, macmon) may be adapted with attribution in `THIRD_PARTY_NOTICES.md`.

## Working in parallel
One owner per module at a time (see the ownership table in ARCHITECTURE.md). Build with your own scratch
path when others are building: `swift build --scratch-path .build/<you>`. Write a handoff in
`docs/handoffs/<area>.md` when you finish: what you built, what you verified (commands and output), gaps.

## Style
Small files, one type per file where sensible. Comments say why, not what. Sentence-case UI text, no emoji
in the UI, SF Symbols only. Numbers go through `Format`. Commit messages in the imperative.
