import Foundation

/// What started a session.
public enum Trigger: String, Codable, Sendable {
    case manual
    case claude
}

/// Why a session stopped.
public enum EndReason: String, Codable, Sendable {
    case manual, timer, battery, unplugged, thermal, claudeIdle, quit, crash

    /// True when the app stopped on its own, which deserves a notification.
    public var isAutomatic: Bool {
        switch self {
        case .manual, .quit, .crash: false
        case .timer, .battery, .unplugged, .thermal, .claudeIdle: true
        }
    }
}

/// One period during which the Mac was kept awake.
public struct Session: Codable, Identifiable, Sendable, Equatable {
    public var id: UUID
    public var start: Date
    public var end: Date?
    public var trigger: Trigger
    public var startBattery: Int?
    public var endBattery: Int?
    public var endReason: EndReason?

    public init(
        id: UUID = UUID(),
        start: Date,
        end: Date? = nil,
        trigger: Trigger,
        startBattery: Int? = nil,
        endBattery: Int? = nil,
        endReason: EndReason? = nil
    ) {
        self.id = id
        self.start = start
        self.end = end
        self.trigger = trigger
        self.startBattery = startBattery
        self.endBattery = endBattery
        self.endReason = endReason
    }

    public var isRunning: Bool { end == nil }

    public func duration(now: Date) -> TimeInterval {
        (end ?? now).timeIntervalSince(start)
    }
}

/// One measurement, taken every minute while the app runs.
public struct Sample: Codable, Identifiable, Sendable, Equatable {
    public var date: Date
    public var battery: Int?
    public var onAC: Bool
    public var active: Bool
    public var claudeSessions: Int

    public init(date: Date, battery: Int?, onAC: Bool, active: Bool, claudeSessions: Int) {
        self.date = date
        self.battery = battery
        self.onAC = onAC
        self.active = active
        self.claudeSessions = claudeSessions
    }

    public var id: Date { date }
}

public struct BatteryInfo: Sendable, Equatable {
    public var percent: Int
    public var onAC: Bool
    public var charging: Bool

    public init(percent: Int, onAC: Bool, charging: Bool) {
        self.percent = percent
        self.onAC = onAC
        self.charging = charging
    }
}

public struct DateRange: Identifiable, Sendable, Equatable {
    public let start: Date
    public let end: Date

    public init(start: Date, end: Date) {
        self.start = start
        self.end = end
    }

    public var id: Date { start }
}
