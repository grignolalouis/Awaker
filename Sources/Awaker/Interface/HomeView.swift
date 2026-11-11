import AwakerCore
import SwiftUI

/// The home screen: start or stop keeping the Mac awake, see whether it is ready, and follow the agents.
struct HomeView: View {
    @Environment(AwakeController.self) private var awake
    @Environment(AgentMonitor.self) private var monitor
    @Environment(Updater.self) private var updater

    private let glassSpacing: CGFloat = 12
    private let agentsWidth: CGFloat = 680

    var body: some View {
        VStack(spacing: 28) {
            if awake.isActive, let start = awake.startedAt {
                SessionTimer(start: start)
            }
            GlassEffectContainer(spacing: glassSpacing) {
                VStack(spacing: glassSpacing) {
                    SessionControls(spacing: glassSpacing)
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
            if let release = updater.bannerRelease {
                UpdateBanner(release: release, install: { Task { await updater.install(release) } }) {
                    withAnimation { updater.dismissBanner() }
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
}

/// How long the Mac has been kept awake, and why.
private struct SessionTimer: View {
    let start: Date
    @Environment(AwakeController.self) private var awake

    var body: some View {
        VStack(spacing: 4) {
            Text(start, style: .timer)
                .font(.system(size: 64, weight: .semibold, design: .rounded))
                .monospacedDigit()
            if let reason = awake.reason {
                Text(reason.sentence())
                    .font(.title3.weight(.medium))
                    .lineLimit(1)
                    .truncationMode(.middle)
            }
        }
        .shadow(color: .black.opacity(0.35), radius: 12, y: 2)
    }
}

/// The one action that matters: install the authorization, start, or stop.
private struct SessionControls: View {
    let spacing: CGFloat
    @Environment(AwakeController.self) private var awake
    @Environment(AppSettings.self) private var settings

    var body: some View {
        @Bindable var settings = settings
        if !awake.isAuthorized {
            Button("Install authorization…", systemImage: "key.fill") { awake.installAuthorization() }
                .buttonStyle(.glassProminent)
                .controlSize(.extraLarge)
        } else if awake.isActive {
            Button("Stop session", systemImage: "stop.fill") { awake.deactivate() }
                .buttonStyle(.glass)
                .controlSize(.extraLarge)
                .keyboardShortcut(.space, modifiers: [])
        } else {
            HStack(spacing: spacing) {
                Button("Start session", systemImage: "play.fill") { awake.activate(for: settings.defaultDuration) }
                    .buttonStyle(.glassProminent)
                    .keyboardShortcut(.space, modifiers: [])
                Menu {
                    Picker("Duration", selection: $settings.defaultMinutes) {
                        ForEach(AppSettings.durationChoices, id: \.minutes) { Text($0.label).tag($0.minutes) }
                    }
                    .pickerStyle(.inline)
                } label: {
                    Label(settings.defaultDurationLabel, systemImage: "timer")
                        .padding(.horizontal, 16)
                        .padding(.vertical, 10)
                        .contentShape(Capsule())
                }
                .menuStyle(.button)
                .buttonStyle(.plain)
                .menuIndicator(.hidden)
                .fixedSize()
                .glassEffect(.regular.interactive())
                .help("Session length")
            }
            .controlSize(.extraLarge)
        }
    }
}

/// One glass pill, three facts: authorization, power, agents. Each reflects the live state.
private struct ReadinessPill: View {
    @Environment(AwakeController.self) private var awake
    @Environment(AppSettings.self) private var settings
    @Environment(AgentMonitor.self) private var monitor

    var body: some View {
        HStack(spacing: 18) {
            fact(awake.isAuthorized ? .ready : .blocked, awake.isAuthorized ? "Authorized" : "Authorization needed")
            fact(powerLevel, powerText)
            fact(agentsLevel, agentsText)
        }
        .font(.callout)
        .padding(.horizontal, 18)
        .padding(.vertical, 11)
        .glassEffect()
    }

    private enum Level {
        case ready, quiet, blocked

        var symbol: String {
            switch self {
            case .ready: "checkmark.circle.fill"
            case .quiet: "circle.dashed"
            case .blocked: "exclamationmark.circle.fill"
            }
        }

        var color: Color {
            switch self {
            case .ready: .green
            case .quiet: .secondary
            case .blocked: .orange
            }
        }
    }

    private func fact(_ level: Level, _ text: String) -> some View {
        Label {
            Text(text)
        } icon: {
            Image(systemName: level.symbol).foregroundStyle(level.color)
        }
        .lineLimit(1)
    }

    /// Blocked exactly when the protections would refuse or stop a session: the same rule the controller applies.
    private var powerLevel: Level {
        settings.powerPolicy.blocker(battery: awake.battery, isThermalCritical: awake.isThermalCritical) == nil ? .ready : .blocked
    }

    private var powerText: String {
        if awake.isThermalCritical && settings.thermalGuard { return "Mac too hot" }
        guard let battery = awake.battery else { return "Plugged in" }
        return "\(battery.onAC ? "Plugged in" : "Battery") · \(battery.percent)%"
    }

    /// Someone waiting for you beats everything else.
    private var agentsLevel: Level {
        if monitor.waitingCount > 0 { return .blocked }
        return monitor.busyCount > 0 ? .ready : .quiet
    }

    private var agentsText: String {
        if monitor.waitingCount > 0 { return Format.plural(monitor.waitingCount, "agent needs you", "agents need you") }
        if monitor.busyCount > 0 { return Format.plural(monitor.busyCount, "agent working", "agents working") }
        return monitor.agents.isEmpty ? "No agents" : Format.plural(monitor.agents.count, "agent idle", "agents idle")
    }
}

/// A new version is available: one glass line to install it, or to close until the next one.
private struct UpdateBanner: View {
    let release: AppRelease
    let install: () -> Void
    let dismiss: () -> Void

    var body: some View {
        HStack(spacing: 10) {
            Image(systemName: "arrow.down.circle.fill")
                .foregroundStyle(.tint)
            Text("Awaker \(release.version) is available")
                .lineLimit(1)
            Button("Install", action: install)
                .buttonStyle(.glassProminent)
                .controlSize(.small)
                .help("Installing relaunches Awaker and stops the running session.")
            Button("Dismiss", systemImage: "xmark", action: dismiss)
                .labelStyle(.iconOnly)
                .buttonStyle(.plain)
                .foregroundStyle(.secondary)
                .help("Hide until the next version. The update stays available in Settings.")
        }
        .font(.callout)
        .padding(.horizontal, 16)
        .padding(.vertical, 8)
        .glassEffect()
    }
}
