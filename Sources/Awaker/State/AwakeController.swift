import AwakerCore
import Foundation
import IOKit.pwr_mgt
import Observation

/// Owns the "keep awake" state: starting and stopping sessions, applying the protections and auto mode,
/// and making sure the Mac's real sleep setting always matches what the app shows.
@MainActor
@Observable
final class AwakeController {
    // Session state
    private(set) var isActive = false
    private(set) var trigger: Trigger?
    private(set) var startedAt: Date?
    private(set) var endsAt: Date?
    private(set) var isAuthorized: Bool
    private(set) var launchesAtLogin: Bool
    private(set) var lastError: String?

    // Live readings, refreshed every tick
    private(set) var now = Date()
    private(set) var battery: BatteryInfo?
    private(set) var isThermalCritical = false

    @ObservationIgnored private let settings: AppSettings
    @ObservationIgnored private let history: HistoryStore
    @ObservationIgnored private let agents: AgentMonitor
    @ObservationIgnored private let system: SystemControl
    @ObservationIgnored private let defaults: UserDefaults

    @ObservationIgnored private var autoMode = AutoMode()
    @ObservationIgnored private var assertionID: IOPMAssertionID = 0
    @ObservationIgnored private var sessionID: UUID?
    @ObservationIgnored private var ticker: Timer?

    private let tickInterval: TimeInterval = 30

    private enum Key {
        static let resumeTrigger = "resumeTrigger"
        static let resumeEndsAt = "resumeEndsAt"
    }

    init(settings: AppSettings, history: HistoryStore, agents: AgentMonitor, system: SystemControl,
         defaults: UserDefaults = .standard) {
        self.settings = settings
        self.history = history
        self.agents = agents
        self.system = system
        self.defaults = defaults
        isAuthorized = system.isAuthorized()
        launchesAtLogin = system.launchesAtLogin()
    }

    /// Why a session can't start right now, in the user's words. Nil when it can.
    var startBlocker: String? {
        if !isAuthorized { return "Installe d'abord l'autorisation dans les réglages." }
        return settings.powerPolicy.blocker(battery: battery, isThermalCritical: isThermalCritical)?.blockerMessage(battery: battery)
    }

    /// Call once at launch.
    func start() {
        refreshReadings()
        history.closeInterruptedSessions()
        reconcileSleepSetting()
        resumeSessionAfterRelaunch()
        let timer = Timer(timeInterval: tickInterval, repeats: true) { [weak self] _ in
            Task { @MainActor in self?.tick() }
        }
        RunLoop.main.add(timer, forMode: .common)
        ticker = timer
    }

    // MARK: Starting and stopping

    func toggle() {
        if isActive {
            deactivate()
        } else {
            activate(for: settings.defaultDuration)
        }
    }

    @discardableResult
    func activate(for duration: TimeInterval?, trigger: Trigger = .manual) -> Bool {
        let isAutomatic = trigger == .auto
        if !isAutomatic { lastError = nil }

        if let blocker = startBlocker {
            if !isAutomatic { lastError = blocker }
            return false
        }

        if !isActive {
            guard system.setSleepDisabled(true) else {
                lastError = "pmset a refusé la commande. Réinstalle l'autorisation."
                return false
            }
            IOPMAssertionCreateWithName(
                kIOPMAssertionTypePreventUserIdleSystemSleep as CFString,
                IOPMAssertionLevel(kIOPMAssertionLevelOn),
                "Awaker" as CFString,
                &assertionID
            )
            sessionID = history.startSession(trigger: trigger, battery: battery?.percent)
            startedAt = Date()
            isActive = true
        }

        self.trigger = trigger
        endsAt = duration.map { Date().addingTimeInterval($0) }
        if isAutomatic {
            let count = Format.plural(agents.busyCount, "agent au travail", "agents au travail")
            notify("Mac maintenu éveillé", "\(count). Tu peux fermer le capot.")
        } else {
            autoMode.userStarted()
        }
        return true
    }

