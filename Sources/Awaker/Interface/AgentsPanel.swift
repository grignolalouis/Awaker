import AwakerCore
import SwiftUI

/// The running Claude Code sessions, in a glass panel: who needs you, who is working, who is done.
/// A row opens to show the last exchange, the cost, and how to get to that agent.
struct AgentsPanel: View {
    @Environment(AgentMonitor.self) private var monitor
    @State private var expandedID: String? = AppEnvironment.shared.isSnapshot ? DemoData.expandedAgent : nil

    /// Width of the avatar plus its gap, so separators and details start under the text.
    private let avatarColumn: CGFloat = 44
    /// Agents that finished longer ago than this are folded into one line: they are yesterday's news.
    private let recentWindow: TimeInterval = 6 * 3_600

    var body: some View {
        // The clock drives the "3 min ago" labels and the fold between recent and old agents.
        TimelineView(.periodic(from: .now, by: 30)) { timeline in
            let (recent, older) = split(monitor.agents, now: timeline.date)
            GlassPanel {
                VStack(spacing: 0) {
                    PanelRows(items: recent, leadingColumn: avatarColumn) { agent in
                        AgentRow(agent: agent, now: timeline.date, avatarColumn: avatarColumn, isExpanded: agent.id == expandedID) {
                            withAnimation(.spring(duration: 0.3)) { expandedID = agent.id == expandedID ? nil : agent.id }
                        }
                    }
                    if older > 0 || monitor.totalDollars > 0 {
                        if !recent.isEmpty { PanelDivider(leadingColumn: avatarColumn) }
                        footer(older: older)
                            .padding(.leading, PanelMetrics.rowInset + avatarColumn)
                            .padding(.trailing, PanelMetrics.rowInset)
                            .padding(.vertical, PanelMetrics.rowPadding)
                    }
                }
            }
        }
    }

    private func footer(older: Int) -> some View {
        HStack {
            if older > 0 {
                Text(Format.plural(older, "other agent idle", "other agents idle"))
            }
            Spacer()
            if monitor.totalDollars > 0 {
                Text("Total ≈ \(Format.dollars(monitor.totalDollars))")
                    .monospacedDigit()
                    .help("API-equivalent cost of the open sessions, as last recorded by Claude Code.")
            }
        }
        .font(.callout)
        .foregroundStyle(.secondary)
    }

    /// Agents worth a row (anything going on, or finished recently), and how many older ones are left.
    private func split(_ agents: [AgentSession], now: Date) -> (recent: [AgentSession], older: Int) {
        let recent = agents.filter {
            $0.state.isActive || !$0.subagents.isEmpty || !$0.commands.isEmpty || now.timeIntervalSince($0.stateSince) < recentWindow
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
            .accessibilityHint(isExpanded ? "Collapse" : "Show details")
            if isExpanded {
                detail
                    .padding(.leading, avatarColumn)
                    .transition(.opacity)
            }
        }
    }

    private var summary: some View {
        HStack(spacing: 0) {
            AgentAvatar(pose: pose, seed: agent.id, companions: agent.subagents.count)
                .frame(width: avatarColumn, alignment: .leading)
            VStack(alignment: .leading, spacing: 2) {
                Text(agent.displayTitle)
                    .fontWeight(agent.state.needsUser ? .semibold : .regular)
                Text("\(agent.projectName) · \(agent.statusLabel)")
                    .font(.callout)
                    .foregroundStyle(.secondary)
                // While something is going on, say what: the command that runs, or what was asked.
                if !isExpanded, agent.state.isActive {
                    if agent.state == .background, let command = agent.commands.first {
                        Text(command.command)
                            .font(.callout.monospaced())
                            .foregroundStyle(.tertiary)
                    } else if let prompt = agent.details.lastPrompt {
                        Text("“\(prompt)”")
                            .font(.callout)
                            .foregroundStyle(.tertiary)
                    }
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
                DetailLine(label: "Asking", text: agent.requestDescription, lines: 3)
            }
            if let prompt = agent.details.lastPrompt {
                DetailLine(label: "Your request", text: prompt, lines: 3)
            }
            if let reply = agent.details.lastReply ?? agent.details.summary {
                DetailLine(label: "Its reply", text: reply, lines: 4)
            }
            if !agent.subagents.isEmpty {
                DetailList(label: Format.plural(agent.subagents.count, "sub-agent at work", "sub-agents at work"),
                           items: agent.subagents.map { (id: $0.id, text: $0.task, note: nil) })
            }
            if !agent.commands.isEmpty {
                DetailList(label: Format.plural(agent.commands.count, "command running", "commands running"),
                           items: agent.commands.map {
                               (id: String($0.id), text: $0.command, note: Format.duration(now.timeIntervalSince($0.startedAt)))
                           },
                           isCode: true)
            }
            if let cost = agent.details.cost {
                Text("≈ \(Format.dollars(cost.dollars)) · \(Format.duration(cost.modelTime)) of compute · +\(cost.linesAdded) −\(cost.linesRemoved) lines")
                    .font(.callout)
                    .monospacedDigit()
                    .foregroundStyle(.secondary)
                    .help("API-equivalent cost, as last recorded by Claude Code. On a subscription, this is not what you pay.")
            }
            HStack(spacing: 8) {
                Button("Go to Terminal", systemImage: "terminal") { AgentJumper.jump(to: agent) }
                Button("Open Folder", systemImage: "folder") { NSWorkspace.shared.open(agent.directory) }
            }
            .buttonStyle(.glass)
            .controlSize(.small)
        }
    }

    /// An agent that finished a while ago has gone to sleep.
    private var pose: AgentAvatar.Pose {
        switch agent.state {
        case .working, .background: .working
        case .waiting: .waiting
        case .finished: now.timeIntervalSince(agent.stateSince) > Self.dozeDelay ? .asleep : .standing
        }
    }

    private static let dozeDelay: TimeInterval = 10 * 60

    /// Green: something is running. Orange: needs you. Gray: nothing going on.
    private var dotColor: Color {
        switch agent.state {
        case .working, .background: .green
        case .waiting: .orange
        case .finished: .gray
        }
    }

    /// "for 3 min" while something is going on, "3 min ago" once it is over.
    private var elapsed: String {
        let duration = Format.duration(now.timeIntervalSince(agent.stateSince))
        return agent.state.isActive ? "for \(duration)" : "\(duration) ago"
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
            // Agents write Markdown: bold and code are shown as such, not as stars and backticks.
            // Not selectable: a selectable text seems to drop its line limit once clicked, and then runs over
            // the rows below (seen in use, not reproduced in snapshots).
            Text(Self.styled(text))
                .font(.callout)
                .lineLimit(lines)
                .fixedSize(horizontal: false, vertical: true)
        }
    }

