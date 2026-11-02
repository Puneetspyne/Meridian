# Handoff: notch body, card, snapshot renderer (UI-A)

## What was built
- `Bodies/NotchPanelController.swift`: non-activating `NotchPanel` (borderless, level mainMenu+3, all Spaces, never key), `NotchHostingView` (hitTest nil outside the shape, accepts first mouse), the interaction state machine.
- `Bodies/Notch/`: `NotchGeometry` (notch rect from `auxiliaryTop*Area`, fallback 200 pt), `NotchLayout` (closed/hover/open sizes), `NotchShape` (animatable continuous bottom radius + concave top flares), `NotchState`, `NotchView` (wings, hairline, hover growth, drawer, matched ring).
- `Bodies/BodyCoordinator.swift`: automatic/notch/corner/both, reacts to `settings.body` (Observation) and screen changes; `openCard/closeCard/toggleCard`; observes `Notification.Name("meridian.toggleCard")`. Forcing `.notch` on a Mac with no notch falls back to the corner body.
- `Card/`: `CardView(model:presentation:ringNamespace:openSettings:)`, `CardTiles`, `CardStrips` (Time, Agents).
- `Components/`: `Ring`, `Sparkline`, `MetricTile`, `Chip`, `CoreBars`, `HeroView`, `SignalValue`, `Num`, environment keys, `meridianSurface`.
- `Snapshot/SnapshotRenderer.swift`; `Design/Tokens.swift` additions (`Design.NotchMetrics`, `Motion.draw`, a few sizes).

## Run and verify
```
swift build --scratch-path .build/ui-a
swift run --scratch-path .build/ui-a Meridian --snapshot docs/snapshots     # headless, prints every path
swift run --scratch-path .build/ui-a Meridian --mock --scenario hot
```
Snapshots in `docs/snapshots/`: `notch-closed-<s>.png`, `notch-open-<s>.png`, `card-<s>.png` for calm, busy, hot, lowBattery, diskFull, charging, meeting, agent, empty (every section nil); plus `notch-closed-gallery.png`, `notch-hover-calm.png`, `components.png`.
Verified on this Mac (M2 Air, notch): the closed shape with wings (live, hot scenario: "102 degrees / Running hot", red hairline), hover then dwell-open, live data in the open card, tile glass over real windows. CPU with `--mock --scenario calm`, closed, debug build: about 1.3 percent; open card showed the same in one sample. I could not re-measure the open card or live-data CPU at the end: UI-B's instance set the shared UserDefaults body mode to Corner, which hid my notch.

## Interaction (exact)
- Panel is 540 x up to 800 pt but mouse-transparent (`ignoresMouseEvents`) until the pointer is over the visible shape (global + local mouse-moved monitors), so the menu bar beside the wings stays clickable.
- Pointer enters closed shape: grows (+6 pt height, +12 pt per wing, `Motion.hover`). After `notchHoverDelay` it opens if `notchHoverToOpen`. Leaving cancels both at once. Click on the closed shape opens immediately.
- Open: closes 400 ms after the pointer leaves, on Esc, on a click outside, or after `cardAutoCloseSeconds` without pointer movement over the card. After Esc/auto-close with the pointer still on the notch, hover does not reopen until it leaves and returns.
- Gear: closes the card, then calls `openSettings`.
- Reduce Motion: `settings.reduceMotionOverride ?? system`; springs become 150 ms ease crossfades, ring and sparkline animation stop.

## Layout choices
- Open notch card: the 38 pt band beside the hardware notch carries the chip (left) and gear (right); uptime and "Updated N s ago" sit at the bottom. Corner/menu-bar presentations use one footer row.
- Strips read signals by kind (`TimeProvider`/`AgentsProvider` had no public API yet): Time = meeting/countdown/timer/stopwatch rows, `.clock` signals as world clocks, `.weather`. Agents strip shows `.agent` signals (dot = signal tint, trailing `value` as elapsed, `actionURL` opens on click). Strips are hidden when empty.
- Tiles that are odd one out in a row span both columns. Missing data shows an em dash.

