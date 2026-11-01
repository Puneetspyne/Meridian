# Privacy

- **No telemetry.** No analytics, crash reporting or tracking of any kind.
- **Network.** The only request Meridian makes is to Open-Meteo (weather, and geocoding for a city you type), and only when weather is enabled. No API key, no account. An optional public-IP lookup exists only if you turn it on.
- **Files it writes.** Settings in `UserDefaults` (`com.puneetspyne.Meridian`). Module state in `~/Library/Application Support/Meridian`.
- **Hooks.** Claude Code hooks are installed into your Claude settings only when you opt in from Settings, and can be removed from the same place. Off by default.
- **Calendar and location.** Requested only when you enable the feature that needs them. Calendar is read-only; location is only used to name the Wi-Fi network.
