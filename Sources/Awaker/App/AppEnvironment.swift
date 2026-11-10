import Foundation
import AwakerCore

/// Builds the app's objects once. Snapshot mode swaps in demo data and disables system writes.
@MainActor
final class AppEnvironment {
    static let shared = AppEnvironment()

    let settings: AppSettings
    let history: HistoryStore
    let agents: AgentMonitor
    let awake: AwakeController
    let updater: Updater
    let snapshotDirectory: URL?

    var isSnapshot: Bool { snapshotDirectory != nil }
    var usesLiveAgents: Bool { !isSnapshot || ProcessInfo.processInfo.environment["AWAKER_SNAPSHOT_LIVE"] != nil }

    private init() {
        snapshotDirectory = ProcessInfo.processInfo.environment["AWAKER_SNAPSHOT"]
            .map { URL(fileURLWithPath: $0, isDirectory: true) }
        settings = AppSettings()
        if snapshotDirectory != nil {
            let demo = DemoData.make(now: Date())
            history = HistoryStore(sessions: demo.sessions, samples: demo.samples)
            // AWAKER_SNAPSHOT_LIVE=1 shows the real Claude Code sessions in snapshots (reading them is harmless).
            let showsLiveAgents = ProcessInfo.processInfo.environment["AWAKER_SNAPSHOT_LIVE"] != nil
            agents = showsLiveAgents ? AgentMonitor(settings: settings) : AgentMonitor(settings: settings, preview: DemoData.agents(now: Date()),
                                                                               recap: DemoData.recap(now: Date()))
        } else {
            history = HistoryStore(files: .applicationSupport)
            agents = AgentMonitor(settings: settings)
        }
        updater = Updater(isPreview: snapshotDirectory != nil)
        awake = AwakeController(settings: settings, history: history, agents: agents, isPreview: snapshotDirectory != nil)
    }
}
