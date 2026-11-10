import Foundation

/// What started a period of keeping the Mac awake.
public enum Trigger: String, Codable, Sendable {
    case manual
    /// Started by auto mode. Stored as "claude", its name in earlier versions.
    case auto = "claude"
}

/// Why a period of keeping the Mac awake stopped.
public enum EndReason: String, Codable, Sendable {
    case manual, timer, battery, unplugged, thermal, quit, crash
    /// Auto mode found no agent at work for a while. Stored as "claudeIdle", its name in earlier versions.
    case agentsIdle = "claudeIdle"

    /// True when the app stopped on its own, which deserves a notification.
    public var isAutomatic: Bool {
        switch self {
        case .manual, .quit, .crash: false
        case .timer, .battery, .unplugged, .thermal, .agentsIdle: true
        }
    }
}

/// One period during which the Mac was kept awake.
public struct AwakeSession: Codable, Identifiable, Sendable, Equatable {
    public var id: UUID
    public var start: Date
    public var end: Date?
    public var trigger: Trigger
    public var startBattery: Int?
    public var endBattery: Int?
    public var endReason: EndReason?
    /// Last time the app confirmed the session was still running. A session interrupted by a crash ends there.
    public var lastSeen: Date?

    public init(id: UUID = UUID(), start: Date, end: Date? = nil, trigger: Trigger, startBattery: Int? = nil,
                endBattery: Int? = nil, endReason: EndReason? = nil, lastSeen: Date? = nil) {
        self.id = id
        self.start = start
        self.end = end
        self.trigger = trigger
        self.startBattery = startBattery
        self.endBattery = endBattery
        self.endReason = endReason
        self.lastSeen = lastSeen
    }

    public var isRunning: Bool { end == nil }

    public func duration(now: Date) -> TimeInterval {
        (end ?? now).timeIntervalSince(start)
    }

    /// The session as it should be recorded when the app finds it still open at launch.
    public func closedAfterInterruption() -> AwakeSession {
        var closed = self
        closed.end = lastSeen ?? start
        closed.endReason = .crash
        return closed
    }
}

public extension Array where Element == AwakeSession {
    /// Time spent awake across all sessions, counting a running one up to `now`.
    func totalAwakeTime(now: Date) -> TimeInterval {
        reduce(0) { $0 + Swift.max(0, $1.duration(now: now)) }
    }
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
