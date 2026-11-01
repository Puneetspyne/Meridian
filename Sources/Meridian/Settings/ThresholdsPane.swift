import SwiftUI
import MeridianKit

/// When a reading turns into a signal. Temperatures are stored in Celsius and shown in the unit chosen under Modules.
struct ThresholdsPane: View {
    @Bindable var model: AppModel

    private var unit: TemperatureUnit { model.settings.modules.temperatureUnit }

    var body: some View {
        Form {
            Section("Processor") {
                ValueSlider(title: "High load above", value: $model.settings.thresholds.cpuSustainedFraction,
                            range: 0.5...1, step: 0.05) { Format.percent($0) }
                ValueSlider(title: "For at least", value: $model.settings.thresholds.cpuSustainedSeconds,
                            range: 10...300, step: 10) { "\(Int($0)) s" }
                ValueSlider(title: "Warn at", value: $model.settings.thresholds.cpuTempWarningC,
                            range: 70...105, step: 1) { Format.temperatureWithUnit($0, unit: unit) }
                ValueSlider(title: "Critical at", value: $model.settings.thresholds.cpuTempCriticalC,
                            range: 80...115, step: 1) { Format.temperatureWithUnit($0, unit: unit) }
                Picker("Warn when the system reports", selection: $model.settings.thresholds.thermalPressureWarning) {
                    Text("Fair").tag(ThermalPressure.fair)
                    Text("Serious").tag(ThermalPressure.serious)
                    Text("Critical").tag(ThermalPressure.critical)
                }
                ValueSlider(title: "Fans warn above", value: $model.settings.thresholds.fanWarningFraction,
                            range: 0.5...1, step: 0.05) { Format.percent($0) + " of max" }
            }

            Section("Memory") {
                Picker("Warn at pressure", selection: $model.settings.thresholds.memoryWarningPressure) {
                    Text("Warning").tag(MemoryPressure.warning)
                    Text("Critical").tag(MemoryPressure.critical)
                }
            }

            Section {
                ValueSlider(title: "Warn below", value: $model.settings.thresholds.diskFreeWarningFraction,
                            range: 0.05...0.30, step: 0.01) { Format.percent($0) + " free" }
                ValueSlider(title: "Critical below", value: $model.settings.thresholds.diskFreeCriticalFraction,
                            range: 0.01...0.15, step: 0.01) { Format.percent($0) + " free" }
                ValueSlider(title: "Or less than", value: gigabytes,
                            range: 1...50, step: 1) { "\(Int($0)) GB" }
            } header: { Text("Startup disk") } footer: {
                Text("Critical applies when either the percentage or the amount is reached.")
            }

            Section("Battery") {
                ValueSlider(title: "Warn at", value: $model.settings.thresholds.batteryWarningLevel,
                            range: 0.10...0.50, step: 0.01) { Format.percent($0) }
                ValueSlider(title: "Critical at", value: $model.settings.thresholds.batteryCriticalLevel,
                            range: 0.03...0.25, step: 0.01) { Format.percent($0) }
                ValueSlider(title: "Or with under", value: minutes,
                            range: 5...60, step: 5) { "\(Int($0)) min left" }
            }

            Section {
                Button("Restore defaults") { model.settings.thresholds = .default }
                    .disabled(model.settings.thresholds == .default)
            }
        }
        .formStyle(.grouped)
    }

    private var gigabytes: Binding<Double> {
        Binding(get: { Double(model.settings.thresholds.diskFreeCriticalBytes) / 1_000_000_000 },
                set: { model.settings.thresholds.diskFreeCriticalBytes = UInt64($0 * 1_000_000_000) })
    }

    private var minutes: Binding<Double> {
        Binding(get: { Double(model.settings.thresholds.batteryCriticalMinutes) },
                set: { model.settings.thresholds.batteryCriticalMinutes = Int($0) })
    }
}