    func deactivate(_ reason: EndReason = .manual) {
        guard isActive else { return }
        let restored = system.setSleepDisabled(false)
        if assertionID != 0 {
            IOPMAssertionRelease(assertionID)
            assertionID = 0
        }
        if let sessionID {
            history.endSession(sessionID, battery: battery?.percent, reason: reason)
        }
        if reason == .manual { autoMode.userStopped() }
        sessionID = nil
        isActive = false
        trigger = nil
        startedAt = nil
        endsAt = nil

        if !restored {
            // The worst failure this app can have: say so, and `reconcileSleepSetting` retries on every tick.
            lastError = "La veille normale n'a pas pu être rétablie. Nouvel essai en cours."
        } else if reason.isAutomatic {
            notify("Veille normale rétablie", reason.label)
        }
    }

    // MARK: Ticking

    private func tick() {
        refreshReadings()
        reconcileSleepSetting()
        if isActive, let sessionID {
            history.heartbeat(sessionID, battery: battery?.percent)
        }

        if isActive, let stop = stopReason() {
            return deactivate(stop)
        }
        switch autoMode.step(now: now, isEnabled: settings.autoMode, busyAgents: agents.busyCount,
                             isAwake: isActive, isAutoSession: trigger == .auto) {
        case .start: activate(for: nil, trigger: .auto)
        case .stop: deactivate(.agentsIdle)
        case .nothing: break
        }
    }

    private func refreshReadings() {
        now = Date()
        battery = system.battery()
        isThermalCritical = ProcessInfo.processInfo.thermalState == .critical
    }

    /// Why the running session must stop now: its time is up, or a protection kicks in.
    private func stopReason() -> EndReason? {
        if let endsAt, now >= endsAt { return .timer }
        return settings.powerPolicy.blocker(battery: battery, isThermalCritical: isThermalCritical)
    }

    /// Makes the Mac's real setting match the app's state. Sleep can be left disabled by a crash or a failed
    /// restore, and switched back on behind a running session by another copy of the app or by hand.
    private func reconcileSleepSetting() {
        guard isAuthorized else { return }
        let isDisabled = system.isSleepDisabled()
        guard isDisabled != isActive else { return }
        if system.setSleepDisabled(isActive), !isActive, lastError?.hasPrefix("La veille normale") == true {
            lastError = nil
        }
    }

    private func notify(_ title: String, _ body: String) {
        if settings.notifications { Notifier.post(title, body) }
    }

    // MARK: Surviving a relaunch

    /// Call before the app quits to update itself: the running session picks up where it left off.
    func rememberSessionForRelaunch() {
        guard isActive, let trigger else { return }
        defaults.set(trigger.rawValue, forKey: Key.resumeTrigger)
        defaults.set(endsAt, forKey: Key.resumeEndsAt)
    }

    private func resumeSessionAfterRelaunch() {
        defer {
            defaults.removeObject(forKey: Key.resumeTrigger)
            defaults.removeObject(forKey: Key.resumeEndsAt)
        }
        guard let trigger = defaults.string(forKey: Key.resumeTrigger).flatMap(Trigger.init(rawValue:)) else { return }
        let endsAt = defaults.object(forKey: Key.resumeEndsAt) as? Date
        if let endsAt, endsAt <= now { return }
        activate(for: endsAt?.timeIntervalSince(now), trigger: trigger)
    }

    // MARK: Authorization and login item

    func installAuthorization() {
        lastError = system.installAuthorization()
        isAuthorized = system.isAuthorized()
    }

    func removeAuthorization() {
        deactivate()
        lastError = system.removeAuthorization()
        isAuthorized = system.isAuthorized()
    }

    func setLaunchesAtLogin(_ enabled: Bool) {
        do {
            try system.setLaunchesAtLogin(enabled)
        } catch {
            lastError = "Ouverture de session : \(error.localizedDescription)"
        }
        launchesAtLogin = system.launchesAtLogin()
    }

    // MARK: Preview

    /// Shows a running session in snapshots. It goes through the normal path, on a `SystemControl` that does nothing.
    func previewSetActive(_ active: Bool) {
        if active {
            activate(for: nil, trigger: .auto)
            startedAt = Date().addingTimeInterval(-5_040)
        } else {
            deactivate()
        }
    }
}
