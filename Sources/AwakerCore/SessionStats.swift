import Foundation

/// Read-only statistics over a list of sessions. Pure: same input, same output.
public struct SessionStats: Sendable {
    public struct Day: Identifiable, Sendable, Equatable {
        public let day: Date
        public let manual: TimeInterval
        public let auto: TimeInterval

        public var id: Date { day }
        public var total: TimeInterval { manual + auto }
    }

    public let sessions: [Session]
    public let now: Date
    private let calendar: Calendar

    public init(sessions: [Session], now: Date, calendar: Calendar = .current) {
        self.sessions = sessions
        self.now = now
        self.calendar = calendar
    }

    /// Awake time inside [start, end], clipping sessions that cross the bounds.
    public func awakeTime(from start: Date, to end: Date, trigger: Trigger? = nil) -> TimeInterval {
        sessions
            .filter { trigger == nil || $0.trigger == trigger }
            .reduce(0) { total, session in
                let overlapStart = max(session.start, start)
                let overlapEnd = min(session.end ?? now, end)
                return total + max(0, overlapEnd.timeIntervalSince(overlapStart))
            }
    }

    /// One entry per calendar day, oldest first, ending today.
    public func days(_ count: Int) -> [Day] {
        let today = calendar.startOfDay(for: now)
        return (0..<count).reversed().compactMap { offset in
            guard let start = calendar.date(byAdding: .day, value: -offset, to: today),
                  let next = calendar.date(byAdding: .day, value: 1, to: start) else { return nil }
            let end = min(next, now)
            return Day(
                day: start,
                manual: awakeTime(from: start, to: end, trigger: .manual),
                auto: awakeTime(from: start, to: end, trigger: .claude)
            )
        }
    }

    /// Relative change of awake time over the last 7 days versus the 7 days before. Nil without a baseline.
    public var weekOverWeekChange: Double? {
        let week: TimeInterval = 7 * 24 * 3600
        let current = awakeTime(from: now.addingTimeInterval(-week), to: now)
        let previous = awakeTime(from: now.addingTimeInterval(-2 * week), to: now.addingTimeInterval(-week))
        guard previous > 0 else { return nil }
        return (current - previous) / previous
    }

    /// Sessions overlapping the window, clipped to it (for chart highlights).
    public func ranges(since start: Date) -> [DateRange] {
        sessions.compactMap { session in
            let end = session.end ?? now
            guard end > start else { return nil }
            return DateRange(start: max(session.start, start), end: end)
        }
    }

    public func sessions(since date: Date) -> [Session] {
        sessions.filter { ($0.end ?? now) >= date }
    }

    public var longest: TimeInterval {
        sessions.map { $0.duration(now: now) }.max() ?? 0
    }

    public var total: TimeInterval {
        awakeTime(from: .distantPast, to: now)
    }

    /// Average battery drop per hour across finished sessions longer than 10 min that lost charge.
    public var drainPerHour: Double? {
        let draining = sessions.compactMap { session -> (drop: Double, hours: Double)? in
            guard let start = session.startBattery, let end = session.endBattery, session.end != nil,
                  start > end, session.duration(now: now) > 600 else { return nil }
            return (Double(start - end), session.duration(now: now) / 3600)
        }
        let hours = draining.reduce(0) { $0 + $1.hours }
        guard hours > 0 else { return nil }
        return draining.reduce(0) { $0 + $1.drop } / hours
    }
}
