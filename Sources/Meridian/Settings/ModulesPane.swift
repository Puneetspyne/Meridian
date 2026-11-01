import SwiftUI
import MeridianKit
import MeridianTime
import MeridianWeather

struct ModulesPane: View {
    @Bindable var model: AppModel

    private static let zoneIDs: [String] = TimeZone.knownTimeZoneIdentifiers.sorted()
    private let maxZones = 3

    @State private var query = ""
    @State private var results: [Place] = []
    @State private var searching = false
    @State private var searchError: String?

    private var weather: WeatherProvider? { model.provider(WeatherProvider.self) }
    private var time: TimeProvider? { model.provider(TimeProvider.self) }

    var body: some View {
        Form {
            Section("Display") {
                Picker("Temperature", selection: $model.settings.modules.temperatureUnit) {
                    Text("Celsius").tag(TemperatureUnit.celsius)
                    Text("Fahrenheit").tag(TemperatureUnit.fahrenheit)
                }
                .pickerStyle(.segmented)
                Toggle("24-hour clock", isOn: $model.settings.modules.uses24HourClock)
            }

            Section {
                ForEach(Array(model.settings.modules.secondaryTimeZones.enumerated()), id: \.offset) { index, _ in
                    HStack {
                        Picker("Time zone \(index + 1)", selection: zoneBinding(index)) {
                            ForEach(options(for: index), id: \.self) { Text($0.replacingOccurrences(of: "_", with: " ")).tag($0) }
                        }
                        Button {
                            model.settings.modules.secondaryTimeZones.remove(at: index)
                        } label: {
                            Image(systemName: "minus.circle")
                        }
                        .buttonStyle(.borderless)
                        .accessibilityLabel("Remove time zone \(index + 1)")
                        .help("Remove")
                    }
                }
                if model.settings.modules.secondaryTimeZones.count < maxZones {
                    Button("Add time zone…", action: addZone)
                }
            } header: { Text("World clocks") } footer: {
                Text("Up to three clocks beside your own, shown in the card.")
            }

            calendarSection
            weatherSection
        }
        .formStyle(.grouped)
    }

    // MARK: Calendar

    private var calendarSection: some View {
        Section {
            Toggle("Show your next meeting", isOn: Binding(
                get: { model.settings.modules.calendarEnabled },
                set: { on in
                    model.settings.modules.calendarEnabled = on
                    if on { Task { _ = await time?.calendarSource.requestAccess() } }
                }))
            if model.settings.modules.calendarEnabled {
                TimelineView(.periodic(from: .now, by: 1)) { _ in
                    calendarStatus
                }
            }
        } header: { Text("Calendar") } footer: {
            Text("Meridian asks for calendar access the first time you turn this on. Events stay on your Mac.")
        }
    }

    @ViewBuilder private var calendarStatus: some View {
        switch time?.calendarSource.access ?? .unknown {
        case .granted:
            LabeledContent("Access") { Label("Allowed", systemImage: "checkmark.circle").foregroundStyle(.secondary) }
        case .unknown:
            LabeledContent("Access") { Text("Waiting for your answer").foregroundStyle(.secondary) }
        case .denied:
            VStack(alignment: .leading, spacing: 8) {
                LabeledContent("Access") { Label("Not allowed", systemImage: "exclamationmark.triangle").foregroundStyle(.secondary) }
                Text("To show meetings, allow Meridian in System Settings, Privacy & Security, Calendars.")
                    .font(.callout).foregroundStyle(.secondary)
                Button("Open Calendar privacy settings…") {
                    if let url = URL(string: "x-apple.systempreferences:com.apple.preference.security?Privacy_Calendars") {
                        NSWorkspace.shared.open(url)
                    }
                }
            }
        }
    }

    // MARK: Weather