## Known gaps
- Esc only works while Meridian is the active app (panel never takes focus; a global key monitor needs Input Monitoring permission). Click outside, pointer exit and auto-close cover the rest.
- Quick-add for timers (plus button, option-command-T) is not built: it belongs with the Time module.
- Cards taller than the screen scroll; not exercised.
- Matched-geometry flight of the wing ring into the hero ring was not inspected mid-animation (cannot capture frames); open/close end states verified.
- Snapshots use a flat fill instead of glass (ImageRenderer has no backdrop), and a 17 s sample step so mock waves do not alias into zigzags. Not yet done: corner body, menu bar item and settings snapshots (other workstream).
- Fan values print without thousands separators (`Format.rpm`).
- Several agents share `~/Library/Preferences` settings and `pkill -x Meridian`, so concurrent runs interfere.

## Wished-for fields
- `AppModel.cardIsOpen` or a shared open-state so the status item can show state; `Settings.notchOpenOnClickOnly`; a public elapsed `Date` on agent signals (now only the `value` string).
- `CardView` falls back to posting `Notification.Name("meridian.openSettings")` when no `openSettings` closure is given; the app delegate can observe it.

## Round 2 (coordinator follow-ups)

1. **Stray ring.** Two causes, neither the matched geometry. (a) `isFloatingPanel = true` reset the panel level to `.floating` (CGWindow layer 3, below the menu bar server); the level is now set after it and reads 27. (b) The ring was Meridian's own menu bar item: macOS draws status items above any window, and the right wing sat on top of the first one. `MenuBarItems.wingCap` reads the status item windows (layer 25, bounds need no permission) and clamps both wings to the free bar between the notch and the first item (minimum 84 pt, checked every 3 s while closed; edge padding tightens when clamped). On this Mac the cap is 84 and the first item is at x=1046. See `notch-closed-narrow-*.png`. The matched ring stays, one view per state.
2. **Idle CPU (closed), debug build, `--mock --scenario calm`, pointer away, `/usr/bin/top` and `ps cputime`:** before about 7 to 10 percent (spikes to 30); after about 0.6 percent over 45 s. `--mock --scenario meeting` the same. No flags (live) about 1.7 percent, debug. The cost was animation: a spring on the wing ring and rolling digits on the wing value, once a second, kept the notch rendering at frame rate (software-drawn layer). Fixes: the wing ring and value no longer animate, `WingModel` (Equatable, progress rounded to 0.02) behind `.equatable()` in `ClosedHost`, `NotchView` never reads `model.top`, the card is not in the tree while closed. Only timers while closed: the clock (once a minute), a live countdown (1 s, only if the top signal is one), the 3 s wing-cap check. Open card, debug: about 40 percent while open (not optimised; release not measured).
3. Processes tile handles 0 to 3 rows (dash when empty).
4. **Time strip** uses `TimeProvider`: header with plus, quick add with live parse preview ("Timer · Focus · 25 min"), meeting row with Join, timers (pause/resume, dismiss when finished, context menu +5 min / reset / remove), countdowns (remove), stopwatch (lap, stop/start, reset), `worldClocks`. Global hotkey Option-Command-T (Carbon, `Bodies/HotKey.swift`) opens the card with the field focused (`CardCommands.shared.quickAddPending`); the panel becomes key only while quick add is open, without activating the app. `Bodies/TimerAlerts.swift` plays Glass and posts one notification per fired timer or countdown signal id (notifications only when running as an .app bundle). Verified live: hotkey opens the card with the field open; the key window is acquired. Not verified: typed text and Return (the automation tool's click took focus away); the parse and add path is the same one the snapshot shows (`card-quickadd.png`). The corner body needs the same `meridianKeyboard` environment hook to let its panel type.
5. **Agents strip** uses `AgentsProvider.sessions` (dot by state, elapsed, dismiss x on done, click opens `actionURL`), and the quiet line "Turn on in Settings → Agents" when inactive. Only shown when the Agents tile is visible. Not run against live sessions.
6. **Weather tile** from `WeatherProvider` (condition symbol, temperature, feels-like, next rain hour, high/low), or "Turn on in Settings → Modules". Not seen live (weather disabled here); snapshot shows the signal-only path.
7. Footer chip and uptime come only from `snapshot.system.chipName` and `snapshot.cpu.uptime`.
8. `meridian.openCard` is observed: opens on the notch if present, else the corner, never toggles closed.

## Round 3: wide pebble, glass, polish, performance budget

**Wide layout** (`Settings.cardLayout == .wide`): `Card/WideCard.swift`, `Card/CompactTiles.swift`. A low bar, 880 pt wide (clamped to screen minus 24 pt, flares included), about 168 pt tall on the notch (38 pt band, 112 pt row, padding; +30 pt when agent pills show). One row: compact hero (44 pt ring), compact tiles (CPU with core bars, Memory, Temperature, Network, Disk, Battery, GPU, Power; as many as fit at 112 pt minimum, the rest are hidden, never squeezed; 4 at 880), time column (clock, next meeting with Join or running timer with pause, one world clock), agent pills under the tiles when there are sessions. No scrolling in wide mode. Corner and menu bar presentations use the same layouts with a 34 pt header instead of the notch band; the view has a fixed frame so `fittingSize` is honest (`WideMetrics`, `CardView.width(layout:screenWidth:isNotch:)`).
**Toggle:** `LayoutToggle` (rectangle.portrait / rectangle) in the notch band, the corner footer or wide header. It writes `model.settings.cardLayout` inside `Motion.open`: the shape frame morphs (`NotchLayout` carries layout and screen width), the old content leaves at once and the new content fades in 90 ms later. Verified live: tall to wide on this Mac.
**Glass:** `cardMaterial == .glass` (default): the black band around the hardware notch stays matte; below it `CardGlassBackground` (Liquid Glass on macOS 26, ultra-thin material before) with hairline, a 22 pt fade out of the band, and a black scrim of 10 percent (dark system appearance) or 14 percent (light), chosen from `NSApp.effectiveAppearance` when the card opens. The panel itself is forced to dark aqua so white text never lands on light glass. Tiles on glass are a flat 7.5 percent white fill (no blur behind blur); on `.black` they are glass over a dark underlay as before. Corner presentation: glass card, or solid black with a hairline. Not verified on a light wallpaper.
**Polish:** ring stroke gradient (tint to tint at 70 percent) with round caps; 1 pt top highlight at 6 percent on every tile; hover lifts a tile 1 pt with a stronger hairline (only exists while the card is open); card entrance staggers sections by 20 ms; sparklines trim-draw on first appearance only.
**Not done from the brief: rolling digits.** `contentTransition(.numericText())` is not used. Measured in a release build with the card open and a smooth mock signal: plain text 2 percent CPU; with a numericText on the hero value 13 percent; an `onChange` that writes state, or an id-swap push transition, 6 to 12 percent. SwiftUI repaints this panel in software, and any effect layer on a value that changes every second is redrawn each tick. For the same reason the ring only animates for jumps of 15 points or more, the core bars do not animate, and the matched-geometry effect on the hero ring is dropped 0.9 s after open. `Num(animates:)` is kept as a no-op for when that cost goes away. "Updated N s ago" is now an event-driven label ("Live", then 3, 10, 30, 60 s...) instead of a once-a-second TimelineView, which made the card repaint twice a second.

**CPU (release build, `swift build -c release --scratch-path .build/ui-a-rel`, `--keep-card-open` flag opens the card 2 s after launch and never auto-closes; 20 s of `ps` CPU time after 8 s settle; M2 Air).** I did not use `scripts/build-app.sh`: it writes `build/Meridian.app`, which another instance was running from.

| state | mock calm | live |
| --- | --- | --- |
| closed | 0.6 % | 1.6 % (sampler cost) |
| open, tall, glass | 2.4 % | 3.0 to 5.1 % (noisy) |
| open, tall, black | 2.4 to 3.4 % | 3.1 to 4.9 % |
| open, wide, glass | 1.5 % | 2.3 to 8.0 % (one outlier) |
| open, wide, black | 2.3 % | 2.7 to 4.4 % |

Glass versus black: no difference beyond noise (under 0.5 percent). Live runs include the 1.6 percent the samplers cost with the card closed, so the card's own share is about 1.4 percent tall and 0.7 to 1 percent wide. Tall with live data can touch 3 to 5 percent in a noisy minute; the budget is met on the smooth mock and mostly met live. Biggest remaining cost is one software repaint of the whole card per sample; shrinking it needs fewer or cheaper sparklines.

**Snapshots:** `card-wide-*`, `notch-open-wide-*` (calm, hot, meeting, agent), `card-calm-glass`, `card-calm-black`, `notch-open-calm-glass/black`, `card-quickadd`, `notch-closed-narrow-*`. Glass is drawn as a flat gradient in snapshots (no backdrop in ImageRenderer).
**Shared state warning:** `--keep-card-open`, the hotkey (system-wide, first instance wins) and `~/Library/Preferences/Meridian` are shared by every running copy; measure with other copies stopped.