    private static func styled(_ text: String) -> AttributedString {
        let options = AttributedString.MarkdownParsingOptions(interpretedSyntax: .inlineOnlyPreservingWhitespace)
        guard var styled = try? AttributedString(markdown: text, options: options) else { return AttributedString(text) }
        // Links stay plain text: an agent's reply can quote anything, and this panel only shows, it opens nothing.
        styled.link = nil
        return styled
    }
}

/// A small label over a short list: one line per item, with an optional note at the end of the line.
private struct DetailList: View {
    let label: String
    let items: [(id: String, text: String, note: String?)]
    var isCode = false

    /// Longer lists end with a count.
    private let shown = 4

    var body: some View {
        VStack(alignment: .leading, spacing: 2) {
            Text(label)
                .font(.caption)
                .foregroundStyle(.secondary)
            ForEach(items.prefix(shown), id: \.id) { item in
                HStack(spacing: 8) {
                    Text(item.text)
                        .font(isCode ? .callout.monospaced() : .callout)
                        .lineLimit(1)
                        .truncationMode(.middle)
                    if let note = item.note {
                        Spacer(minLength: 8)
                        Text(note)
                            .font(.callout)
                            .monospacedDigit()
                            .foregroundStyle(.secondary)
                    }
                }
            }
            if items.count > shown {
                Text("and \(items.count - shown) more")
                    .font(.callout)
                    .foregroundStyle(.secondary)
            }
        }
    }
}

/// What happened while the user was away: one glass line with a way to dismiss it.
struct RecapBanner: View {
    let recap: AwayRecap
    /// The recap in plain language, when the user's Claude Code writes one.
    var written: AgentMonitor.WrittenRecapState?
    let dismiss: () -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack(spacing: 10) {
                Image(systemName: "moon.zzz.fill")
                    .foregroundStyle(.secondary)
                Text("While you were away (\(Format.duration(recap.duration))): \(recap.sentence)")
                    .lineLimit(2)
                // Alone, the line stays a compact pill; with a written recap it heads a panel.
                if written != nil { Spacer(minLength: 0) }
                Button("Dismiss", systemImage: "xmark", action: dismiss)
                    .labelStyle(.iconOnly)
                    .buttonStyle(.plain)
                    .foregroundStyle(.secondary)
            }
            switch written {
            case .writing:
                HStack(spacing: 8) {
                    ProgressView().controlSize(.small)
                    Text("Claude Code is writing the recap…").foregroundStyle(.secondary)
                }
            case .written(let text):
                Divider()
                ForEach(WrittenRecap.lines(of: text)) { line in
                    VStack(alignment: .leading, spacing: 2) {
                        if let title = line.title {
                            Text(title).fontWeight(.semibold)
                        }
                        Text(line.text)
                            .foregroundStyle(line.title == nil ? .primary : .secondary)
                            .fixedSize(horizontal: false, vertical: true)
                    }
                }
            case .failed(let message):
                Text(message).foregroundStyle(.secondary)
            case nil:
                EmptyView()
            }
        }
        .font(.callout)
        .padding(.horizontal, 16)
        .padding(.vertical, written == nil ? 10 : 14)
        .glassEffect(in: .rect(cornerRadius: written == nil ? 22 : 18))
    }
}