    private var weatherSection: some View {
        Section {
            Toggle("Show the weather", isOn: $model.settings.modules.weatherEnabled)

            LabeledContent("Location") {
                Text(model.settings.modules.weatherLocationName ?? "Not set").foregroundStyle(.secondary)
            }
            if model.settings.modules.weatherEnabled, model.settings.modules.weatherLatitude != nil {
                TimelineView(.periodic(from: .now, by: 2)) { _ in weatherStatus }
            }

            TextField("Search for a city", text: $query)
                .textContentType(.addressCity)
                .task(id: query) { await runSearch() }

            if searching { ProgressView().controlSize(.small) }
            if let searchError {
                Label(searchError, systemImage: "wifi.slash").font(.callout).foregroundStyle(.secondary)
            } else if !query.trimmingCharacters(in: .whitespaces).isEmpty, !searching, results.isEmpty {
                Text("No places found.").font(.callout).foregroundStyle(.secondary)
            }
            ForEach(results) { place in
                Button { choose(place) } label: {
                    HStack {
                        Text(place.displayName)
                        Spacer()
                        Text(String(format: "%.2f°, %.2f°", place.latitude, place.longitude))
                            .font(.caption).monospacedDigit().foregroundStyle(.tertiary)
                    }
                    .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
            }
        } header: { Text("Weather") } footer: {
            Text("Weather comes from Open-Meteo and is the only thing Meridian fetches over the network. Choosing a place turns the weather on.")
        }
    }

    @ViewBuilder private var weatherStatus: some View {
        if let w = weather {
            if let updated = w.lastUpdated {
                LabeledContent("Status") {
                    Text(w.isStale ? "Out of date, updated \(Self.ago(updated))" : "Updated \(Self.ago(updated))")
                        .foregroundStyle(.secondary)
                }
            } else if w.lastError == nil {
                LabeledContent("Status") { Text("Loading…").foregroundStyle(.secondary) }
            }
            if let err = w.lastError {
                Label(err.errorDescription ?? "Weather could not be updated.", systemImage: "wifi.slash")
                    .font(.callout).foregroundStyle(.secondary)
            }
        }
    }

    private static func ago(_ date: Date) -> String {
        let minutes = Int(Date().timeIntervalSince(date) / 60)
        return minutes < 1 ? "just now" : "\(minutes) min ago"
    }

    /// Debounced 400 ms; `.task(id:)` cancels the previous run when the text changes.
    private func runSearch() async {
        let q = query.trimmingCharacters(in: .whitespaces)
        searchError = nil
        guard q.count >= 2 else { results = []; searching = false; return }
        try? await Task.sleep(for: .milliseconds(400))
        guard !Task.isCancelled, let weather else { return }
        searching = true
        defer { searching = false }
        do {
            let found = try await weather.search(q)
            guard !Task.isCancelled else { return }
            results = found
        } catch {
            guard !Task.isCancelled else { return }
            results = []
            searchError = (error as? LocalizedError)?.errorDescription ?? "Search needs an internet connection."
        }
    }

    private func choose(_ place: Place) {
        model.settings.modules.weatherLocationName = place.displayName
        model.settings.modules.weatherLatitude = place.latitude
        model.settings.modules.weatherLongitude = place.longitude
        model.settings.modules.weatherEnabled = true
        query = ""
        results = []
    }

    // MARK: Time zones

    private func zoneBinding(_ index: Int) -> Binding<String> {
        Binding(get: { model.settings.modules.secondaryTimeZones.indices.contains(index) ? model.settings.modules.secondaryTimeZones[index] : "UTC" },
                set: { if model.settings.modules.secondaryTimeZones.indices.contains(index) { model.settings.modules.secondaryTimeZones[index] = $0 } })
    }

    private func options(for index: Int) -> [String] {
        let current = model.settings.modules.secondaryTimeZones.indices.contains(index) ? model.settings.modules.secondaryTimeZones[index] : "UTC"
        return Self.zoneIDs.contains(current) ? Self.zoneIDs : [current] + Self.zoneIDs
    }

    private func addZone() {
        let taken = Set(model.settings.modules.secondaryTimeZones)
        let next = ["America/New_York", "Europe/London", "Asia/Kolkata", "Asia/Tokyo", "America/Los_Angeles"].first { !taken.contains($0) } ?? "UTC"
        model.settings.modules.secondaryTimeZones.append(next)
    }
}
