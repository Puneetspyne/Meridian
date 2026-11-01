# Weather module handoff

Owner files: `Sources/MeridianWeather/**`, `Tests/MeridianWeatherTests/**`. No `MeridianKit` changes. Foundation only.

## Public API for the UI (`import MeridianWeather`)

`WeatherProvider` (`@MainActor`, `SignalProvider`, `providerID == "weather"`)
- `init(settings: ModuleSettings, client: OpenMeteoClient = .init(), cache: WeatherCache = .init(), now:)`
- Read-only: `current: CurrentConditions?` (temperature, feelsLike, humidity %, wind km/h, precipitation mm, weatherCode, isDay, `condition`),
  `hourly: [HourForecast]` (next 12, starting at the current hour), `daily: [DayForecast]` (7; high, low, sunrise, sunset, precipitationProbabilityMax, `condition`),
  `sunrise`, `sunset` (today), `lastUpdated: Date?`, `isStale: Bool`, `lastError: WeatherError?` (has `errorDescription`), `place: Place?`, `isEnabled`, `forecast: Forecast?` (the full model, incl. `timeZone`).
- `search(_ query: String) async throws -> [Place]` for the location picker. `Place.displayName` is "Bengaluru, Karnataka, India"; store `name`/`latitude`/`longitude` into `ModuleSettings`.
- `refresh(force: Bool = false) async` (also what start and the 15 min timer call).
- All temperatures are celsius; format with `Format.temperature(_, unit:)`. Wind is km/h.
- `WeatherCondition(code:isDay:)`: `description`, `symbol` (SF Symbol), `severity` (`.normal/.notable/.severe`), `isWet`.

Behaviour
- Enabled only when `weatherEnabled` and both coordinates are set; otherwise `signals == []`, no network, no timer.
- `start()` shows the cache immediately (stale or not), fetches if the cache is older than 15 min. Timer every 15 min (tolerance 60 s) always refetches.
- `apply(_:)`: changed coordinates refetch; changed unit, 24 h clock or location name only rebuilds signals (no request); disabling clears state and signals.
- Failed fetch falls back to the cache and sets `isStale = true` and `lastError`. Cache: `~/Library/Application Support/Meridian/weather-cache.json`, matched by location within about 1 km.

## Signals

| id | attention | priority | when |
| --- | --- | --- | --- |
| `weather.current` | calm | 4 | always when enabled and a forecast exists. Title = place name, value "27°", detail "Partly cloudy · feels 29° · rain 45% at 16:00" (rain clause only if an hour in the next 6 has probability >= 40%; honours `uses24HourClock`, "4 PM" otherwise) |
| `weather.alert` | warning | 45 | current condition severity is `.severe` (thunderstorm, hail, violent showers). Title = condition, tint amber |
| `weather.alert` | info | 20 | not currently wet and an hour in the next 6 has probability >= 70%. Title "Rain at 18:00", symbol `umbrella.fill`, tint blue |

At most one `weather.alert` at a time; the severe warning wins over the rain notice. No deadlines are set so a rain notice never outranks a meeting by soonest-deadline.

## Decisions

- Request adds `forecast_hours=24` and `forecast_days=7` so hourly starts at the current hour. Hourly has no `is_day`, so it is derived from that day's sunrise/sunset.
- `forecast(latitude:longitude:unit:)` takes a `unit` for call-site symmetry; the wire value is always `celsius`.
- WMO 71-77 and 85-86 (any snow) are `.notable`; 82 (violent showers) is `.severe`, as is any hail.
- `Forecast` times are real `Date`s parsed in the forecast's time zone (Open-Meteo returns local wall time).

## Verified

- `swift build --scratch-path .build/weather --target MeridianWeather`: clean (a full `swift build` currently fails in `MeridianSensors`, another agent's in-flight work, unrelated).
- `./scripts/test.sh --scratch-path .build/weather --filter MeridianWeatherTests`: 22 tests pass (decode fixtures, geocoding, errors, URL construction, WMO table, signals for rain/thunderstorm/calm/already-raining/beyond-6h, 12 h and Fahrenheit formatting, cache freshness with injected clock, provider refresh/offline fallback/disable/unit change). No test touches the network.
- Live (`MERIDIAN_LIVE=1`, run once on this online machine):

```
LIVE Bengaluru, Karnataka, India: 22° Overcast, feels 25°, hourly 24, daily 7
```

## Not done

- Nothing committed. No UI. Hourly/daily use the model's own code for `isDay` on daily conditions (always day icons).
