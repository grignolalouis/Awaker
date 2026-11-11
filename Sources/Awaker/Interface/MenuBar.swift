import AwakerCore
import SwiftUI

/// The menu bar menu: status, the agents that need attention, start or stop, duration, auto mode.
struct MenuBarContent: View {
    @Environment(AwakeController.self) private var awake
    @Environment(AppSettings.self) private var settings
    @Environment(AgentMonitor.self) private var monitor
    @Environment(Updater.self) private var updater

    /// Agents listed in the menu: the ones that need you, then the ones at work.
    private let listedAgents = 6

    var body: some View {
        @Bindable var settings = settings
        Text(status)
        if let reason = awake.reason {
            Text(reason.sentence())
        }
        if let error = awake.lastError {
            Text("⚠️ \(error)")
        }
        let active = monitor.agents.filter(\.state.isActive).prefix(listedAgents)
        if !active.isEmpty {
            Divider()
            ForEach(Array(active)) { agent in
                Button("\(agent.state.needsUser ? "✋" : "⚙️") \(agent.displayTitle) · \(agent.projectName)") {
                    AgentJumper.jump(to: agent)
                }
            }
        }
        Divider()
        if awake.isAuthorized {
            Button(awake.isActive ? "Stop session" : "Start Session (\(settings.defaultDurationLabel.lowercased()))") { awake.toggle() }
                .keyboardShortcut("a")
            Menu("Start For…") {
                ForEach(AppSettings.durationChoices, id: \.minutes) { choice in
                    Button(choice.label) {
                        awake.activate(for: AppSettings.duration(minutes: choice.minutes))
                    }
                }
            }
            Toggle("Auto Mode", isOn: $settings.autoMode)
        } else {
            Button("Install authorization…") { awake.installAuthorization() }
        }
        Divider()
        if let release = updater.availableRelease {
            Button("Install Awaker \(release.version)…") { Task { await updater.install(release) } }
        }
        Button("Open Awaker…") { WindowOpener.shared.open() }
            .keyboardShortcut(",")
        Button("Quit") { NSApp.terminate(nil) }
            .keyboardShortcut("q")
    }

    private var status: String {
        guard awake.isActive, let start = awake.startedAt else {
            return "Idle · \(Format.plural(monitor.busyCount, "agent working", "agents working"))"
        }
        return "Awake for \(Format.duration(awake.now.timeIntervalSince(start)))"
    }
}

struct MenuBarLabel: View {
    let awake: AwakeController
    let settings: AppSettings
    let monitor: AgentMonitor
    @Environment(\.openWindow) private var openWindow

    var body: some View {
        label.onAppear { WindowOpener.shared.register(openWindow) }
    }

    /// The icon, a green dot while the Mac is kept awake, and how many agents wait for you.
    @ViewBuilder private var label: some View {
        let icon = Image(nsImage: awake.isActive ? Brand.menuBarActive : Brand.menuBarInactive)
        if monitor.waitingCount > 0 {
            // Side by side rather than inside one Text: a colored image placed in a Text vanished from the menu bar.
            HStack(spacing: 4) {
                icon
                Text("✋\(monitor.waitingCount)")
            }
        } else {
            icon
        }
    }
}
