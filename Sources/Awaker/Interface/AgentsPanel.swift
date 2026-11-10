import AwakerCore
import SwiftUI

/// The running Claude Code sessions, in a glass panel: who needs you, who is working, who is done.
/// A row opens to show the last exchange, the cost, and how to get to that agent.
struct AgentsPanel: View {
    @Environment(AgentMonitor.self) private var monitor
    /// Measured heights: the panel hugs its rows, and only fades its edges when the rows overflow it.
    @State private var contentHeight: CGFloat = 0
    @State private var viewportHeight: CGFloat = 0
    @State private var expandedID: String?

    private let panelRadius: CGFloat = 24
    private let rowInset: CGFloat = 18
    /// Width of the avatar plus its gap, so separators and details start under the text.
    private let avatarColumn: CGFloat = 44
    /// Sessions that finished longer ago than this are folded into one line: they are yesterday's news.
    private let recentWindow: TimeInterval = 6 * 3_600

    var body: some View {
        // The clock drives the "il y a 3 min" labels and the fold between recent and old sessions.
        TimelineView(.periodic(from: .now, by: 30)) { timeline in
            let (recent, older) = split(monitor.agents, now: timeline.date)
            let rows = VStack(spacing: 0) {
                ForEach(Array(recent.enumerated()), id: \.element.id) { index, agent in
                    if index > 0 { Divider().padding(.leading, rowInset + avatarColumn) }
                    AgentRow(agent: agent, now: timeline.date, avatarColumn: avatarColumn, isExpanded: agent.id == expandedID) {
                        withAnimation(.spring(duration: 0.3)) { expandedID = agent.id == expandedID ? nil : agent.id }
                    }
                    .padding(.horizontal, rowInset)
                    .padding(.vertical, 10)
                }
                if older > 0 || monitor.totalDollars > 0 {
                    if !recent.isEmpty { Divider().padding(.leading, rowInset + avatarColumn) }
                    footer(older: older)
                        .padding(.leading, rowInset + avatarColumn)
                        .padding(.trailing, rowInset)
                        .padding(.vertical, 10)
                }
            }
            .padding(.vertical, 6)
            // One scroll view in both cases. Measuring two candidate layouts (ViewThatFits) on every
            // avatar frame made SwiftUI lay out the whole window several times a second.
            ScrollView {
                rows.onGeometryChange(for: CGFloat.self) { $0.size.height } action: { contentHeight = $0 }
            }
            .scrollIndicators(.never)
            .frame(maxHeight: contentHeight > 0 ? contentHeight : nil)
            .onGeometryChange(for: CGFloat.self) { $0.size.height } action: { viewportHeight = $0 }
            .mask {
                if contentHeight > viewportHeight + 1 {
                    Self.edgeFade
                } else {
                    Rectangle()
                }
            }
            .glassEffect(in: .rect(cornerRadius: panelRadius))
        }
    }

    private func footer(older: Int) -> some View {
        HStack {
            if older > 0 {
                Text(Format.plural(older, "autre session au repos", "autres sessions au repos"))
            }
            Spacer()
            if monitor.totalDollars > 0 {
                Text("Total ≈ \(Format.dollars(monitor.totalDollars))")
                    .monospacedDigit()
                    .help("Coût équivalent API des sessions ouvertes, au dernier relevé de Claude Code.")
            }
        }
        .font(.callout)
        .foregroundStyle(.secondary)
    }

    /// Rows fade in and out at the top and bottom edges of the scrolling panel.
    private static let edgeFade = LinearGradient(
        stops: [.init(color: .clear, location: 0), .init(color: .black, location: 0.07),
                .init(color: .black, location: 0.86), .init(color: .clear, location: 1)],
        startPoint: .top, endPoint: .bottom
    )

    /// Sessions worth a row (anything active, or finished recently), and how many older ones are left.
    private func split(_ agents: [AgentSession], now: Date) -> (recent: [AgentSession], older: Int) {
        let recent = agents.filter { agent in
            switch agent.state {
            case .working, .waiting: true
            case .finished, .background: now.timeIntervalSince(agent.stateSince) < recentWindow
            }
        }
        return (recent, agents.count - recent.count)
    }
}

