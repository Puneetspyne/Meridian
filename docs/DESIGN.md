# Meridian design language

Meridian shows one thing at a time, beautifully, and gets out of the way. This document is the brief
every surface follows. Tokens live in `Sources/Meridian/Design/Tokens.swift`; this file explains them.

## Principles

1. **One glance.** The closed surface shows exactly one signal: the top of `UrgencyRanker`. Never a dashboard.
2. **Hardware first.** The notch extension is matte black, the same black as the bezel, so it reads as part of
   the Mac. Glass is for the open card only. Nothing glows in the closed state except the single accent.
3. **Springs, never curves.** Every state change is a spring from `Design.Motion`. Values animate with
   `.contentTransition(.numericText())`. Reduce Motion turns springs into 150 ms crossfades.
4. **System colour only.** Accents are `systemRed`, `systemOrange`, `systemTeal`, `systemBlue`, `systemGreen`,
   `systemPurple`. White at 92/58/36 percent for text. No custom brand colour anywhere.
5. **Quiet typography.** SF Pro, rounded for numbers, monospaced digits so nothing jitters. The biggest number
   in the hero is 44 pt. Labels are 10.5 to 12.5 pt, medium or semibold, never bold.
6. **Nothing competes with the user's work.** Panels never take key focus, never steal activation, never sit
   over the pointer uninvited. Hover opens are delayed 350 ms and cancel instantly on pointer exit.

## Bodies

### Notch body (notched displays)

**Closed.** A black shape wraps the hardware notch with 2 pt extra on each side and 4 pt extra below, bottom
corners radius 14, continuous curvature. Left and right of the notch, two *wings* 132 pt wide (configurable)
carry one live element each:

- Left wing: the top signal's symbol and value, e.g. a 16 pt ring at 2.5 pt stroke filled to `progress`,
  with the value in `Design.Font.wing` beside it. Calm state shows the ambient CPU ring in white.
- Right wing: the top signal's title, or when calm the clock (`HH:mm`), in `Design.Font.wing`.
  A deadline signal shows a live countdown here (`Format.countdown`).

When attention is warning or critical, the accent colour tints the wing content and a 1 pt accent line
runs along the bottom edge of the shape, fading in with `Motion.swap`.

**Hover.** The whole shape grows 6 pt in height and the wings extend 12 pt with `Motion.hover`. The pointer
cursor stays an arrow.

**Open.** After `notchHoverDelay` or on click, the card unfolds *downward from the notch* like a drawer:
width `Design.Size.cardWidth` (440), anchored centred on the notch, top corners merge seamlessly into the
black shape, bottom corners radius 26. Use `Motion.open`; the content fades in 60 ms after the shape begins.
Closing uses `Motion.close`. The card closes on pointer exit after 400 ms, on Esc, or after
`cardAutoCloseSeconds` without interaction.

### Corner body (every display, every Mac)

**Closed.** A quarter circle of radius `CornerSize.points` in the chosen screen corner, matte black with a
1 pt hairline. Along the curve, an arc track shows the top signal's `progress` in its tint. The value sits
inside near the corner, the title in `wingLabel` below it. Calm state: time, with the ring showing the
workday or the ambient CPU (user setting).

**Rest styles.** `full` keeps it as is. `shrink` rests at 60 percent and grows on hover. `tuck` collapses to a
10 pt dot that passes clicks through, growing when the pointer presses against the screen edge beside it.

**Drag.** Press and drag anywhere on the quarter circle; it follows the pointer and, on release, springs into
the nearest corner with `Motion.open`. Press and hold 250 ms without moving opens the card.

**Open.** The card grows out of the corner (anchored to it, so top-left opens down-right) with
`Motion.open`, same content as the notch card.

### Menu bar item

Optional. `icon` shows the Meridian glyph; `cpu` and `temperature` show a live value in monospaced 12 pt;
`topSignal` shows the symbol and value of the top signal. Clicking toggles the card from the item.

## The card

Same content from both bodies. Sections, top to bottom, separated by 12 pt, inside 16 pt padding:

1. **Hero.** The top signal. Left: a 56 pt ring (4 pt stroke) or symbol in the signal tint. Right: title
   (`heroTitle`), value (`heroValue`), detail (`body`, secondary). If the signal has `actionURL`, a capsule
   button with `actionTitle`. The hero uses `matchedGeometryEffect` with the wing so opening feels like the
   wing expanding into it.
2. **Tiles.** A 2-column grid of `Design.Size.tileHeight` (76) tiles in the user's order, each with a label,
   a value and a 1 pt sparkline over the last 180 samples drawn with `Path.trim` on first appearance.
   Tiles: CPU (plus a 4 + 4 core bar row for E and P cores), Memory (pressure dot), Temperature (hottest
   sensor, fan rpm), Network (down and up with two sparklines), Disk (free, read and write), Battery (level,
   time, watts), GPU, Fans, Power (cpu, gpu, total watts and the source), Top processes (3 rows).
3. **Time strip.** Next meeting with Join, running timers and countdowns, two world clocks. Quick add field
   appears on ⌥⌘T or clicking the plus.
4. **Agents strip** (when enabled). One row per coding-agent session: name, state dot (violet working,
   amber needs you, green done), elapsed time. Click opens the session.
5. **Footer.** Chip name, uptime, "Updated 1 s ago", gear button.

Card background: `meridianGlass()`. Tiles: `meridianGlass(radius: 16)` with `cardTint`. Hairlines at 8
percent, 16 percent in Increase Contrast.

## States to design for

The snapshot renderer must produce every one of these with the mock source so the README and reviews can see
them: calm notch closed and open, hot (critical) closed and open, low battery, disk full, meeting in 1 minute,
agent needs you, corner body in all four corners and three rest styles, menu bar item in each style, settings.

## Accessibility

Every surface has VoiceOver labels ("CPU 94 percent, warning"). Reduce Motion swaps springs for crossfades
and stops ring animations. Increase Contrast raises hairlines and text opacity. Everything works with the
pointer only; nothing requires a trackpad gesture.
