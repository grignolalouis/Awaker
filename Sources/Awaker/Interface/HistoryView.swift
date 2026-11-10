import AwakerCore
import SwiftUI

/// Every awake session, newest first.
struct HistoryView: View {
    private enum Filter: Hashable {
        case all
        case only(Trigger)
    }

    @Environment(AwakeController.self) private var awake
    @Environment(HistoryStore.self) private var history
    @State private var filter: Filter = .all
    @State private var isConfirmingClear = false

    /// Width of the leading icon plus its gap, so separators start under the text.
    private let iconColumn: CGFloat = 32

    var body: some View {
        VStack(spacing: 12) {
            HStack {
                Picker("Filtre", selection: $filter) {
                    Text("Toutes").tag(Filter.all)
                    Text("Manuelles").tag(Filter.only(.manual))
                    Text("Auto").tag(Filter.only(.auto))
                }
                .pickerStyle(.segmented)
                .labelsHidden()
                .fixedSize()
                Spacer()
                Text(summary)
                    .font(.callout)
                    .foregroundStyle(.secondary)
                    .monospacedDigit()
                Button("Effacer…", systemImage: "trash", role: .destructive) { isConfirmingClear = true }
                    .buttonStyle(.glass)
                    .disabled(history.sessions.isEmpty)
            }
            if sessions.isEmpty {
                ContentUnavailableView("Aucune session", systemImage: "clock",
                                       description: Text("Chaque session apparaîtra ici avec sa durée et sa raison d'arrêt."))
                    .glassEffect(in: .rect(cornerRadius: PanelMetrics.radius))
            } else {
                GlassPanel {
                    PanelRows(items: sessions, leadingColumn: iconColumn) { session in
                        SessionRow(session: session, now: awake.now, iconColumn: iconColumn)
                    }
                }
            }
        }
        .frame(maxWidth: PanelMetrics.maxWidth)
        .frame(maxHeight: .infinity, alignment: .top)
        .padding()
        .confirmationDialog("Effacer l'historique ?", isPresented: $isConfirmingClear) {
            Button("Tout effacer", role: .destructive) { history.clear() }
        } message: {
            Text("Les sessions terminées seront supprimées. La session en cours est conservée.")
        }
    }

    /// Newest first, filtered by trigger.
    private var sessions: [AwakeSession] {
        let all = history.sessions.sorted { $0.start > $1.start }
        switch filter {
        case .all: return all
        case .only(let trigger): return all.filter { $0.trigger == trigger }
        }
    }

    private var summary: String {
        let total = history.sessions.totalAwakeTime(now: awake.now)
        return "\(Format.plural(history.sessions.count, "session", "sessions")) · \(Format.duration(total))"
    }
}

private struct SessionRow: View {
    let session: AwakeSession
    let now: Date
    let iconColumn: CGFloat

    var body: some View {
        HStack(spacing: 0) {
            Image(systemName: session.trigger == .auto ? "sparkles" : "power")
                .foregroundStyle(.secondary)
                .frame(width: iconColumn, alignment: .leading)
            VStack(alignment: .leading, spacing: 2) {
                Text(title)
                Text(subtitle)
                    .font(.callout)
                    .foregroundStyle(.secondary)
            }
            .lineLimit(1)
            Spacer(minLength: 12)
            if session.isRunning {
                Image(systemName: "circle.fill")
                    .font(.caption2)
                    .foregroundStyle(.green)
                    .padding(.trailing, 8)
            }
            Text(Format.duration(session.duration(now: now)))
                .fontWeight(.medium)
                .monospacedDigit()
        }
    }

    private var title: String {
        let start = "\(Format.day(session.start)), \(Format.time(session.start))"
        guard let end = session.end else { return "\(start) → en cours" }
        return "\(start) – \(Format.time(end))"
    }

    private var subtitle: String {
        var parts = [session.trigger.label]
        if let reason = session.endReason { parts.append(reason.label) }
        if let start = session.startBattery, let end = session.endBattery { parts.append("batterie \(start) → \(end) %") }
        return parts.joined(separator: " · ")
    }
}
