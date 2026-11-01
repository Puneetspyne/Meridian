import Foundation
import Observation
import MeridianKit

/// The single source of truth for every surface. Samples telemetry on a timer, runs the rule engine,
/// merges module signals, and keeps per-metric histories for sparklines.
@MainActor
@Observable
final class AppModel {
    // MARK: State the views read
    private(set) var snapshot: TelemetrySnapshot = .empty
    private(set) var signals: [Signal] = []
    private(set) var ranked: [Signal] = []
    private(set) var histories: [MetricID: MetricHistory] = [:]
    private(set) var lastSampleError: String?
    var settings: Settings {
        didSet {
            guard settings != oldValue else { return }
            settings.save()
            engine.thresholds = settings.thresholds
            if settings.refreshInterval != oldValue.refreshInterval { restartSampling() }
            if settings.modules != oldValue.modules { pushModuleSettings() }
        }
    }

    /// The one thing the closed surface shows.
    var top: Signal? { ranked.first }
    var urgent: [Signal] { UrgencyRanker.urgent(signals) }

    // MARK: Internals
    private let source: TelemetrySource
    private var engine: RuleEngine
    private var providers: [SignalProvider] = []
    private var providerSignals: [String: [Signal]] = [:]
    private var samplingTask: Task<Void, Never>?

    init(source: TelemetrySource, settings: Settings = Settings.load()) {
        self.source = source
        self.settings = settings
        self.engine = RuleEngine(thresholds: settings.thresholds)
    }

    func register(provider: SignalProvider) {
        providers.append(provider)
        provider.onChange = { [weak self, weak provider] in
            guard let self, let provider else { return }
            self.providerSignals[provider.providerID] = provider.signals
            self.recomputeSignals()
        }
    }

    func start() {
        pushModuleSettings()
        providers.forEach { $0.start() }
        restartSampling()
    }

    func stop() {
        samplingTask?.cancel()
        samplingTask = nil
        providers.forEach { $0.stop() }
    }

    /// Modules exposing their settings-dependent state read it from here.
    func provider<P: SignalProvider>(_ type: P.Type) -> P? {
        providers.compactMap { $0 as? P }.first
    }

    // MARK: Sampling

    private func restartSampling() {
        samplingTask?.cancel()
        let interval = max(0.5, settings.refreshInterval)
        samplingTask = Task { [weak self] in
            while !Task.isCancelled {
                await self?.sampleOnce()
                try? await Task.sleep(for: .seconds(interval))
            }
        }
    }

    func sampleOnce() async {
        do {
            let s = try await source.sample()
            apply(snapshot: s)
            lastSampleError = nil
        } catch {
            lastSampleError = String(describing: error)
        }
    }

    func apply(snapshot s: TelemetrySnapshot) {
        snapshot = s
        record(s)
        recomputeSignals()
    }

    private func record(_ s: TelemetrySnapshot) {
        let t = s.timestamp
        func put(_ id: MetricID, _ v: Double?) {
            guard let v else { return }
            var h = histories[id] ?? MetricHistory(capacity: 180)
            h.record(v, at: t)
            histories[id] = h
        }
        put(.cpu, s.cpu?.total)
        put(.gpu, s.gpu?.utilization)
        put(.memory, s.memory?.usedFraction)
        put(.networkDown, s.network?.rxBytesPerSec)
        put(.networkUp, s.network?.txBytesPerSec)
        put(.diskRead, s.bootDisk?.readBytesPerSec)
        put(.diskWrite, s.bootDisk?.writeBytesPerSec)
        put(.battery, s.battery?.level)
        put(.cpuTemp, s.thermal?.cpuCelsius)
        put(.gpuTemp, s.thermal?.gpuCelsius)
        put(.fan, s.thermal?.fans.first?.rpm)
        put(.power, s.power?.totalWatts)
    }

    private func recomputeSignals() {
        var all = engine.evaluate(snapshot, now: Date())
        for (_, list) in providerSignals.sorted(by: { $0.key < $1.key }) { all += list }
        signals = all
        ranked = UrgencyRanker.rank(all)
    }

    private func pushModuleSettings() {
        for p in providers { p.apply(settings.modules) }
    }
}

enum MetricID: String, CaseIterable, Hashable {
    case cpu, gpu, memory, networkDown, networkUp, diskRead, diskWrite, battery, cpuTemp, gpuTemp, fan, power
}
