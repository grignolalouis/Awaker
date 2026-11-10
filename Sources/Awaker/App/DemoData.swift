import AwakerCore
import Foundation

/// Plausible data for snapshots.
enum DemoData {
    /// The agent whose row is open in snapshots.
    static let expandedAgent = "b"

    /// One session in each state, plus an old one that gets folded away.
    static func agents(now: Date) -> [AgentSession] {
        let dev = URL(fileURLWithPath: "/Users/demo/dev")
        func agent(_ id: String, _ folder: String, _ state: AgentState, secondsAgo: TimeInterval, _ details: AgentDetails) -> AgentSession {
            AgentSession(id: id, pid: 0, directory: dev.appendingPathComponent(folder), name: "\(folder)-\(id)", state: state,
                         stateSince: now.addingTimeInterval(-secondsAgo), details: details)
        }
        var agents = [
            agent("a", "nexus", .waiting(tool: "Bash"), secondsAgo: 70, AgentDetails(
                title: "Stripe webhooks migration", lastPrompt: "push the branch and open the PR",
                lastReply: "Tests pass. Pushing the branch.", pendingAction: "git push origin feat/stripe-webhooks",
                cost: AgentCost(dollars: 4.12, modelTime: 1_260, linesAdded: 212, linesRemoved: 40))),
            agent("b", "dashboard", .working, secondsAgo: 260, AgentDetails(
                title: "Contacts screen redesign", lastPrompt: "align the table with the mockup and fix sorting",
                lastReply: "Alexis pushed 4 commits on #2771 and they fix the disabled button. **What changes** (head `51da8a20`, 21 files): the button is greyed out when disabled, opacity 0.64 and clicks blocked, on both Sync buttons. It stays reachable with the keyboard. He did not take my `focusableWhenDisabled={false}` suggestion, and he has not answered my comment yet. I have only read the diff so far, I have not run his changes: the table still needs a pass on sorting by last activity, which I am doing now with two helpers.",
                cost: AgentCost(dollars: 11.8, modelTime: 3_900, linesAdded: 640, linesRemoved: 310))),
            agent("c", "dev", .finished, secondsAgo: 900, AgentDetails(
                title: "HubSpot seats and plan collector", lastPrompt: "ask for the review again",
                lastReply: "The PR is green and the review is requested again.",
                cost: AgentCost(dollars: 26.49, modelTime: 3_631, linesAdded: 979, linesRemoved: 209))),
            agent("d", "extension", .background, secondsAgo: 3_100, AgentDetails(title: "End-to-end tests")),
            agent("e", "dev", .finished, secondsAgo: 90_000, AgentDetails(title: "Old session")),
        ]
        agents[1].subagents = [SubAgent(id: "1", task: "Check sorting by last activity"), SubAgent(id: "2", task: "Compare the table with the mockup")]
        agents[1].commands = [RunningCommand(id: 1, command: "npm run test -- --watch contacts", startedAt: now.addingTimeInterval(-140))]
        agents[3].commands = [RunningCommand(id: 2, command: "npx playwright test --project=chromium", startedAt: now.addingTimeInterval(-3_100))]
        return agents
    }

    static func recap(now: Date) -> AwayRecap? {
        AwayRecap(agents: agents(now: now), leftAt: now.addingTimeInterval(-4_800), now: now)
    }

    /// Two weeks of sessions, some manual, some automatic.
    static func sessions(now: Date, calendar: Calendar = .current) -> [AwakeSession] {
        let today = calendar.startOfDay(for: now)
        let plan: [(daysAgo: Int, hour: Double, hours: Double, trigger: Trigger, reason: EndReason)] = [
            (9, 22, 4.2, .auto, .agentsIdle), (8, 11, 1.0, .manual, .manual), (7, 13, 3.4, .auto, .agentsIdle),
            (6, 10, 2.5, .manual, .manual), (5, 14, 1.0, .manual, .timer), (4, 9.5, 4.8, .auto, .agentsIdle),
            (3, 22.5, 6.5, .auto, .agentsIdle), (2, 13, 2.0, .manual, .manual), (1, 11, 3.4, .auto, .agentsIdle),
            (1, 23, 1.2, .manual, .battery), (0, 8.5, 1.6, .auto, .agentsIdle),
        ]
        return plan.compactMap { item in
            guard let day = calendar.date(byAdding: .day, value: -item.daysAgo, to: today) else { return nil }
            let start = day.addingTimeInterval(item.hour * 3_600)
            let end = start.addingTimeInterval(item.hours * 3_600)
            guard end < now else { return nil }
            return AwakeSession(start: start, end: end, trigger: item.trigger, startBattery: 92,
                                endBattery: 92 - Int(item.hours * 7), endReason: item.reason)
        }
    }
}
