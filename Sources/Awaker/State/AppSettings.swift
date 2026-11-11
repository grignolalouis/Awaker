import AwakerCore
import Foundation
import Observation

/// User preferences, persisted in UserDefaults on every change.
@MainActor
@Observable
final class AppSettings {
    static let durationChoices: [(minutes: Int, label: String)] = [
        (0, "No limit"), (30, "30 min"), (60, "1 h"), (120, "2 h"), (240, "4 h"), (480, "8 h"),
    ]
    static let thresholdChoices = [10, 15, 20, 30]

    var defaultMinutes: Int { didSet { defaults.set(defaultMinutes, forKey: Key.defaultMinutes) } }
    var autoMode: Bool { didSet { defaults.set(autoMode, forKey: Key.autoMode) } }
    var batteryGuard: Bool { didSet { defaults.set(batteryGuard, forKey: Key.batteryGuard) } }
    var batteryThreshold: Int { didSet { defaults.set(batteryThreshold, forKey: Key.batteryThreshold) } }
    var acOnly: Bool { didSet { defaults.set(acOnly, forKey: Key.acOnly) } }
    var thermalGuard: Bool { didSet { defaults.set(thermalGuard, forKey: Key.thermalGuard) } }
    var notifications: Bool { didSet { defaults.set(notifications, forKey: Key.notifications) } }
    /// Tell the user when a Claude Code session finishes or needs them.
    var agentNotifications: Bool { didSet { defaults.set(agentNotifications, forKey: Key.agentNotifications) } }

    /// The picture behind the window: the id of a `BackdropScene`.
    var backdrop: String { didSet { defaults.set(backdrop, forKey: Key.backdrop) } }
    /// Whether the picture moves. Off, it is drawn once and costs nothing afterwards.
    var animatedBackdrop: Bool { didSet { defaults.set(animatedBackdrop, forKey: Key.animatedBackdrop) } }
    /// Names of the avatar skins the user doesn't want agents to wear.
    var hiddenSkins: Set<String> { didSet { defaults.set(hiddenSkins.sorted(), forKey: Key.hiddenSkins) } }

    @ObservationIgnored private let defaults: UserDefaults

    private enum Key {
        static let defaultMinutes = "defaultMinutes"
        /// Kept from earlier versions, so the preference survives updates.
        static let autoMode = "claudeAutoMode"
        static let batteryGuard = "batteryGuard"
        static let batteryThreshold = "batteryThreshold"
        static let acOnly = "acOnly"
        static let thermalGuard = "thermalGuard"
        static let notifications = "notifications"
        static let agentNotifications = "agentNotifications"
        static let hiddenSkins = "hiddenSkins"
        static let backdrop = "backdrop"
        static let animatedBackdrop = "animatedBackdrop"
    }

    init(defaults: UserDefaults = .standard) {
        self.defaults = defaults
        defaults.register(defaults: [
            Key.defaultMinutes: 0,
            Key.autoMode: false,
            Key.batteryGuard: true,
            Key.batteryThreshold: 15,
            Key.acOnly: false,
            Key.thermalGuard: true,
            Key.notifications: true,
            Key.agentNotifications: true,
            Key.animatedBackdrop: true,
        ])
        defaultMinutes = defaults.integer(forKey: Key.defaultMinutes)
        autoMode = defaults.bool(forKey: Key.autoMode)
        batteryGuard = defaults.bool(forKey: Key.batteryGuard)
        batteryThreshold = defaults.integer(forKey: Key.batteryThreshold)
        acOnly = defaults.bool(forKey: Key.acOnly)
        thermalGuard = defaults.bool(forKey: Key.thermalGuard)
        notifications = defaults.bool(forKey: Key.notifications)
        agentNotifications = defaults.bool(forKey: Key.agentNotifications)
        backdrop = defaults.string(forKey: Key.backdrop) ?? Backdrop.scenes[0].id
        animatedBackdrop = defaults.bool(forKey: Key.animatedBackdrop)
        hiddenSkins = Set(defaults.stringArray(forKey: Key.hiddenSkins) ?? [])
    }

    var defaultDuration: TimeInterval? { Self.duration(minutes: defaultMinutes) }

    var defaultDurationLabel: String {
        Self.durationChoices.first { $0.minutes == defaultMinutes }?.label ?? Self.durationChoices[0].label
    }

    /// A choice's length; nil for "no limit" (0 minutes).
    static func duration(minutes: Int) -> TimeInterval? {
        minutes > 0 ? TimeInterval(minutes * 60) : nil
    }

    /// The protections as one rule.
    var powerPolicy: PowerPolicy {
        PowerPolicy(acOnly: acOnly, batteryGuard: batteryGuard, batteryThreshold: batteryThreshold, thermalGuard: thermalGuard)
    }

}
