import Foundation
import AwakerCore
import Observation

/// Sessions and minute samples, persisted as JSON. In-memory when `files` is nil (previews, snapshots).
@MainActor
@Observable
final class HistoryStore {
    private(set) var sessions: [Session]
    private(set) var samples: [Sample]

    @ObservationIgnored private let files: JSONFileStore?
    @ObservationIgnored private var unsavedSamples = 0
    @ObservationIgnored private let retention: TimeInterval = 14 * 24 * 3600
    @ObservationIgnored private let samplesPerSave = 10

    private enum File {
        static let sessions = "sessions.json"
        static let samples = "samples.json"
    }

    init(files: JSONFileStore) {
        self.files = files
        sessions = files.load([Session].self, from: File.sessions) ?? []
        samples = files.load([Sample].self, from: File.samples) ?? []
        pruneSamples(before: Date().addingTimeInterval(-retention))
    }

    init(sessions: [Session], samples: [Sample]) {
        files = nil
        self.sessions = sessions
        self.samples = samples
    }

    func stats(now: Date) -> SessionStats {
        SessionStats(sessions: sessions, now: now)
    }

    func samples(since date: Date) -> [Sample] {
        samples.filter { $0.date >= date }
    }

    // MARK: Sessions

    func startSession(trigger: Trigger, battery: Int?) -> UUID {
        let session = Session(start: Date(), trigger: trigger, startBattery: battery)
        sessions.append(session)
        saveSessions()
        return session.id
    }

    func endSession(_ id: UUID, battery: Int?, reason: EndReason) {
        guard let index = sessions.firstIndex(where: { $0.id == id }) else { return }
        sessions[index].end = Date()
        sessions[index].endBattery = battery
        sessions[index].endReason = reason
        saveSessions()
    }

    /// Sessions left open by a crash or a forced shutdown end at their last active sample.
    func closeInterruptedSessions() {
        var changed = false
        for index in sessions.indices where sessions[index].isRunning {
            let start = sessions[index].start
            let lastActive = samples.last { $0.active && $0.date >= start }
            sessions[index].end = lastActive?.date ?? start
            sessions[index].endBattery = lastActive?.battery
            sessions[index].endReason = .crash
            changed = true
        }
        if changed { saveSessions() }
    }

    /// Removes finished sessions and all samples. A running session is kept.
    func clear() {
        sessions.removeAll { !$0.isRunning }
        samples.removeAll()
        saveSessions()
        flush()
    }

    // MARK: Samples

    func record(_ sample: Sample) {
        samples.append(sample)
        pruneSamples(before: sample.date.addingTimeInterval(-retention))
        unsavedSamples += 1
        if unsavedSamples >= samplesPerSave { flush() }
    }

    func flush() {
        files?.save(samples, to: File.samples)
        unsavedSamples = 0
    }

    private func pruneSamples(before cutoff: Date) {
        if let first = samples.first, first.date < cutoff {
            samples.removeAll { $0.date < cutoff }
        }
    }

    private func saveSessions() {
        files?.save(sessions, to: File.sessions)
    }
}