private struct AgentRow: View {
    let agent: AgentSession
    let now: Date
    let avatarColumn: CGFloat
    let isExpanded: Bool
    let toggle: () -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            Button(action: toggle) {
                summary.contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .accessibilityHint(isExpanded ? "Replier" : "Afficher le détail")
            if isExpanded {
                detail
                    .padding(.leading, avatarColumn)
                    .transition(.opacity)
            }
        }
    }

    private var summary: some View {
        HStack(spacing: 0) {
            AgentAvatar(state: agent.state, seed: agent.id)
                .frame(width: avatarColumn, alignment: .leading)
            VStack(alignment: .leading, spacing: 2) {
                Text(agent.displayTitle)
                    .fontWeight(agent.state.needsUser ? .semibold : .regular)
                Text("\(agent.projectName) · \(status)")
                    .font(.callout)
                    .foregroundStyle(.secondary)
                // While something is going on, say what was asked.
                if !isExpanded, isActive, let prompt = agent.details.lastPrompt {
                    Text("« \(prompt) »")
                        .font(.callout)
                        .foregroundStyle(.tertiary)
                }
            }
            .lineLimit(1)
            Spacer(minLength: 12)
            Circle()
                .fill(dotColor)
                .frame(width: 8, height: 8)
                .padding(.trailing, 8)
            Text(elapsed)
                .font(.callout)
                .monospacedDigit()
                .foregroundStyle(.secondary)
        }
        .accessibilityElement(children: .combine)
    }

    private var detail: some View {
        VStack(alignment: .leading, spacing: 10) {
            if agent.state.needsUser {
                DetailLine(label: "Il demande", text: AgentMonitor.request(of: agent), lines: 3)
            }
            if let prompt = agent.details.lastPrompt {
                DetailLine(label: "Ta demande", text: prompt, lines: 3)
            }
            if let reply = agent.details.lastReply ?? agent.details.summary {
                DetailLine(label: "Sa réponse", text: reply, lines: 4)
            }
            if let cost = agent.details.cost {
                Text("≈ \(Format.dollars(cost.dollars)) · \(Format.duration(cost.modelTime)) de calcul · +\(cost.linesAdded) −\(cost.linesRemoved) lignes")
                    .font(.callout)
                    .monospacedDigit()
                    .foregroundStyle(.secondary)
                    .help("Coût équivalent API, au dernier relevé de Claude Code. Sur un abonnement, ce n'est pas ce que tu paies.")
            }
            HStack(spacing: 8) {
                Button("Aller au terminal", systemImage: "terminal") { AgentJumper.jump(to: agent) }
                Button("Ouvrir le dossier", systemImage: "folder") { NSWorkspace.shared.open(agent.directory) }
            }
            .buttonStyle(.glass)
            .controlSize(.small)
        }
    }

    private var isActive: Bool {
        switch agent.state {
        case .working, .waiting: true
        case .finished, .background: false
        }
    }

    /// Green: at work. Orange: needs you. Gray: nothing going on.
    private var dotColor: Color {
        switch agent.state {
        case .working: .green
        case .waiting: .orange
        case .finished, .background: .gray
        }
    }

    private var status: String {
        switch agent.state {
        case .working: "Travaille"
        case .waiting(let tool): tool.map { "Demande ton accord : \($0)" } ?? "Attend ta réponse"
        case .finished: "A terminé"
        case .background: "Au repos, commande en arrière-plan"
        }
    }

    /// "depuis 3 min" while something is going on, "il y a 3 min" once it is over.
    private var elapsed: String {
        let duration = Format.duration(now.timeIntervalSince(agent.stateSince))
        return isActive ? "depuis \(duration)" : "il y a \(duration)"
    }
}

/// A small label over a few lines of text.
private struct DetailLine: View {
    let label: String
    let text: String
    let lines: Int

    var body: some View {
        VStack(alignment: .leading, spacing: 2) {
            Text(label)
                .font(.caption)
                .foregroundStyle(.secondary)
            Text(text)
                .font(.callout)
                .lineLimit(lines)
                .textSelection(.enabled)
        }
    }
}

/// What happened while the user was away: one glass line with a way to dismiss it.
struct RecapBanner: View {
    let recap: AwayRecap
    let dismiss: () -> Void

    var body: some View {
        HStack(spacing: 10) {
            Image(systemName: "moon.zzz.fill")
                .foregroundStyle(.secondary)
            Text("Pendant ton absence (\(Format.duration(recap.duration))) : \(recap.sentence)")
                .lineLimit(2)
            Button("Fermer", systemImage: "xmark", action: dismiss)
                .labelStyle(.iconOnly)
                .buttonStyle(.plain)
                .foregroundStyle(.secondary)
        }
        .font(.callout)
        .padding(.horizontal, 16)
        .padding(.vertical, 10)
        .glassEffect()
    }
}
