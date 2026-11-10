import Foundation

/// User-facing formatting and wording, in English.
public enum Format {
    private static let english = Locale(identifier: "en_US")

    /// "45 min", "2 h 05".
    public static func duration(_ seconds: TimeInterval) -> String {
        let minutes = max(0, Int(seconds / 60))
        let hours = minutes / 60
        guard hours > 0 else { return "\(minutes) min" }
        return "\(hours) h " + String(format: "%02d", minutes % 60)
    }

    /// "1:05", for the menu bar.
    public static func clock(_ seconds: TimeInterval) -> String {
        let minutes = max(0, Int(seconds / 60))
        return "\(minutes / 60):" + String(format: "%02d", minutes % 60)
    }

    /// The time of day, in the user's own 12- or 24-hour format.
    public static func time(_ date: Date) -> String {
        date.formatted(date: .omitted, time: .shortened)
    }

    /// "Today", "Yesterday", "Saturday, November 7".
    public static func day(_ date: Date, calendar: Calendar = .current) -> String {
        if calendar.isDateInToday(date) { return "Today" }
        if calendar.isDateInYesterday(date) { return "Yesterday" }
        return date.formatted(.dateTime.weekday(.wide).month(.wide).day().locale(english))
    }

    /// "$26.49". Small amounts keep their cents; from $100 up, whole dollars are enough.
    public static func dollars(_ amount: Double) -> String {
        let digits = amount >= 100 ? 0 : 2
        return "$" + amount.formatted(.number.precision(.fractionLength(digits)).locale(english))
    }

    /// "1 agent", "3 agents".
    public static func plural(_ count: Int, _ singular: String, _ plural: String) -> String {
        "\(count) \(count > 1 ? plural : singular)"
    }
}

public extension Trigger {
    var label: String {
        switch self {
        case .manual: "Manual"
        case .auto: "Auto"
        }
    }
}

public extension EndReason {
    var label: String {
        switch self {
        case .manual: "Stopped by hand"
        case .timer: "Time was up"
        case .battery: "Low battery"
        case .unplugged: "Charger unplugged"
        case .thermal: "Overheating"
        case .agentsIdle: "Agents went idle"
        case .quit: "App quit"
        case .crash: "Interrupted"
        }
    }

    /// Why a session can't start, said to the user. Nil for reasons that never block a start.
    func blockerMessage(battery: BatteryInfo?) -> String? {
        switch self {
        case .unplugged: "Plug in the charger: \"Only when plugged in\" is on."
        case .battery: "Battery too low (\(battery?.percent ?? 0)%)."
        case .thermal: "The Mac is too hot."
        case .manual, .timer, .agentsIdle, .quit, .crash: nil
        }
    }
}

public extension AgentSession {
    /// What the agent is doing, in a few words.
    var statusLabel: String {
        switch state {
        case .working: "Working"
        case .waiting(let tool): tool.map { "Asking permission: \($0)" } ?? "Waiting for your answer"
        case .finished: "Finished"
        case .background: "Background command running"
        }
    }

    /// What a waiting agent is asking for, as precisely as its files allow. Empty when it isn't waiting.
    var requestDescription: String {
        guard case .waiting(let tool) = state else { return "" }
        if let action = details.pendingAction { return "It asks permission for: \(action)." }
        if let tool { return "It asks permission for: \(tool)." }
        return "It is waiting for your answer."
    }

    /// The notification this agent deserves after moving from `previous` to its current state, if any:
    /// it now needs the user, or it has just finished working.
    func notification(after previous: AgentState) -> (title: String, body: String)? {
        guard previous != state else { return nil }
        switch state {
        case .waiting:
            return ("\(displayTitle) needs you", "\(requestDescription) Project \(projectName).")
        case .finished where previous == .working, .background where previous == .working:
            return ("\(displayTitle) finished", details.lastReply ?? "Your move. Project \(projectName).")
        case .working, .finished, .background:
            return nil
        }
    }
}
