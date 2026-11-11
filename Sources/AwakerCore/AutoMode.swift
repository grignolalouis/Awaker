import Foundation

/// Auto mode's decisions: keep the Mac awake while agents work, give it back a while after they stop,
/// and never undo a stop the user asked for.
///
/// Pure and time-based, so the rules hold whatever the caller's polling rhythm.
public struct AutoMode: Equatable, Sendable {
    public enum Action: Equatable, Sendable {
        case start, stop, nothing
    }

    /// How long agents must stay idle before it counts. Long enough to span the gap between two turns.
    public let grace: TimeInterval
    /// Since when no agent has been at work. Nil while one is.
    private var idleSince: Date?
    /// The user stopped an auto session: don't start another until the agents have really gone quiet.
    private var isSuppressed = false

    public init(grace: TimeInterval = 180) {
        self.grace = grace
    }

    /// When an auto session ends if no agent goes back to work. Nil while one is working.
    public var stopsAt: Date? {
        idleSince?.addingTimeInterval(grace)
    }

    /// Call when the user stops a session by hand.
    public mutating func userStopped() {
        isSuppressed = true
    }

    /// Call when the user starts a session by hand: their intent is clear again.
    public mutating func userStarted() {
        isSuppressed = false
    }

    /// What to do now.
    /// - Parameters:
    ///   - isEnabled: the user's auto mode setting.
    ///   - busyAgents: agents whose work a sleeping Mac would stop.
    ///   - isAwake: a session is running, whoever started it.
    ///   - isAutoSession: that session was started by auto mode.
    public mutating func step(now: Date, isEnabled: Bool, busyAgents: Int, isAwake: Bool, isAutoSession: Bool) -> Action {
        if busyAgents > 0 {
            idleSince = nil
        } else if idleSince == nil {
            idleSince = now
        }
        let idleLongEnough = idleSince.map { now.timeIntervalSince($0) >= grace } ?? false
        if idleLongEnough { isSuppressed = false }

        if isAwake {
            return isAutoSession && idleLongEnough ? .stop : .nothing
        }
        return isEnabled && busyAgents > 0 && !isSuppressed ? .start : .nothing
    }
}
