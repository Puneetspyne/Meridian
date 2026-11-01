import SwiftUI
import MeridianKit

struct ModulesPane: View {
    @Bindable var model: AppModel

    private static let zoneIDs: [String] = TimeZone.knownTimeZoneIdentifiers.sorted()
    private let maxZones = 3

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

            Section {
                Toggle("Show your next meeting", isOn: $model.settings.modules.calendarEnabled)
            } header: { Text("Calendar") } footer: {
                Text("Meridian asks for calendar access the first time you turn this on. Events stay on your Mac.")
            }

            Section {
                Toggle("Show the weather", isOn: $model.settings.modules.weatherEnabled)
                TextField("City", text: city)
                    .disabled(!model.settings.modules.weatherEnabled)
                LabeledContent("Coordinates") { Text(coordinates).monospacedDigit().foregroundStyle(.secondary) }
            } header: { Text("Weather") } footer: {
                Text("Weather comes from Open-Meteo and is the only thing Meridian fetches over the network. City search is added with the weather module; for now the name and coordinates are stored as they are set.")
            }
        }
        .formStyle(.grouped)
    }

    private var city: Binding<String> {
        Binding(get: { model.settings.modules.weatherLocationName ?? "" },
                set: { model.settings.modules.weatherLocationName = $0.isEmpty ? nil : $0 })
    }

    private var coordinates: String {
        guard let lat = model.settings.modules.weatherLatitude, let lon = model.settings.modules.weatherLongitude else { return "Not set" }
        return String(format: "%.3f°, %.3f°", lat, lon)
    }

    private func zoneBinding(_ index: Int) -> Binding<String> {
        Binding(get: { model.settings.modules.secondaryTimeZones.indices.contains(index) ? model.settings.modules.secondaryTimeZones[index] : "UTC" },
                set: { if model.settings.modules.secondaryTimeZones.indices.contains(index) { model.settings.modules.secondaryTimeZones[index] = $0 } })
    }

    /// Every known zone, plus the current value if it is an alias the system list lacks, so the picker never shows blank.
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
