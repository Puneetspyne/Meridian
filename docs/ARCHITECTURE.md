# Architecture

Meridian is a Swift package that builds with the Xcode Command Line Tools alone. No Xcode project.

```
swift build -c release          # everything
./scripts/build-app.sh          # Meridian.app in build/
./scripts/test.sh               # all suites (Swift Testing from the Command Line Tools)
swift run meridianctl snapshot  # one live telemetry snapshot as JSON
swift run Meridian --mock --scenario hot   # run the app on fake data
swift run Meridian --snapshot docs/snapshots  # render every surface to PNG
```

## Modules and ownership

| Target | Depends on | What it is |
| --- | --- | --- |
| `MeridianKit` | nothing | Pure models: `TelemetrySnapshot`, `Signal`, `UrgencyRanker`, `RuleEngine`, `MetricHistory`, `Format`, `MockTelemetrySource`, `SignalProvider` contract. No AppKit. |
| `CMeridian` | nothing | C shim: IOKit structs for the SMC, declarations for privately resolved symbols (HID sensors, IOReport). |
| `MeridianSensors` | Kit, CMeridian | `LiveTelemetrySource` and one sampler per section: CPU, memory, GPU, disks, network, battery, temperatures (SMC + HID), fans, power (IOReport), processes, system info. |
| `MeridianTime` | Kit | `TimeProvider`: timers, countdowns, stopwatch, next meeting (EventKit), world clocks, quick-add parser. |
| `MeridianAgents` | Kit | `AgentsProvider`: coding-agent sessions from Claude Code hooks, opt-in installer, event log reader. |
| `MeridianWeather` | Kit | `WeatherProvider`: Open-Meteo current conditions and forecast, geocoding, no API key. |
| `Meridian` | all | The app: `AppModel`, bodies (notch, corner), card, settings, status item, snapshot renderer, design tokens. |
| `meridianctl` | Kit, Sensors | Terminal probe and sensor-map exporter for contributors. |

Each module has one owner at a time. Do not edit another module's files; if you need a contract change,
add to `MeridianKit` additively and say so in your handoff.

## Data flow

```
LiveTelemetrySource.sample()  ──1 Hz──▶  AppModel.apply(snapshot)
                                            ├─ MetricHistory per MetricID (sparklines)
                                            ├─ RuleEngine.evaluate → [Signal]   (thermal, cpu, memory, disk, battery)
TimeProvider / AgentsProvider / WeatherProvider ──onChange──▶ providerSignals
                                            └─ UrgencyRanker.rank(all) → ranked, top
Bodies observe AppModel (Observation) and render `top` closed, everything open.
```

Threading: samplers run off the main thread inside `LiveTelemetrySource.sample()` (use `Task.detached` or a
dedicated queue for IOKit calls; never block the main actor). `AppModel` and all providers are `@MainActor`.

## Signals

`Signal` is the one vocabulary. Rules and providers emit them; the ranker orders them; the UI renders them.
A provider replaces its whole signal list on each change and ids must be stable (`time.timer.<uuid>`,
`agents.session.<id>`, `weather.current`) so SwiftUI can animate transitions.

Attention levels: `calm` (ambient, only shows when nothing else does), `info`, `warning`, `critical`.
Within a level, soonest `deadline` wins, then `priority`, then most recent `createdAt`.

## Privacy

No network except Open-Meteo when weather is enabled and an optional public-IP lookup the user turns on.
No analytics. Settings in `UserDefaults`; module state in `~/Library/Application Support/Meridian`.
Calendar and Claude Code hooks are opt-in and off by default.

## Private APIs

Temperatures on Apple silicon come from `IOHIDEventSystemClient` (private) and the SMC via `AppleSMC`
(undocumented but stable since 2006). Power comes from IOReport (private). All of these are resolved with
`dlsym` at runtime and fail soft: a missing symbol or a permission change in a future macOS yields `nil`
for that metric, never a crash. The app is not sandboxed and is distributed outside the App Store.

## Testing

Swift Testing (`import Testing`). `scripts/test.sh` finds the framework inside the Command Line Tools.
Kit and parser tests are pure. Sensor tests cover decoders (sp78, flt, fpe2, ioft) with fixtures and run
the live samplers once, asserting shape not values. UI is verified through the snapshot renderer.
