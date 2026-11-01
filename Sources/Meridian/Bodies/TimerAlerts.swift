import AppKit
import Observation
import UserNotifications
import MeridianKit

/// When a timer or countdown fires (its signal turns critical) post one notification and play one sound.
/// De-duplicated by signal id, forgotten once the signal is no longer critical.
@MainActor
final class TimerAlerts {
    private let model: AppModel
    private var notified: Set<String> = []
    private var running = false

    init(model: AppModel) { self.model = model }

    func start() {
        running = true
        track()
    }

    func stop() { running = false }

    private func track() {
        guard running else { return }
        withObservationTracking {
            _ = model.signals
        } onChange: { [weak self] in
            Task { @MainActor in
                guard let self, self.running else { return }
                self.check()
                self.track()
            }
        }
    }

    private func check() {
        let firing = model.signals.filter { ($0.kind == .timer || $0.kind == .countdown) && $0.attention == .critical }
        let ids = Set(firing.map(\.id))
        notified.formIntersection(ids)
        for s in firing where !notified.contains(s.id) {
            notified.insert(s.id)
            NSSound(named: "Glass")?.play()
            post(s)
        }
    }

    private func post(_ s: Signal) {
        // UNUserNotificationCenter traps in a process that is not an app bundle (`swift run`).
        guard Bundle.main.bundleURL.pathExtension == "app" else { return }
        let center = UNUserNotificationCenter.current()
        let content = UNMutableNotificationContent()
        content.title = s.title
        if let d = s.detail { content.body = d }
        let request = UNNotificationRequest(identifier: s.id, content: content, trigger: nil)
        center.requestAuthorization(options: [.alert, .sound]) { granted, _ in
            guard granted else { return }
            center.add(request)
        }
    }
}
