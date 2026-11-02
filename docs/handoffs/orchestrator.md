# Orchestrator notes: state of Meridian at the end of the overnight build (2 Nov 2026)

Read this first. It says what is done, what was verified on this Mac, what is not, and the two things only
Puneet can do.

## Done and verified on this Mac (M2 MacBook Air, macOS 26.5.1, notch)

- `swift build` clean; `./scripts/test.sh` passes: **108 tests in 19 suites**.
- `./scripts/build-app.sh` produces `build/Meridian.app` (ad-hoc signed). It is running now, tall glass layout.
- Live telemetry: CPU (4E + 4P), memory, GPU, disks, network, battery (cycles, health, watts), 129 temperature
  and fan sensors through HID and SMC, IOReport power, top processes aggregated by app.
- Notch body: closed wings (ring + value left, clock or top signal right), hover grows, dwell opens, click
  opens, Esc / click outside / pointer leave / idle closes. Wings clamp to the free menu bar next to the
  first status item.
- Card, two layouts, switchable from the band toggle, Settings → General, or the menu bar "Card layout"
  submenu. Glass (default) or matte black.
- Corner body, settings window (General, Tiles, Thresholds, Modules, Agents, About), menu bar item, time
  module (quick add, timers, countdowns, stopwatch, meeting with Join, world clocks), agents module
  (Claude Code hooks), weather module (Open-Meteo).
- CPU budget, release build, `/usr/bin/top`, 20 s windows, live data:

  | state | CPU | RSS |
  | --- | --- | --- |
  | closed | 1.1 to 1.9 % | 16 MB |
  | open, tall, glass | 2.0 to 2.4 % | 36 MB |
  | open, wide, glass | 2.1 to 2.5 % | 28 MB |

## Verified only by the agent that built it, not re-checked by me

- The on-screen look of the wide bar and the glass material. UI-A switched tall to wide on this Mac and
  looked at it with the desktop screenshot tool; that tool stopped answering (timed out on every call) before
  I could repeat it, and `screencapture` has no Screen Recording permission from this shell. The layout
  itself is checked through the renderer PNGs in `docs/snapshots/` and `docs/images/`.
- Glass over a light wallpaper (scrim is 14 % in light appearance, 10 % in dark; nobody has looked at it
  on a bright desktop).
- Typing into quick add and pressing Return in the live panel (the parse path is unit tested and snapshotted).
- Agents end to end with a real Claude Code `Stop` hook: the Claude Code CLI OAuth on this Mac had expired.
- Calendar access and timer notifications: both need the `.app` bundle, and nobody has granted the prompts yet.
- Corner body with the wide layout: sizes come from the same `CardView`, so it should fit, but it has not
  been opened in wide mode from a corner.

## Only Puneet can do these

1. **CI.** `.github/workflows/ci.yml` is committed on local branch `ci` (commit 261f303). Pushing it needs
   the `workflow` OAuth scope the `gh` token lacks:
   ```bash
   gh auth refresh -h github.com -s workflow
   ```
   ```bash
   git merge ci && git push
   ```
2. **Permissions on first run.** Open `build/Meridian.app` (or `./scripts/build-app.sh --install`), then:
   Settings → Modules to grant Calendar if you want meetings; the first timer asks for Notifications.
   Weather needs a location picked in Settings → Modules (no permission, no key).
3. **Optional:** a Developer ID for notarised DMGs. Everything is ad-hoc signed today; `scripts/package-dmg.sh`
   makes a DMG that needs "Open Anyway" once.

## Design decisions that are not obvious from the code

- Rolling digits, per-sample ring animation and the once-a-second "Updated N s ago" label were built and
  removed: SwiftUI paints these panels in software, and anything that re-renders on every sample cost 6 to
  13 % CPU in release. `Num(animates:)` is kept as a no-op so the roll can come back if that changes.
- Tiles on a glass card are a flat fill: a second blur over the card's glass looked muddy and cost more.
- The notch panel is forced to the dark appearance so white text never lands on light glass.
- `--keep-card-open` (debug flag) opens the card 2 s after launch and never auto-closes; use it to measure.
  The hotkey, that flag and the UserDefaults are shared by every running copy, so measure with one copy.
- `--mock --scenario <calm|busy|hot|lowBattery|diskFull|charging>` drives the UI on fake data;
  `--snapshot <dir>` renders every surface to PNG headlessly.

## Where things are

- Per-workstream handoffs: `docs/handoffs/{infra,sensors,time,agents,weather,ui-notch-card,ui-corner-settings}.md`.
- Design language: `docs/DESIGN.md`. Module ownership: `docs/ARCHITECTURE.md`. Sensor keys: `docs/SENSORS.md`.
- Renders: `docs/snapshots/` (gitignored, regenerate with `swift run Meridian --snapshot docs/snapshots`);
  the ones the README uses are copied to `docs/images/` at 1200 px.

## Suggested next round

- Light-wallpaper pass on the glass scrim, ideally by sampling the wallpaper once on open.
- Wide layout on the corner body; a third layout for Macs without a notch (a floating pill under the menu bar).
- Fewer sparkline repaints while open (the remaining cost) by drawing only tiles whose value changed.
- Fan control is deliberately absent; it needs a privileged helper and is a different risk class.
- Release pipeline: once CI is pushed, tag `v0.1.0` and let the workflow attach the DMG.
