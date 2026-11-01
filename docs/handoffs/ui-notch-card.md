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
