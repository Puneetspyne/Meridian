import Foundation

/// Fixed-capacity ring of recent values for sparklines. Appending is O(1); reading is in chronological order.
public struct History<Value: Sendable>: Sendable {
    public private(set) var capacity: Int
    private var storage: [Value]
    private var head = 0
    private var count = 0

    public init(capacity: Int) {
        precondition(capacity > 0)
        self.capacity = capacity
        self.storage = []
        self.storage.reserveCapacity(capacity)
    }

    public mutating func append(_ value: Value) {
        if storage.count < capacity {
            storage.append(value)
            count = storage.count
        } else {
            storage[head] = value
            head = (head + 1) % capacity
        }
    }

    /// Oldest first.
    public var values: [Value] {
        if storage.count < capacity { return storage }
        return Array(storage[head...] + storage[..<head])
    }

    public var last: Value? { values.last }
    public var isEmpty: Bool { storage.isEmpty }
    public var isFull: Bool { storage.count == capacity }
}

/// A timestamped Double series, which is what every tile sparkline draws.
public struct MetricHistory: Sendable {
    public struct Point: Sendable, Equatable {
        public var time: Date
        public var value: Double
        public init(time: Date, value: Double) { self.time = time; self.value = value }
    }

    private var ring: History<Point>

    public init(capacity: Int = 120) { ring = History(capacity: capacity) }

    public mutating func record(_ value: Double, at time: Date = Date()) {
        ring.append(Point(time: time, value: value))
    }

    public var points: [Point] { ring.values }
    public var values: [Double] { ring.values.map(\.value) }
    public var last: Double? { ring.last?.value }
    public var max: Double? { values.max() }
    public var min: Double? { values.min() }
    public var capacity: Int { ring.capacity }

    /// Mean over the trailing window, used for "sustained" judgements and smoothing.
    public func average(last n: Int) -> Double? {
        let tail = values.suffix(n)
        guard !tail.isEmpty else { return nil }
        return tail.reduce(0, +) / Double(tail.count)
    }
}
