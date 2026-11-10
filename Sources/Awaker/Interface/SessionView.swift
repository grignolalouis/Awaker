import AwakerCore
import SwiftUI

/// The home screen: start or stop a session, see whether the Mac is ready, and follow the Claude Code agents.
struct SessionView: View {
    @Environment(AwakeController.self) private var awake
    @Environment(AppSettings.self) private var settings
    @Environment(AgentMonitor.self) private var monitor

    private let glassSpacing: CGFloat = 12
    private let agentsWidth: CGFloat = 560

    var body: some View {
        VStack(spacing: 28) {
            if awake.isActive, let start = awake.startedAt {
                timer(since: start)
            }
            GlassEffectContainer(spacing: glassSpacing) {
                VStack(spacing: glassSpacing) {
                    controls
                    ReadinessPill()
                    if let error = awake.lastError {
                        Label(error, systemImage: "exclamationmark.triangle.fill")
                            .symbolRenderingMode(.multicolor)
                            .padding(.horizontal, 16)
                            .padding(.vertical, 10)
                            .glassEffect()
                    }
                }
            }
            if let recap = monitor.recap {
                RecapBanner(recap: recap) { monitor.dismissRecap() }
            }
            if !monitor.agents.isEmpty {
                AgentsPanel()
                    .frame(maxWidth: agentsWidth)
            }
        }
        .padding()
        .animation(.spring(duration: 0.35), value: awake.isActive)
    }

    private func timer(since start: Date) -> some View {
        VStack(spacing: 4) {
            Text(start, style: .timer)
                .font(.system(size: 64, weight: .semibold, design: .rounded))
                .monospacedDigit()
            Text(until)
                .font(.title3.weight(.medium))
        }
        .shadow(color: .black.opacity(0.35), radius: 12, y: 2)
    }

    private var until: String {
        if let end = awake.endsAt { return "Jusqu'à \(Format.time(end))" }
        return awake.trigger == .claude ? "Tant que Claude Code tourne" : "Sans limite"
    }

    @ViewBuilder private var controls: some View {
        @Bindable var settings = settings
        if !awake.isAuthorized {
            Button("Installer l'autorisation…", systemImage: "key.fill") { awake.installAuthorization() }
                .buttonStyle(.glassProminent)
                .controlSize(.extraLarge)
        } else if awake.isActive {
            Button("Arrêter la session", systemImage: "stop.fill") { awake.deactivate() }
                .buttonStyle(.glass)
                .controlSize(.extraLarge)
                .keyboardShortcut(.space, modifiers: [])
        } else {
            HStack(spacing: glassSpacing) {
                Button("Lancer la session", systemImage: "play.fill") { awake.activate(for: settings.defaultDuration) }
                    .buttonStyle(.glassProminent)
                    .keyboardShortcut(.space, modifiers: [])
                Menu {
                    Picker("Durée", selection: $settings.defaultMinutes) {
                        ForEach(AppSettings.durationChoices, id: \.minutes) { Text($0.label).tag($0.minutes) }
                    }
                    .pickerStyle(.inline)
                } label: {
                    Label(durationLabel, systemImage: "timer")
                        .padding(.horizontal, 16)
                        .padding(.vertical, 10)
                        .contentShape(Capsule())
                }
                .menuStyle(.button)
                .buttonStyle(.plain)
                .menuIndicator(.hidden)
                .fixedSize()
                .glassEffect(.regular.interactive())
                .help("Durée de la session")
            }
            .controlSize(.extraLarge)
        }
    }

    private var durationLabel: String {
        AppSettings.durationChoices.first { $0.minutes == settings.defaultMinutes }?.label ?? "Illimité"
    }
}

/// One glass pill, three facts: authorization, power, Claude Code. Each reflects the live state.
private struct ReadinessPill: View {
    @Environment(AwakeController.self) private var awake
    @Environment(AppSettings.self) private var settings
    @Environment(AgentMonitor.self) private var monitor

    var body: some View {
        HStack(spacing: 18) {
            ForEach(Readiness(awake: awake, settings: settings, agents: monitor.agents).checks) { check in
                Label {
                    Text(check.text)
                } icon: {
                    Image(systemName: check.state.symbol)
                        .foregroundStyle(check.state.color)
                }
                .lineLimit(1)
            }
        }
        .font(.callout)
        .padding(.horizontal, 18)
        .padding(.vertical, 11)
        .glassEffect()
    }
}

/// What a session needs, read from the live state. Text always describes the current situation.
@MainActor
struct Readiness {
    enum State {
        case ready, waiting, blocked

        var symbol: String {
            switch self {
            case .ready: "checkmark.circle.fill"
            case .waiting: "circle.dashed"
            case .blocked: "exclamationmark.circle.fill"
            }
        }

        var color: Color {
            switch self {
            case .ready: .green
            case .waiting: .secondary
            case .blocked: .orange
            }
        }
    }

    struct Check: Identifiable {
        let id: String
        let state: State
        let text: String
    }

    let awake: AwakeController
    let settings: AppSettings
    let agents: [AgentSession]

    var checks: [Check] { [authorization, power, claude] }

    private var authorization: Check {
        awake.isAuthorized
            ? Check(id: "authorization", state: .ready, text: "Autorisé")
            : Check(id: "authorization", state: .blocked, text: "Autorisation requise")
    }

    private var power: Check {
        guard let battery = awake.battery else {
            return Check(id: "power", state: .ready, text: "Sur secteur")
        }
        if battery.onAC {
            return Check(id: "power", state: .ready, text: "Secteur · \(battery.percent) %")
        }
        let isBlocked = settings.acOnly || (settings.batteryGuard && battery.percent <= settings.batteryThreshold)
        return Check(id: "power", state: isBlocked ? .blocked : .ready, text: "Batterie · \(battery.percent) %")
    }

    /// The headline about the agents: someone waiting for you beats everything else.
    private var claude: Check {
        let waiting = agents.filter(\.state.needsUser).count
        let working = agents.filter { $0.state == .working }.count
        if waiting > 0 {
            return Check(id: "claude", state: .blocked, text: Format.plural(waiting, "agent t'attend", "agents t'attendent"))
        }
        if working > 0 {
            return Check(id: "claude", state: .ready, text: Format.plural(working, "agent au travail", "agents au travail"))
        }
        guard !agents.isEmpty else {
            return Check(id: "claude", state: .waiting, text: "Aucune session Claude Code")
        }
        return Check(id: "claude", state: .waiting, text: Format.plural(agents.count, "session au repos", "sessions au repos"))
    }
}
