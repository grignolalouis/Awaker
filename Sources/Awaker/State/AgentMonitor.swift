import AppKit
import AwakerCore
import Observation

/// Follows the running Claude Code sessions, tells the user when one finishes or needs them,
/// and sums up what happened while they were away.
///
/// It reads the files Claude Code keeps in `~/.claude` every couple of seconds. Those are internal
/// formats: if they change, the list goes empty rather than wrong.
@MainActor
@Observable
final class AgentMonitor {
    private(set) var agents: [AgentSession] = []
    /// What happened while the screen was off. Shown until the user dismisses it.
    private(set) var recap: AwayRecap?

    @ObservationIgnored private let reader = AgentSessionReader()
    @ObservationIgnored private let settings: AppSettings
    @ObservationIgnored private var timer: Timer?
    /// What each transcript said, with the date it was read at, so big transcripts aren't re-read needlessly.
    @ObservationIgnored private var cache: [String: CachedDetails] = [:]
    /// False until the first read: sessions found at launch must not trigger notifications.
    @ObservationIgnored private var hasBaseline = false
    /// When the screen went off (lid closed, display asleep). Nil while the user is there.
    @ObservationIgnored private var leftAt: Date?
    @ObservationIgnored private var observers: [NSObjectProtocol] = []

    private let pollInterval: TimeInterval = 2
    /// Shorter absences don't deserve a recap.
    private let minimumAbsence: TimeInterval = 5 * 60

    private struct CachedDetails: Sendable {
        var modified: Date
        var details: AgentDetails
        /// The one-off search for the last recorded cost has been done.
        var searchedCost: Bool
    }

    init(settings: AppSettings) {
        self.settings = settings
    }

    /// Fixed sessions for previews and snapshots.
    init(settings: AppSettings, preview agents: [AgentSession], recap: AwayRecap? = nil) {
        self.settings = settings
        self.agents = agents.sortedForDisplay()
        self.recap = recap
        hasBaseline = true
    }

    var waitingCount: Int { agents.filter(\.state.needsUser).count }
    /// Agents whose work a sleeping Mac would stop.
    var busyCount: Int { agents.filter(\.state.keepsMacBusy).count }
    /// API-equivalent cost of the running sessions, where Claude Code recorded one.
    var totalDollars: Double { agents.compactMap(\.details.cost?.dollars).reduce(0, +) }

    /// Call once at launch.
    func start() {
        let timer = Timer(timeInterval: pollInterval, repeats: true) { [weak self] _ in
            Task { @MainActor in await self?.refresh() }
        }
        RunLoop.main.add(timer, forMode: .common)
        self.timer = timer
        watchPresence()
        Task { await refresh() }
    }

    func dismissRecap() {
        recap = nil
    }

    // MARK: Reading

    private func refresh() async {
        let reader = reader
        let known = cache
        // File reads happen off the main thread; transcripts can be large.
        let (sessions, newCache) = await Task.detached(priority: .utility) {
            var cache = known
            let sessions = reader.sessions().map { session -> AgentSession in
                var session = session
                session.details = Self.details(of: session, reader: reader, cache: &cache)
                return session
            }
            return (sessions, cache.filter { entry in sessions.contains { $0.id == entry.key } })
        }.value

        if hasBaseline && leftAt == nil { notifyChanges(from: agents, to: sessions) }
        cache = newCache
        agents = sessions.sortedForDisplay()
        hasBaseline = true
    }

    /// The session's details, re-read only when its transcript changed.
    private nonisolated static func details(of session: AgentSession, reader: AgentSessionReader,
                                            cache: inout [String: CachedDetails]) -> AgentDetails {
        let cached = cache[session.id]
        guard let transcript = reader.transcript(of: session) else { return cached?.details ?? AgentDetails() }
        let modified = (try? transcript.resourceValues(forKeys: [.contentModificationDateKey]))?.contentModificationDate ?? .distantPast
        if let cached, cached.modified == modified { return cached.details }

        var details = reader.details(in: transcript).filling(from: cached?.details ?? AgentDetails())
        var searchedCost = cached?.searchedCost ?? false
        if details.cost == nil && !searchedCost {
            details.cost = reader.lastCost(in: transcript)
            searchedCost = true
        }
        cache[session.id] = CachedDetails(modified: modified, details: details, searchedCost: searchedCost)
        return details
    }

    // MARK: Notifications

    private func notifyChanges(from old: [AgentSession], to new: [AgentSession]) {
        guard settings.agentNotifications else { return }
        for agent in new {
            guard let before = old.first(where: { $0.id == agent.id })?.state, before != agent.state else { continue }
            switch agent.state {
            case .waiting:
                Notifier.post("\(agent.displayTitle) a besoin de toi", "\(Self.request(of: agent)) Projet \(agent.projectName).")
            case .finished where before == .working, .background where before == .working:
                Notifier.post("\(agent.displayTitle) a terminé", agent.details.lastReply ?? "À toi de jouer. Projet \(agent.projectName).")
            default:
                break
            }
        }
    }

    /// What a waiting agent is asking for, as precisely as the files allow.
    static func request(of agent: AgentSession) -> String {
        guard case .waiting(let tool) = agent.state else { return "" }
        if let action = agent.details.pendingAction { return "Il demande ton accord pour : \(action)." }
        if let tool { return "Il demande ton accord pour : \(tool)." }
        return "Il attend ta réponse."
    }

    // MARK: Presence

    /// With sleep disabled the Mac never "sleeps", so absence is read from the screen: off when the lid
    /// closes or the display sleeps, on again when the user is back.
    private func watchPresence() {
        let center = NSWorkspace.shared.notificationCenter
        let left = [NSWorkspace.screensDidSleepNotification, NSWorkspace.willSleepNotification]
        let back = [NSWorkspace.screensDidWakeNotification, NSWorkspace.didWakeNotification]
        for name in left {
            observers.append(center.addObserver(forName: name, object: nil, queue: .main) { [weak self] _ in
                MainActor.assumeIsolated { self?.userLeft() }
            })
        }
        for name in back {
            observers.append(center.addObserver(forName: name, object: nil, queue: .main) { [weak self] _ in
                MainActor.assumeIsolated { self?.userCameBack() }
            })
        }
    }

    private func userLeft() {
        if leftAt == nil { leftAt = Date() }
    }

    private func userCameBack() {
        guard let leftAt else { return }
        self.leftAt = nil
        Task {
            // The files may have changed while nobody was looking: read them before summing up.
            await refresh()
            let now = Date()
            guard now.timeIntervalSince(leftAt) >= minimumAbsence,
                  let recap = AwayRecap(agents: agents, leftAt: leftAt, now: now) else { return }
            self.recap = recap
            if settings.agentNotifications {
                Notifier.post("Pendant ton absence (\(Format.duration(recap.duration)))", recap.sentence)
            }
        }
    }
}

/// Brings the user to an agent: the app hosting its terminal, or its folder when that app can't be found.
@MainActor
enum AgentJumper {
    static func jump(to agent: AgentSession) {
        var pid: Int32? = agent.pid
        // Walk up from the CLI to the first regular app: Terminal, iTerm, an editor…
        while let current = pid {
            if let app = NSRunningApplication(processIdentifier: current), app.activationPolicy == .regular {
                app.activate()
                return
            }
            pid = ProcessTree.parent(of: current)
        }
        NSWorkspace.shared.open(agent.directory)
    }
}
