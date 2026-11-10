import AwakerCore
import Foundation
import Observation

/// The awake sessions, persisted as JSON. In-memory when `files` is nil (previews, snapshots).
@MainActor
@Observable
final class HistoryStore {
    private(set) var sessions: [AwakeSession]

    @ObservationIgnored private let files: JSONFileStore?
    private let fileName = "sessions.json"

    init(files: JSONFileStore) {
        self.files = files
        sessions = files.load([AwakeSession].self, from: fileName) ?? []
    }

    init(sessions: [AwakeSession]) {
        files = nil
        self.sessions = sessions
    }

    func startSession(trigger: Trigger, battery: Int?) -> UUID {
        let session = AwakeSession(start: Date(), trigger: trigger, startBattery: battery, lastSeen: Date())
        sessions.append(session)
        save()
        return session.id
    }

    /// Notes that a running session is still alive, so a crash can be dated afterwards.
    func heartbeat(_ id: UUID, battery: Int?) {
        guard let index = sessions.firstIndex(where: { $0.id == id }) else { return }
        sessions[index].lastSeen = Date()
        sessions[index].endBattery = battery
        save()
    }

    func endSession(_ id: UUID, battery: Int?, reason: EndReason) {
        guard let index = sessions.firstIndex(where: { $0.id == id }) else { return }
        sessions[index].end = Date()
        sessions[index].endBattery = battery
        sessions[index].endReason = reason
        save()
    }

    /// Sessions left open by a crash or a forced shutdown end where they were last seen alive.
    func closeInterruptedSessions() {
        guard sessions.contains(where: \.isRunning) else { return }
        sessions = sessions.map { $0.isRunning ? $0.closedAfterInterruption() : $0 }
        save()
    }

    /// Removes finished sessions. A running session is kept.
    func clear() {
        sessions.removeAll { !$0.isRunning }
        save()
    }

    private func save() {
        files?.save(sessions, to: fileName)
    }
}
