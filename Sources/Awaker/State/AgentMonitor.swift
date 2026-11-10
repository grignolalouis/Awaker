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
    /// When the screen went off (lid closed, display asleep), and what the agents were doing then.
    /// Nil while the user is there.
    @ObservationIgnored private var absence: (since: Date, agents: [AgentSession])?
    /// A read is in flight. Reads can be slow (big transcripts); a second one must not start meanwhile,
    /// or the older could land last and overwrite newer states.
    @ObservationIgnored private var isRefreshing = false
    @ObservationIgnored private var observers: [NSObjectProtocol] = []

    private let pollInterval: TimeInterval = 2
    /// Sub-agents are looked up on disk (a folder listing and a few small reads per session) less often
    /// than the rest: they come and go over minutes, not seconds.
    private let subagentInterval: TimeInterval = 6
    @ObservationIgnored private var subagentsReadAt = Date.distantPast
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
        guard !isRefreshing else { return }
        isRefreshing = true
        defer { isRefreshing = false }

        let reader = reader
        let known = cache
        let readsSubagents = Date().timeIntervalSince(subagentsReadAt) >= subagentInterval
        if readsSubagents { subagentsReadAt = Date() }
        let knownSubagents = Dictionary(agents.map { ($0.id, $0.subagents) }, uniquingKeysWith: { first, _ in first })
        // File reads happen off the main thread; transcripts can be large.
        let (sessions, newCache) = await Task.detached(priority: .utility) {
            var cache = known
            let found = reader.sessions()
            let commands = AgentSessionReader.runningCommands(of: Set(found.map(\.pid)))
            let sessions = found.map { session -> AgentSession in
                var session = session
                let transcript = reader.transcript(of: session)
                session.details = Self.details(of: session, transcript: transcript, reader: reader, cache: &cache)
                session.subagents = readsSubagents
                    ? transcript.map { reader.subagents(besideTranscript: $0) } ?? []
                    : knownSubagents[session.id] ?? []
                session.commands = commands[session.pid] ?? []
                return session
            }
            return (sessions, cache.filter { entry in sessions.contains { $0.id == entry.key } })
        }.value

        // While the user is away, changes are held for the recap (or told on return).
        if hasBaseline && absence == nil { notifyChanges(from: agents, to: sessions) }
        cache = newCache
        agents = sessions.sortedForDisplay()
        hasBaseline = true
    }

    /// The session's details, re-read only when its transcript changed.
    private nonisolated static func details(of session: AgentSession, transcript: URL?, reader: AgentSessionReader,
                                            cache: inout [String: CachedDetails]) -> AgentDetails {
        let cached = cache[session.id]
        guard let transcript else { return cached?.details ?? AgentDetails() }
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
            guard let before = old.first(where: { $0.id == agent.id })?.state,
                  let notification = agent.notification(after: before) else { continue }
            Notifier.post(notification.title, notification.body)
        }
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
        if absence == nil { absence = (Date(), agents) }
    }

    private func userCameBack() {
        guard let absence else { return }
        self.absence = nil
        Task {
            // The files may have changed while nobody was looking: read them before summing up.
            await refresh()
            let now = Date()
            if now.timeIntervalSince(absence.since) >= minimumAbsence,
               let recap = AwayRecap(agents: agents, leftAt: absence.since, now: now) {
                self.recap = recap
                if settings.agentNotifications {
                    Notifier.post("While you were away (\(Format.duration(recap.duration)))", recap.sentence)
                }
            } else {
                // Too short for a recap: tell what changed meanwhile, as if the user had been there.
                notifyChanges(from: absence.agents, to: agents)
            }
        }
    }
}
