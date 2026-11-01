# Handoff: time module (`MeridianTime`)

Foundation + EventKit only, no AppKit. Everything below is `public` unless marked internal.

## Building the provider

```swift
TimeProvider(settings: ModuleSettings, storeDirectory: URL? = nil, calendar: Calendar = .current, now: @escaping () -> Date = { Date() })
```
`providerID == "time"`. Call `start()` (1 Hz `Timer` on the main run loop, tolerance 0.1; also enables the calendar if
`settings.calendarEnabled`), `stop()` (flushes to disk), `apply(_ settings: ModuleSettings)` (the protocol label is `_`).
`signals` is already populated after `init`, so the surface is never empty. State loads from
`Paths.supportDirectory/time.json` on init; saves are debounced 0.5 s, `flush()` writes now.

## Read-only state for the UI
`timers: [TimerItem]`, `countdowns: [Countdown]`, `stopwatch: Stopwatch?` (nil = none), `todos: [TodoItem]`,
`worldClocks: [WorldClock]`, `nextMeeting: MeetingEvent?`, `workdayProgress: Double` (0...1, 09:00-18:00 local),
`calendarSource: CalendarSource` (has `access: .unknown/.granted/.denied`, `requestAccess() async -> Bool`), `lastSaveError`.
`onChange` fires when any signal or world clock changed textually, and always after a mutation (so list UIs refresh).

## Mutation API (exact names)
- `add(parsed: QuickParse.Parsed) -> Bool` (false for `.invalid`)
- `addTimer(name:seconds:) -> UUID` (starts running), `addCountdown(name:fireAt:repeatRule:) -> UUID`, `addTodo(_:) -> UUID`
- `pause(timerID:)`, `resume(timerID:)`, `reset(timerID:)` (stopped at full duration; `resume` restarts), `remove(timerID:)`,
  `addMinutes(_ minutes: Int, to timerID: UUID)` (also revives a finished timer)
- `remove(countdownID:)`, `remove(todo:)`, `complete(todo: UUID)` (toggles done)
- `startStopwatch()` (starts or resumes), `lapStopwatch()`, `stopStopwatch()` (pause, keeps laps), `resetStopwatch()` (sets nil)
- `dismiss(signalID: String)`: finished timer stops nagging (stays in `timers` for reset); countdown completes (repeating ones
  jump to next occurrence); meeting is hidden for this launch (not persisted). Other ids ignored.

`QuickParse.parse(_:now:calendar:) -> Parsed` (`.timer(name:seconds:)`, `.countdown(name:fireAt:repeatRule:)`, `.stopwatch`,
`.todo(text:)`, `.invalid(reason:)`). The label is `repeatRule`, not `repeat`. `.invalid` carries a user-facing hint.
`RepeatRule`: `.none/.daily/.weekdays/.weekly(Set<Int>)` (Calendar weekday numbers, 1 = Sunday), `.label` ("every Mon, Wed").

## Signals
| id | kind | attention | notes |
| --- | --- | --- | --- |
| `time.timer.<uuid>` | timer | running: `.info`; past end and not dismissed: `.critical` "Time's up" (detail = name, value "-m:ss", tint red); paused/ready: `.calm` (detail "Paused"/"Ready", priority 40) | deadline = endsAt, progress elapsed/duration, symbol timer, tint teal, priority 50 |
| `time.countdown.<uuid>` | countdown | `.calm` > 15 min (value `Format.relative`), `.info` <= 15 min, `.warning` <= 2 min (value m:ss), `.critical` from fire time for 60 s (value "Now"), then auto-complete/advance | symbol hourglass, tint violet/amber/red, priority 52, deadline fireAt |
| `time.stopwatch` | stopwatch | running `.info`, stopped `.calm` | value elapsed, detail "Lap n · split · Running", priority 45 |
| `time.meeting.<event id>` | meeting | `.calm` > 15 min (title = event, value relative), `.info` <= 15 min and `.warning` <= 2 min (title "Standup in 1m 20s", value m:ss), `.critical` from start to start+1 min (title "Standup now") | detail "9:40-10:10 · Zoom", actionURL = join link, actionTitle "Join", symbol calendar, tint blue, priority 55, deadline start |
| `time.clock` | clock | `.calm` always | title "Clock", value HH:mm or h:mm a, detail "Wed 4 Nov", priority 5, symbol clock |

Meeting selection: soonest event with `start >= now - 1 min`. Band edges are inclusive on the nearer side (exactly 900 s is `.info`, exactly 120 s is `.warning`).
Within 30 s of start `Format.relative` says "now", so a 20 s warning title reads "Standup now" while still `.warning`.

## Grammar notes
Also accepted beyond the brief: "10min", "2hr", "6 pm" (split), "today 6pm", "tmrw", "every mon, wed 7pm". A day qualifier without a time
("fri release notes") is a to-do. Out-of-range times ("25:99", "13pm") are `.invalid`. A time equal to `now` rolls to tomorrow.

## What I verified
- `swift build --scratch-path .build/time --target MeridianTime`: clean, no warnings.
- `./scripts/test.sh --scratch-path .build/time --filter MeridianTimeTests`: 37 tests green. They cover every grammar line with now = Wed 2026-11-04 14:32 Asia/Kolkata (including rollover and weekday repeats), timer
  lifecycle (running, time's up, overtime, dismiss, pause/resume/reset/add minutes), countdown bands and auto-complete, meeting bands and detail/join action,
  join-link extraction for all five services, world clocks at 12/24 h, persistence round trip and corrupt file, debounced save.

## Gaps and caveats
- Full `swift build` was failing at the time of writing because `MeridianAgents` is mid-edit (missing `AgentSession` etc.); not mine. I built my target alone.
- `CalendarSource` is not exercised against a real `EKEventStore` in tests (it would prompt for permission). Meetings are tested through the internal `meetingEventsOverride`
  and `MeetingEvent.next`. `events(matching:)` runs synchronously on the main actor once per minute.
- The host app must add `NSCalendarsFullAccessUsageDescription` to its Info.plist, or EventKit access will be refused.
- No notifications or sound when a timer ends; that belongs to the app layer (observe `.critical` timer/countdown signals).
- Dismissed meetings are in memory only. To-dos never emit signals.
- Timer/countdown firing relies on wall-clock dates, so they survive relaunch but a Mac asleep through a countdown's 60 s critical window skips straight to its next occurrence.
