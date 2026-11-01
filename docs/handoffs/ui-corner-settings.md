# Handoff: corner body, Settings window, menu bar item (UI-B)

## What was built
- `Bodies/CornerPanelController.swift` (same interface: `init(model:openSettings:)`, `start(on:)`, `stop()`, `openCard()`, `closeCard()`).
- `Bodies/Corner/`: `CornerView` (+ `CornerState`), `CornerGeometry` (shapes, hit tests), `CornerPanels` (non-activating panels, mouse handling), `CornerCardController` (the card panel), `SpringAnimator` (spring for window frames).
- `Settings/`: `SettingsWindowController`, `SettingsView` (NavigationSplitView) and panes General, Tiles, Thresholds, Modules, Agents, About. Everything binds to `model.settings` through `@Bindable`.
- `App/StatusItemController.swift` (icon, cpu, temperature, topSignal, hidden; right-click menu), `App/LaunchAtLogin.swift` (SMAppService.mainApp with status readback and surfaced errors).
- `Design/Tokens+Corner.swift`: `Design.Corner.*` tokens (rest scale, tuck size, timings, card inset, settle spring).

## Behaviour
- Panel: borderless, non-activating, `.statusBar` level, joins all Spaces, clear, no shadow, never key. Laid out against `visibleFrame`; against `screen.frame` when a full-screen app covers the screen (window-list check, re-evaluated on Space, app activation and screen changes, debounced).
- Drawn: matte black quarter disk, 1 pt hairline (stronger with Increase Contrast), arc track with the top signal's progress in its tint, value (`Design.Font.number`, scaled to the radius) nearest the corner, 9.5 pt title beside it. Calm: clock (`HH:mm`, `h:mm` when 12 hour) and ambient CPU on the arc. Signals without progress show a dimmed full arc; with a deadline and no value, a live countdown.
- Rest styles: `full`; `shrink` (60 percent, grows on hover with `Motion.hover`, hysteresis); `tuck` (10 pt quarter disk with tint dot, panel ignores the mouse; opens after the pointer presses within 3 pt of the screen edge beside it for 150 ms; collapses 300 ms after leaving).
- Pass-through: the panel takes the mouse only while the pointer is on the drawn shape (`ignoresMouseEvents` toggled from a 20 Hz sampled mouse-moved monitor, plus `hitTest` returning nil off-shape). Never while tucked or while the card is up.
- Drag: press and move more than 4 pt moves the panel with the pointer; the body takes the orientation of the corner it would land in; on release it springs (`SpringAnimator`, response 0.46 / damping 0.80, same as `Motion.open`) into the nearest corner of the screen under the pointer and writes `model.settings.corner`. Reduce Motion snaps.
- Card: click, or press and hold 250 ms without moving, opens `CardView(model:presentation:.corner(corner))` in a second panel anchored to the corner (8 pt inset), scaling out of the corner with `Motion.open`, content fading in 60 ms later. Closes on pointer exit after 400 ms (armed only once the pointer has been inside, so opening from the menu bar does not close it at once), Esc, click outside (global and local monitors), or `cardAutoCloseSeconds` without pointer activity inside (0 means never). The card panel may become key only when a control needs typing (`becomesKeyOnlyIfNeeded`), and never activates the app.
- Closed card panels are released entirely. A hidden `NSHostingView` kept re-rendering the whole card on every 1 Hz sample (about 20 percent CPU in a debug build); releasing it brought idle back to 0.1 to 0.3 percent.
- Right-click on the body: Open Meridian, Settings….
- VoiceOver: "Meridian, <title> <value>", button trait, hint "Opens the card".
- Menu bar: left click posts `meridian.toggleCard`; right click menu has Open Meridian (also posts toggleCard), Pause/Resume updates (`model.stop()` / `model.start()`), Body submenu (writes `settings.body`), Settings… (command-comma), Quit. Text is monospaced 12 pt via `attributedTitle`, refreshed by a 1 Hz timer that only runs for the live styles. The glyph is a template `NSImage` (18x18, Core Graphics).
- Settings window: 680x480, titled and closable, unified toolbar, non-resizable. Because the app is an accessory with no main menu, `SettingsWindow.performKeyEquivalent` routes command-W and the edit shortcuts (C, V, X, A, Z).
- Agents pane posts `Notification.Name("meridian.agents.install")` (the same name `AgentsProvider.installNotification` uses).

