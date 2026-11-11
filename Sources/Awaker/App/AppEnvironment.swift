import AwakerCore
import Foundation

/// Builds the app's objects once and wires them together.
/// Snapshot mode swaps in demo data and a `SystemControl` that touches nothing.
@MainActor
final class AppEnvironment {
    static let shared = AppEnvironment()

    let settings: AppSettings
    let history: HistoryStore
    let agents: AgentMonitor
    let awake: AwakeController
    let updater: Updater
    /// Where snapshots are written. Nil when the app runs normally.
    let snapshotDirectory: URL?
    /// Snapshots show demo agents unless asked to show the real ones (reading them is harmless).
    let usesLiveAgents: Bool

    var isSnapshot: Bool { snapshotDirectory != nil }

    private init() {
        let environment = ProcessInfo.processInfo.environment
        snapshotDirectory = environment["AWAKER_SNAPSHOT"].map { URL(fileURLWithPath: $0, isDirectory: true) }
        let isSnapshot = snapshotDirectory != nil
        usesLiveAgents = !isSnapshot || environment["AWAKER_SNAPSHOT_LIVE"] != nil

        settings = AppSettings()
        history = isSnapshot ? HistoryStore(sessions: DemoData.sessions(now: Date())) : HistoryStore(files: .applicationSupport)
        agents = usesLiveAgents
            ? AgentMonitor(settings: settings, recapWriter: isSnapshot ? nil : .live)
            : AgentMonitor(settings: settings, preview: DemoData.agents(now: Date()), recap: DemoData.recap(now: Date()), written: DemoData.writtenRecap)
        awake = AwakeController(settings: settings, history: history, agents: agents, system: isSnapshot ? .inert : .live)
        updater = Updater(isPreview: isSnapshot)
        // An update relaunches the app: the running session must pick up where it left off.
        updater.willRelaunch = { [awake] in awake.rememberSessionForRelaunch() }
    }
}
