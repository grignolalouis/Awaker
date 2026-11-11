import Foundation

/// Why the Mac is being kept awake right now, so the user never has to guess.
/// One rule for the window and the menu bar.
public enum AwakeReason: Equatable, Sendable {
    /// The user started the session, with or without an end time.
    case user(until: Date?)
    /// Auto mode holds the Mac for these agents (their titles, in display order).
    case agents([String])
    /// Auto mode found no agent at work and gives the Mac back at that time. Nil until the next check has dated it.
    case agentsDone(sleepAt: Date?)

    /// - Parameters:
    ///   - busyAgents: titles of the agents whose work a sleeping Mac would stop.
    ///   - autoStopsAt: when auto mode ends its session, as `AutoMode.stopsAt` says.
    public init(trigger: Trigger, endsAt: Date?, busyAgents: [String], autoStopsAt: Date?) {
        switch trigger {
        case .manual: self = .user(until: endsAt)
        case .auto: self = busyAgents.isEmpty ? .agentsDone(sleepAt: autoStopsAt) : .agents(busyAgents)
        }
    }

    /// One short line: "Kept awake by “Contacts screen redesign” and 1 other agent".
    public func sentence(time: (Date) -> String = Format.time) -> String {
        switch self {
        case .user(let until):
            return "Started by you · " + (until.map { "until \(time($0))" } ?? "no time limit")
        case .agents(let titles):
            guard let first = titles.first else { return "Kept awake by auto mode" }
            let others = titles.count - 1
            return "Kept awake by “\(first)”" + (others > 0 ? " and \(Format.plural(others, "other agent", "other agents"))" : "")
        case .agentsDone(let sleepAt):
            return "No agent working · " + (sleepAt.map { "normal sleep at \(time($0))" } ?? "normal sleep returns soon")
        }
    }
}