## How to verify
```
swift build --scratch-path .build/ui-b
.build/ui-b/arm64-apple-macosx/debug/Meridian --mock --scenario lowBattery --settings [--corner topRight] [--settings-pane tiles]
```
- `--corner <topLeft|topRight|bottomLeft|bottomRight>` sets the corner at launch (it goes through `model.settings`, so it persists like any change) and logs `[corner] corner=... frame=...`.
- `--settings-pane <general|tiles|thresholds|modules|agents|about>` opens a pane.
- The corner only shows when Settings > General > "Show Meridian as" is Corner or Notch and corner (on this notched Mac, Automatic shows the notch only).

Logged frames on this Mac (1710x1112, menu bar 39 pt, Dock hidden), medium (72 pt):
topLeft {0,1001}, topRight {1638,1001}, bottomLeft {0,0}, bottomRight {1638,0}. The top two sit below the menu bar (visibleFrame).

Checked by running the app, with screenshots taken through the MacOS-MCP snapshot tool:
- General pane (all sections), Tiles pane (switches and drag handles), body mode switched to Corner from the UI, rest style switched to tuck from the UI (dot visible, tint red), shrink to full on hover, click opens the card from the top-left corner (card from the other workstream rendered), click outside closes it.
- Idle CPU (debug build, mock): corner alone 0.2 percent; with Settings open 0.3 percent; card closed after use 0.1 to 0.2 percent. With the card open it is 17 to 25 percent in a debug build, which is `CardView` content (sparklines and tiles re-rendering each second), not the corner.

## Not verified / known gaps
- `screencapture` fails here ("could not create image from display": no Screen Recording permission for the shell), so screenshots came from the MacOS-MCP snapshot tool.
- Real drag and the spring settle were not exercised (no way to drag programmatically). The geometry, nearest-corner logic and spring are separate pieces; `--corner` verified the end frames only.
- Thresholds, Modules, Agents and About panes were built and compile but I did not screenshot them.
- Menu bar styles other than `icon` were not visually checked; the right-click menu was not opened. Icon glyph renders in the menu bar.
- Click-through outside the shape relies on the sampled `ignoresMouseEvents` toggle. A click that arrives with no preceding mouse-move event (a synthetic teleport and click, as the MCP click tool does) lands before the toggle and passes through. Real pointer use always moves first.
- Tuck "pressing against the screen edge" uses both the layout area edge (below the menu bar) and the physical screen edge, with a 150 ms dwell so sliding toward the menu bar does not pop it open.
- Hover-to-open applies to the notch only (`notchHoverToOpen` is notch-named); the corner opens on click or press-and-hold as DESIGN.md says. The Settings label says so.
- The weather city field stores a name only; lat/lon are displayed, never set here (the weather module owns search).
- Global Esc needs Accessibility; without it Esc works only while the card panel is key. Click outside and pointer exit cover the common cases.
- `LaunchAtLogin` reports an error when run via `swift run` (not an installed bundle); it shows in the General pane.
- "Open Meridian" in the menu bar toggles the card (only `meridian.toggleCard` exists).

## Needs from Settings / AppModel
Nothing blocking. A dedicated "open card" notification would let "Open Meridian" never close an open card. A corner-specific hover-open setting would be reasonable if you want one.

## Housekeeping
- `pkill -x Meridian` kills every agent's running copy of the app (all binaries are named Meridian); use the PID.
- My runs wrote `meridian.settings.v1` into the shared `Meridian` defaults domain (body corner, rest tuck); I deleted the key at the end so the next run starts from defaults.
