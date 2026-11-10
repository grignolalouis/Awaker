import Foundation
import Observation

/// User preferences, persisted in UserDefaults on every change.
@MainActor
@Observable
final class AppSettings {
    static let durationChoices: [(minutes: Int, label: String)] = [
        (0, "Illimité"), (30, "30 min"), (60, "1 h"), (120, "2 h"), (240, "4 h"), (480, "8 h"),
    ]
    static let thresholdChoices = [10, 15, 20, 30]

    var defaultMinutes: Int { didSet { defaults.set(defaultMinutes, forKey: Key.defaultMinutes) } }
    var claudeAutoMode: Bool { didSet { defaults.set(claudeAutoMode, forKey: Key.claudeAutoMode) } }
    var batteryGuard: Bool { didSet { defaults.set(batteryGuard, forKey: Key.batteryGuard) } }
    var batteryThreshold: Int { didSet { defaults.set(batteryThreshold, forKey: Key.batteryThreshold) } }
    var acOnly: Bool { didSet { defaults.set(acOnly, forKey: Key.acOnly) } }
    var thermalGuard: Bool { didSet { defaults.set(thermalGuard, forKey: Key.thermalGuard) } }
    var showElapsedInMenuBar: Bool { didSet { defaults.set(showElapsedInMenuBar, forKey: Key.showElapsed) } }
    var notifications: Bool { didSet { defaults.set(notifications, forKey: Key.notifications) } }
    /// Tell the user when a Claude Code session finishes or needs them.
    var agentNotifications: Bool { didSet { defaults.set(agentNotifications, forKey: Key.agentNotifications) } }

    @ObservationIgnored private let defaults: UserDefaults

    private enum Key {
        static let defaultMinutes = "defaultMinutes"
        static let claudeAutoMode = "claudeAutoMode"
        static let batteryGuard = "batteryGuard"
        static let batteryThreshold = "batteryThreshold"
        static let acOnly = "acOnly"
        static let thermalGuard = "thermalGuard"
        static let showElapsed = "showElapsed"
        static let notifications = "notifications"
        static let agentNotifications = "agentNotifications"
    }

    init(defaults: UserDefaults = .standard) {
        self.defaults = defaults
        defaults.register(defaults: [
            Key.defaultMinutes: 0,
            Key.claudeAutoMode: false,
            Key.batteryGuard: true,
            Key.batteryThreshold: 15,
            Key.acOnly: false,
            Key.thermalGuard: true,
            Key.showElapsed: false,
            Key.notifications: true,
            Key.agentNotifications: true,
        ])
        defaultMinutes = defaults.integer(forKey: Key.defaultMinutes)
        claudeAutoMode = defaults.bool(forKey: Key.claudeAutoMode)
        batteryGuard = defaults.bool(forKey: Key.batteryGuard)
        batteryThreshold = defaults.integer(forKey: Key.batteryThreshold)
        acOnly = defaults.bool(forKey: Key.acOnly)
        thermalGuard = defaults.bool(forKey: Key.thermalGuard)
        showElapsedInMenuBar = defaults.bool(forKey: Key.showElapsed)
        notifications = defaults.bool(forKey: Key.notifications)
        agentNotifications = defaults.bool(forKey: Key.agentNotifications)
    }

    var defaultDuration: TimeInterval? {
        defaultMinutes > 0 ? TimeInterval(defaultMinutes * 60) : nil
    }

}
