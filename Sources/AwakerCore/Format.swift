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
        case .claude: "Auto · Claude Code"
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
        case .claudeIdle: "Agents au repos"
        case .quit: "App quittée"
        case .crash: "Interrompu"
        }
    }
}

public extension BatteryInfo {
    var sourceLabel: String {
        if charging { return "En charge" }
        return onAC ? "Sur secteur" : "Sur batterie"
    }
}

public extension ProcessInfo.ThermalState {
    var label: String {
        switch self {
        case .nominal: "Normale"
        case .fair: "Tiède"
        case .serious: "Élevée"
        case .critical: "Critique"
        @unknown default: "Inconnue"
        }
    }
}
