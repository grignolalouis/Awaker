import Foundation
import IOKit.pwr_mgt
import AwakerCore
import Observation
import ServiceManagement

/// Owns the "keep awake" state, the protections and the live machine readings.
@MainActor
@Observable
final class AwakeController {
    // Session state
    private(set) var isActive = false
    private(set) var trigger: Trigger?
    private(set) var startedAt: Date?
    private(set) var endsAt: Date?
    private(set) var isAuthorized = false
    private(set) var launchesAtLogin = false
    private(set) var lastError: String?

    // Live readings, refreshed every tick
    private(set) var now = Date()
    private(set) var battery: BatteryInfo?
    private(set) var thermal: ProcessInfo.ThermalState = .nominal

    @ObservationIgnored private let settings: AppSettings
    @ObservationIgnored private let history: HistoryStore
    @ObservationIgnored private let agents: AgentMonitor
    /// Preview mode never touches pmset, sudo or the login item.
    @ObservationIgnored private let isPreview: Bool

    @ObservationIgnored private var assertionID: IOPMAssertionID = 0
    @ObservationIgnored private var sessionID: UUID?
    @ObservationIgnored private var ticker: Timer?
    @ObservationIgnored private var tickCount = 0
    @ObservationIgnored private var claudeIdleTicks = 0
    @ObservationIgnored private var autoModeSuppressed = false

    private let tickInterval: TimeInterval = 30
    /// Consecutive ticks without any agent at work before an auto session ends (3 min).
    /// Long enough not to drop the session between two turns.
    private let claudeIdleTicksToStop = 6

    init(settings: AppSettings, history: HistoryStore, agents: AgentMonitor, isPreview: Bool = false) {
        self.settings = settings
        self.history = history
        self.agents = agents
        self.isPreview = isPreview
        // Read before the first scene renders: it decides whether the window opens at launch.
        // Previews show the app as it looks once set up.
        isAuthorized = isPreview || PowerService.isAuthorized
        launchesAtLogin = SMAppService.mainApp.status == .enabled
    }

    /// Running Claude Code sessions, whatever they are doing.
    var claudeSessionCount: Int { agents.agents.count }
    /// Agents whose work a sleeping Mac would stop. Auto mode follows these, not merely open sessions.
    private var busyAgentCount: Int { agents.busyCount }

    /// Call once at launch.
    func start() {
        if !isPreview {
            // A previous run that died while active leaves sleep disabled.
            if isAuthorized && PowerService.isSleepDisabled {
                PowerService.setSleepDisabled(false)
            }
            history.closeInterruptedSessions()
            scheduleTicker()
        }
        refresh()
    }

    // MARK: Activation

    func toggle() {
        if isActive {
            deactivate()
        } else {
            activate(for: settings.defaultDuration)
        }
    }

    @discardableResult
    func activate(for duration: TimeInterval?, trigger: Trigger = .manual) -> Bool {
        let isAutomatic = trigger == .claude
        if !isAutomatic { lastError = nil }

        if let reason = blockingReason() {
            if !isAutomatic { lastError = reason }
            return false
        }

        if !isActive {
            guard PowerService.setSleepDisabled(true) else {
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
        claudeIdleTicks = 0
        if isAutomatic {
            let count = Format.plural(busyAgentCount, "agent au travail", "agents au travail")
            notify("Mac maintenu éveillé", "\(count). Tu peux fermer le capot.")
        } else {
            autoModeSuppressed = false
        }
        return true
    }

    func deactivate(_ reason: EndReason = .manual) {
        guard isActive else { return }
        PowerService.setSleepDisabled(false)
        if assertionID != 0 {
            IOPMAssertionRelease(assertionID)
            assertionID = 0
        }
        if let sessionID {
            history.endSession(sessionID, battery: battery?.percent, reason: reason)
        }
        // A manual stop while Claude Code runs must not be undone by auto mode on the next tick.
        if reason == .manual && settings.claudeAutoMode && busyAgentCount > 0 {
            autoModeSuppressed = true
        }
        sessionID = nil
        isActive = false
        trigger = nil
        startedAt = nil
        endsAt = nil
        if reason.isAutomatic {
            notify("Veille normale rétablie", reason.label)
        }
    }

    private func blockingReason() -> String? {
        if !isAuthorized { return "Installe d'abord l'autorisation dans les réglages." }
        if let battery, !battery.onAC {
            if settings.acOnly { return "Branche le chargeur : l'option « secteur uniquement » est active." }
            if settings.batteryGuard && battery.percent <= settings.batteryThreshold {
                return "Batterie trop faible (\(battery.percent) %)."
            }
        }
        if settings.thermalGuard && thermal == .critical { return "Le Mac est trop chaud." }
        return nil
    }

    // MARK: Ticker

    private func scheduleTicker() {
        let timer = Timer(timeInterval: tickInterval, repeats: true) { [weak self] _ in
            Task { @MainActor in self?.tick() }
        }
        RunLoop.main.add(timer, forMode: .common)
        ticker = timer
    }

    private func refresh() {
        now = Date()
        battery = PowerService.battery()
        thermal = ProcessInfo.processInfo.thermalState
    }

    private func notify(_ title: String, _ body: String) {
        if settings.notifications { Notifier.post(title, body) }
    }

    private func tick() {
        refresh()
        tickCount += 1
        if tickCount.isMultiple(of: 2) {
            history.record(Sample(date: now, battery: battery?.percent, onAC: battery?.onAC ?? true,
                                  active: isActive, claudeSessions: claudeSessionCount))
        }
        if busyAgentCount == 0 { autoModeSuppressed = false }

        if isActive {
            enforceProtections()
        } else if settings.claudeAutoMode && busyAgentCount > 0 && !autoModeSuppressed {
            activate(for: nil, trigger: .claude)
        }
    }

    private func enforceProtections() {
        if let endsAt, now >= endsAt { return deactivate(.timer) }
        if let battery, !battery.onAC {
            if settings.acOnly { return deactivate(.unplugged) }
            if settings.batteryGuard && battery.percent <= settings.batteryThreshold { return deactivate(.battery) }
        }
        if settings.thermalGuard && thermal == .critical { return deactivate(.thermal) }
        if trigger == .claude {
            claudeIdleTicks = busyAgentCount == 0 ? claudeIdleTicks + 1 : 0
            if claudeIdleTicks >= claudeIdleTicksToStop { deactivate(.claudeIdle) }
        }
    }

    // MARK: Authorization and login item

    func installAuthorization() {
        lastError = PowerService.installAuthorization()
        isAuthorized = PowerService.isAuthorized
    }

    func removeAuthorization() {
        deactivate()
        lastError = PowerService.removeAuthorization()
        isAuthorized = PowerService.isAuthorized
    }

    func setLaunchesAtLogin(_ enabled: Bool) {
        guard !isPreview else { return }
        do {
            if enabled {
                try SMAppService.mainApp.register()
            } else {
                try SMAppService.mainApp.unregister()
            }
        } catch {
            lastError = "Ouverture de session : \(error.localizedDescription)"
        }
        launchesAtLogin = SMAppService.mainApp.status == .enabled
    }

    // MARK: Preview

    /// Fakes an active session for snapshots. No effect outside preview mode.
    func previewSetActive(_ active: Bool) {
        guard isPreview else { return }
        isActive = active
        trigger = active ? .claude : nil
        startedAt = active ? Date().addingTimeInterval(-5_040) : nil
        endsAt = nil
    }
}
