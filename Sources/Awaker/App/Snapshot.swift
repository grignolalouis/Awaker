import AppKit
import AwakerCore

/// Dev tool. `AWAKER_SNAPSHOT=<dir>` renders every screen to PNG, then exits. Captures can't show
/// Liquid Glass or the inside of scroll views: use them for layout and the backdrop only.
/// Runs on demo data and never touches pmset or the real history.
@MainActor
enum SnapshotRunner {
    static func run(show: @escaping (Screen) -> Void) async {
        let environment = AppEnvironment.shared
        guard let directory = environment.snapshotDirectory else { return }
        try? FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        await pause()
        window?.setFrame(NSRect(x: 0, y: 0, width: 880, height: 620), display: true)

        environment.awake.previewSetActive(false)
        show(.session)
        await pause()
        capture(directory, "1-session-idle")
        environment.awake.previewSetActive(true)
        await pause()
        capture(directory, "2-session-active")
        show(.history)
        await pause()
        capture(directory, "3-history")
        show(.settings)
        await pause()
        capture(directory, "4-settings")
        exit(0)
    }

    private static var window: NSWindow? {
        NSApp.windows.first { $0.isVisible && $0.frame.width > 400 }
    }

    private static func pause() async {
        try? await Task.sleep(for: .milliseconds(900))
    }

    /// Asks the window server for the window as it is composited on screen, Liquid Glass included.
    /// `CGWindowListCreateImage` is no longer in the SDK headers but still ships in CoreGraphics;
    /// capturing the app's own window needs no Screen Recording permission. Dev tool only.
    private static func capture(_ directory: URL, _ name: String) {
        typealias CreateImage = @convention(c) (CGRect, UInt32, UInt32, UInt32) -> Unmanaged<CGImage>?
        let includingWindow: UInt32 = 1 << 3
        let ignoreFraming: UInt32 = 1 << 0
        let currentProcess = UnsafeMutableRawPointer(bitPattern: -2)
        guard let window, let symbol = dlsym(currentProcess, "CGWindowListCreateImage") else { return }
        let createImage = unsafeBitCast(symbol, to: CreateImage.self)
        guard let image = createImage(.null, includingWindow, UInt32(window.windowNumber), ignoreFraming)?.takeRetainedValue() else {
            print("snapshot: the window server returned no image for \(name)")
            return
        }
        let bitmap = NSBitmapImageRep(cgImage: image)
        try? bitmap.representation(using: .png, properties: [:])?
            .write(to: directory.appendingPathComponent("\(name).png"))
    }
}

/// A plausible week of usage for snapshots.
enum DemoData {
    /// One session in each state, plus an old one that gets folded away.
    static func agents(now: Date) -> [AgentSession] {
        let dev = URL(fileURLWithPath: "/Users/demo/dev")
        func agent(_ id: String, _ folder: String, _ state: AgentState, secondsAgo: TimeInterval, _ details: AgentDetails) -> AgentSession {
            AgentSession(id: id, pid: 0, directory: dev.appendingPathComponent(folder), name: "\(folder)-\(id)", state: state,
                         stateSince: now.addingTimeInterval(-secondsAgo), details: details)
        }
        return [
            agent("a", "nexus", .waiting(tool: "Bash"), secondsAgo: 70, AgentDetails(
                title: "Migration des webhooks Stripe", lastPrompt: "pousse la branche et ouvre la PR",
                lastReply: "Les tests passent. Je pousse la branche.", pendingAction: "git push origin feat/stripe-webhooks",
                cost: AgentCost(dollars: 4.12, modelTime: 1_260, linesAdded: 212, linesRemoved: 40))),
            agent("b", "dashboard", .working, secondsAgo: 260, AgentDetails(
                title: "Refonte de l'écran Contacts", lastPrompt: "aligne le tableau sur la maquette et corrige le tri",
                cost: AgentCost(dollars: 11.8, modelTime: 3_900, linesAdded: 640, linesRemoved: 310))),
            agent("c", "dev", .finished, secondsAgo: 900, AgentDetails(
                title: "Collecteur HubSpot seats et plan", lastPrompt: "relance la review",
                lastReply: "La PR est verte et la review est redemandée.",
                cost: AgentCost(dollars: 26.49, modelTime: 3_631, linesAdded: 979, linesRemoved: 209))),
            agent("d", "extension", .background, secondsAgo: 3_100, AgentDetails(title: "Tests de bout en bout")),
            agent("e", "dev", .finished, secondsAgo: 90_000, AgentDetails(title: "Ancienne session")),
        ]
    }

    static func recap(now: Date) -> AwayRecap? {
        AwayRecap(agents: agents(now: now), leftAt: now.addingTimeInterval(-4_800), now: now)
    }

    static func make(now: Date, calendar: Calendar = .current) -> (sessions: [Session], samples: [Sample]) {
        let today = calendar.startOfDay(for: now)
        let plan: [(daysAgo: Int, hour: Double, hours: Double, trigger: Trigger, reason: EndReason)] = [
            (13, 10, 2.0, .manual, .manual), (12, 21, 3.0, .claude, .claudeIdle), (11, 9, 1.5, .manual, .timer),
            (10, 14, 2.6, .claude, .claudeIdle), (9, 22, 4.2, .claude, .claudeIdle), (8, 11, 1.0, .manual, .manual),
            (7, 13, 3.4, .claude, .claudeIdle), (6, 10, 2.5, .manual, .manual), (6, 21, 3.2, .claude, .claudeIdle),
            (5, 14, 1.0, .manual, .timer), (4, 9.5, 4.8, .claude, .claudeIdle), (3, 22.5, 6.5, .claude, .claudeIdle),
            (2, 13, 2.0, .manual, .manual), (1, 11, 3.4, .claude, .claudeIdle), (1, 23, 1.2, .manual, .battery),
            (0, 8.5, 1.6, .claude, .claudeIdle),
        ]
        let sessions: [Session] = plan.compactMap { item in
            guard let day = calendar.date(byAdding: .day, value: -item.daysAgo, to: today) else { return nil }
            let start = day.addingTimeInterval(item.hour * 3_600)
            let end = start.addingTimeInterval(item.hours * 3_600)
            guard end < now else { return nil }
            return Session(start: start, end: end, trigger: item.trigger, startBattery: 92,
                           endBattery: 92 - Int(item.hours * 7), endReason: item.reason)
        }

        var samples: [Sample] = []
        var battery = 58.0
        for minutesAgo in stride(from: 24 * 60, through: 0, by: -1) {
            let date = now.addingTimeInterval(-Double(minutesAgo) * 60)
            let hour = calendar.component(.hour, from: date)
            let active = sessions.contains { date >= $0.start && date <= ($0.end ?? now) }
            if !active && (1...7).contains(hour) { continue }
            let onAC = (9...12).contains(hour) || (18...19).contains(hour)
            battery = min(100, max(8, battery + (onAC ? 0.3 : (active ? -0.11 : -0.05))))
            let claude = active ? 2 + Int((sin(Double(minutesAgo) / 35) + 1) * 1.2) : ((10...20).contains(hour) ? 1 : 0)
            samples.append(Sample(date: date, battery: Int(battery), onAC: onAC, active: active, claudeSessions: claude))
        }
        return (sessions, samples)
    }
}
