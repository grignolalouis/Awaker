import Foundation

/// User-facing formatting, in French.
public enum Format {
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

    /// "14:05".
    public static func time(_ date: Date) -> String {
        date.formatted(date: .omitted, time: .shortened)
    }

    /// "Aujourd'hui", "Hier", "Samedi 7 novembre".
    public static func day(_ date: Date, calendar: Calendar = .current) -> String {
        if calendar.isDateInToday(date) { return "Aujourd'hui" }
        if calendar.isDateInYesterday(date) { return "Hier" }
        let text = date.formatted(.dateTime.weekday(.wide).day().month(.wide))
        return text.prefix(1).uppercased() + text.dropFirst()
    }

    /// "26,49 $". Small amounts keep their cents; from 100 $ up, whole dollars are enough.
    public static func dollars(_ amount: Double) -> String {
        let digits = amount >= 100 ? 0 : 2
        return amount.formatted(.number.precision(.fractionLength(digits)).locale(Locale(identifier: "fr_FR"))) + " $"
    }

    public static func plural(_ count: Int, _ singular: String, _ plural: String) -> String {
        "\(count) \(count > 1 ? plural : singular)"
    }
}

public extension Trigger {
    var label: String {
        switch self {
        case .manual: "Manuel"
        case .auto: "Auto"
        }
    }
}

public extension EndReason {
    var label: String {
        switch self {
        case .manual: "Arrêt manuel"
        case .timer: "Durée écoulée"
        case .battery: "Batterie faible"
        case .unplugged: "Chargeur débranché"
        case .thermal: "Surchauffe"
        case .agentsIdle: "Agents au repos"
        case .quit: "App quittée"
        case .crash: "Interrompu"
        }
    }

    /// Why a session can't start, said to the user. Nil for reasons that never block a start.
    func blockerMessage(battery: BatteryInfo?) -> String? {
        switch self {
        case .unplugged: "Branche le chargeur : l'option « secteur uniquement » est active."
        case .battery: "Batterie trop faible (\(battery?.percent ?? 0) %)."
        case .thermal: "Le Mac est trop chaud."
        case .manual, .timer, .agentsIdle, .quit, .crash: nil
        }
    }
}

public extension AgentSession {
    /// What the agent is doing, in a few words.
    var statusLabel: String {
        switch state {
        case .working: "Travaille"
        case .waiting(let tool): tool.map { "Demande ton accord : \($0)" } ?? "Attend ta réponse"
        case .finished: "A terminé"
        case .background: "Commande en cours en arrière-plan"
        }
    }

    /// What a waiting agent is asking for, as precisely as its files allow. Empty when it isn't waiting.
    var requestDescription: String {
        guard case .waiting(let tool) = state else { return "" }
        if let action = details.pendingAction { return "Il demande ton accord pour : \(action)." }
        if let tool { return "Il demande ton accord pour : \(tool)." }
        return "Il attend ta réponse."
    }

    /// The notification this agent deserves after moving from `previous` to its current state, if any:
    /// it now needs the user, or it has just finished working.
    func notification(after previous: AgentState) -> (title: String, body: String)? {
        guard previous != state else { return nil }
        switch state {
        case .waiting:
            return ("\(displayTitle) a besoin de toi", "\(requestDescription) Projet \(projectName).")
        case .finished where previous == .working, .background where previous == .working:
            return ("\(displayTitle) a terminé", details.lastReply ?? "À toi de jouer. Projet \(projectName).")
        case .working, .finished, .background:
            return nil
        }
    }
}
