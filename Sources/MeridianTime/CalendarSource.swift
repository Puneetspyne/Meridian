import EventKit
import Foundation

/// Reads upcoming meetings from the user's calendars through EventKit. Opt-in: nothing is touched until
/// `setEnabled(true)`. Refreshes on `EKEventStoreChanged` and every 60 seconds while enabled.
///
/// The host app needs `NSCalendarsFullAccessUsageDescription` in its Info.plist.
@MainActor
public final class CalendarSource {
    public enum Access: Sendable { case unknown, granted, denied }

    public private(set) var access: Access = .unknown
    /// Events in the next 24 hours, soonest first. All-day and declined events are already removed.
    public private(set) var events: [MeetingEvent] = []
    public private(set) var isActive = false
    public var onChange: (@MainActor () -> Void)?

    private var store: EKEventStore?
    private var observer: NSObjectProtocol?
    private var pollTimer: Timer?
    private var generation = 0

    public init() {}

    /// Starts or stops reading. Requests access the first time it is enabled.
    public func setEnabled(_ enabled: Bool) {
        guard enabled != isActive else { return }
        isActive = enabled
        generation += 1
        guard enabled else {
            teardown()
            events = []
            onChange?()
            return
        }
        let current = generation
        Task { @MainActor [weak self] in
            guard let self else { return }
            if EKEventStore.authorizationStatus(for: .event) == .notDetermined {
                _ = await self.requestAccess()
            } else {
                self.updateAccess()
            }
            guard self.isActive, self.generation == current, self.access == .granted else { return }
            self.attach()
            self.refresh()
        }
    }

    /// Asks for full calendar access (macOS 14+ API). Returns whether it was granted.
    @discardableResult
    public func requestAccess() async -> Bool {
        let granted = (try? await eventStore().requestFullAccessToEvents()) ?? false
        updateAccess()
        return granted
    }

    /// Events starting within `window` of `now` (default 24 h), excluding all-day and declined ones.
    public func upcomingEvents(within window: TimeInterval = 24 * 3600, now: Date = Date()) -> [MeetingEvent] {
        guard EKEventStore.authorizationStatus(for: .event) == .fullAccess else { return [] }
        let store = eventStore()
        let predicate = store.predicateForEvents(withStart: now.addingTimeInterval(-60),
                                                 end: now.addingTimeInterval(window), calendars: nil)
        return store.events(matching: predicate).compactMap { event -> MeetingEvent? in
            guard !event.isAllDay, event.status != .canceled, let start = event.startDate, let end = event.endDate,
                  start >= now.addingTimeInterval(-60) else { return nil }
            let declined = event.attendees?.contains { $0.isCurrentUser && $0.participantStatus == .declined } ?? false
            guard !declined else { return nil }
            let ident = event.eventIdentifier ?? event.calendarItemIdentifier
            return MeetingEvent(
                id: "\(ident)@\(Int(start.timeIntervalSince1970))",
                title: (event.title?.isEmpty == false ? event.title : nil) ?? "Meeting",
                start: start, end: end,
                joinLink: MeetingLinks.extract(url: event.url, location: event.location, notes: event.notes))
        }.sorted { $0.start < $1.start }
    }

    /// The soonest event with `start >= now - 1 minute`.
    public func nextMeeting(now: Date = Date()) -> MeetingEvent? { MeetingEvent.next(in: events, now: now) }

    // MARK: Internals

    private func eventStore() -> EKEventStore {
        if let store { return store }
        let created = EKEventStore()
        store = created
        return created
    }

    private func updateAccess() {
        switch EKEventStore.authorizationStatus(for: .event) {
        case .fullAccess: access = .granted
        case .notDetermined: access = .unknown
        default: access = .denied
        }
    }

    private func attach() {
        teardown()
        observer = NotificationCenter.default.addObserver(
            forName: .EKEventStoreChanged, object: eventStore(), queue: .main
        ) { [weak self] _ in
            MainActor.assumeIsolated { self?.refresh() }
        }
        let timer = Timer(timeInterval: 60, repeats: true) { [weak self] _ in
            MainActor.assumeIsolated { self?.refresh() }
        }
        timer.tolerance = 5
        RunLoop.main.add(timer, forMode: .common)
        pollTimer = timer
    }

    private func teardown() {
        if let observer { NotificationCenter.default.removeObserver(observer) }
        observer = nil
        pollTimer?.invalidate()
        pollTimer = nil
    }

    private func refresh() {
        guard isActive else { return }
        let fresh = upcomingEvents()
        if fresh != events {
            events = fresh
            onChange?()
        }
    }
}
