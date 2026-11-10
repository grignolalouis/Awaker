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
        var text = "Awake for \(Format.duration(awake.now.timeIntervalSince(start)))"
        if let end = awake.endsAt { text += " · until \(Format.time(end))" }
        if awake.trigger == .auto { text += " · auto" }
        return text
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

    /// The icon, then what matters most: how many agents wait for you, else the session's duration.
    @ViewBuilder private var label: some View {
        let icon = Image(nsImage: awake.isActive ? Brand.menuBarActive : Brand.menuBarInactive)
        if monitor.waitingCount > 0 {
            Text("\(icon) ✋\(monitor.waitingCount)")
        } else if settings.showElapsedInMenuBar, let start = awake.startedAt {
            Text("\(icon) \(Format.clock(awake.now.timeIntervalSince(start)))")
        } else {
            icon
        }
    }
}
