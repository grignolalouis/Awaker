import Foundation
import Testing
@testable import AwakerCore

@Suite struct AgentSessionTests {
    private func session(_ json: String) -> AgentSession? {
        AgentSession.decode(Data(json.utf8))
    }

    private func agent(_ id: String, _ state: AgentState, minutesAgo: Double, now: Date = Date()) -> AgentSession {
        AgentSession(id: id, pid: 1, directory: URL(fileURLWithPath: "/tmp"), name: id, state: state,
                     stateSince: now.addingTimeInterval(-minutesAgo * 60))
    }

    @Test func decodesAStatusFile() throws {
        let agent = try #require(session("""
        {"pid": 34462, "sessionId": "b6c5", "cwd": "/Users/me/dev", "name": "dev-f5",
         "status": "busy", "statusUpdatedAt": 1794322047927, "startedAt": 1794236764143}
        """))

        #expect(agent.pid == 34462)
        #expect(agent.id == "b6c5")
        #expect(agent.projectName == "dev")
        #expect(agent.state == .working)
        #expect(agent.stateSince == Date(timeIntervalSince1970: 1_794_322_047.927))
        #expect(agent.displayTitle == "dev-f5")
    }

    @Test func mapsEveryStatus() {
        func state(_ status: String, waitingFor: String? = nil) -> AgentState? {
            let extra = waitingFor.map { ", \"waitingFor\": \"\($0)\"" } ?? ""
            return session("{\"pid\": 1, \"sessionId\": \"s\", \"cwd\": \"/tmp\", \"status\": \"\(status)\"\(extra)}")?.state
        }

        #expect(state("busy") == .working)
        #expect(state("waiting", waitingFor: "Bash") == .waiting(tool: "Bash"))
        #expect(state("waiting") == .waiting(tool: nil))
        #expect(state("idle") == .finished)
        #expect(state("shell") == .background)
        #expect(state("something-new") == .finished)
    }

    @Test func rejectsFilesWithoutTheEssentials() {
        #expect(session("{\"pid\": 1, \"cwd\": \"/tmp\"}") == nil)
        #expect(session("not json") == nil)
    }

    @Test func rejectsPidsThatAreNotARealProcessId() {
        // 0 and -1 would pass a `kill(pid, 0)` probe; a huge value would overflow.
        for pid in ["0", "-1", "99999999999"] {
            #expect(session("{\"pid\": \(pid), \"sessionId\": \"s\", \"cwd\": \"/tmp\"}") == nil)
        }
    }

    @Test func aProcessThatStartedAtAnotherTimeIsNotTheSession() {
        let me = ProcessInfo.processInfo.processIdentifier
        let myStart = ProcessTree.startTime(of: me)
        func candidate(startedAt: Date?) -> AgentSession {
            AgentSession(id: "s", pid: me, directory: URL(fileURLWithPath: "/tmp"), name: "s", state: .working,
                         stateSince: Date(), startedAt: startedAt)
        }

        #expect(myStart != nil)
        #expect(AgentSessionReader.processIsAlive(candidate(startedAt: myStart)))
        #expect(AgentSessionReader.processIsAlive(candidate(startedAt: nil)))
        // Same pid, but the status file is from a process that started a day earlier: a reused pid.
        #expect(!AgentSessionReader.processIsAlive(candidate(startedAt: myStart?.addingTimeInterval(-86_400))))
    }

    @Test func notifiesWhenAnAgentNeedsYouOrFinishesWork() {
        let waiting = AgentSession(id: "a", pid: 1, directory: URL(fileURLWithPath: "/tmp/nexus"), name: "a",
                                   state: .waiting(tool: "Bash"), stateSince: Date(),
                                   details: AgentDetails(title: "Migration", pendingAction: "git push origin main"))
        let request = waiting.notification(after: .working)
        #expect(request?.title == "Migration needs you")
        #expect(request?.body == "It asks permission for: git push origin main. Project nexus.")

        let done = agent("b", .finished, minutesAgo: 0)
        #expect(done.notification(after: .working)?.title == "b finished")
        // Nothing to say when it was not working before, or when nothing changed.
        #expect(done.notification(after: .waiting(tool: nil)) == nil)
        #expect(done.notification(after: .finished) == nil)
        #expect(agent("c", .working, minutesAgo: 0).notification(after: .finished) == nil)
    }

    @Test func onlyRunningWorkKeepsTheMacBusy() {
        #expect(AgentState.working.keepsMacBusy)
        #expect(AgentState.background.keepsMacBusy)
        #expect(!AgentState.waiting(tool: "Bash").keepsMacBusy)
        #expect(!AgentState.finished.keepsMacBusy)
    }

    @Test func sortsWhoNeedsYouFirstThenMostRecent() {
        let sorted = [
            agent("done-old", .finished, minutesAgo: 60),
            agent("working", .working, minutesAgo: 5),
            agent("done-new", .finished, minutesAgo: 2),
            agent("waiting", .waiting(tool: nil), minutesAgo: 30),
        ].sortedForDisplay()

        #expect(sorted.map(\.id) == ["waiting", "working", "done-new", "done-old"])
        #expect(AgentState.background.isActive && AgentState.background.priority < AgentState.finished.priority)
    }

    @Test func recapCountsWhatFinishedMeanwhileAndWhoWaits() throws {
        let now = Date()
        let leftAt = now.addingTimeInterval(-3_600)
        let agents = [
            agent("finished-meanwhile", .finished, minutesAgo: 20, now: now),
            agent("finished-before", .finished, minutesAgo: 90, now: now),
            agent("still-working", .working, minutesAgo: 10, now: now),
            agent("waiting", .waiting(tool: "Bash"), minutesAgo: 5, now: now),
        ]
        let recap = try #require(AwayRecap(agents: agents, leftAt: leftAt, now: now))

        #expect(recap.finished == ["finished-meanwhile"])
        #expect(recap.waiting == ["waiting"])
        #expect(recap.duration == 3_600)
        #expect(recap.sentence == "1 agent finished, 1 needs you.")
        #expect(AwayRecap(agents: [agent("busy", .working, minutesAgo: 10, now: now)], leftAt: leftAt, now: now) == nil)
    }

    @Test func keepsOnlySessionsWhoseProcessIsAlive() throws {
        let root = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        let sessions = root.appendingPathComponent("sessions")
        try FileManager.default.createDirectory(at: sessions, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: root) }
        for pid in [10, 20] {
            let json = "{\"pid\": \(pid), \"sessionId\": \"s\(pid)\", \"cwd\": \"/tmp\", \"status\": \"idle\"}"
            try Data(json.utf8).write(to: sessions.appendingPathComponent("\(pid).json"))
        }
        // Not a status file: must be ignored.
        try Data("secret".utf8).write(to: sessions.appendingPathComponent("10.abc.key"))

        let alive = AgentSessionReader(claudeDirectory: root).sessions { $0.pid == 20 }

        #expect(alive.map(\.id) == ["s20"])
    }
}

@Suite struct TranscriptParserTests {
    private let transcript = """
    ut off line that is not valid json
    {"type":"ai-title","aiTitle":"Premier titre","sessionId":"s"}
    {"type":"cost-state","totalCostUSD":26.49,"totalAPIDuration":3631359,"totalLinesAdded":979,"totalLinesRemoved":209}
    {"type":"last-prompt","lastPrompt":"relance la\\n review","sessionId":"s"}
    {"type":"system","subtype":"away_summary","content":"La PR est verte."}
    {"type":"assistant","isSidechain":false,"message":{"content":[{"type":"text","text":"Je regarde."}]}}
    {"type":"assistant","isSidechain":true,"message":{"content":[{"type":"text","text":"Sous-agent."}]}}
    {"type":"ai-title","aiTitle":"Titre final","sessionId":"s"}
    {"type":"assistant","isSidechain":false,"message":{"content":[{"type":"text","text":"Je pousse la branche."},{"type":"tool_use","name":"Bash","input":{"command":"git push origin main"}}]}}
    {"type":"user","message":{"content":[{"type":"tool_result"}]}}
    """

    @Test func keepsTheNewestOfEachKind() {
        let details = TranscriptParser.details(in: transcript)

        #expect(details.title == "Titre final")
        #expect(details.lastPrompt == "relance la review")
        #expect(details.summary == "La PR est verte.")
        #expect(details.lastReply == "Je pousse la branche.")
        #expect(details.pendingAction == "git push origin main")
        #expect(details.cost == AgentCost(dollars: 26.49, modelTime: 3_631.359, linesAdded: 979, linesRemoved: 209))
    }

    @Test func pendingActionComesOnlyFromTheNewestAssistantMessage() {
        let text = """
        {"type":"assistant","message":{"content":[{"type":"tool_use","name":"Edit","input":{"file_path":"/tmp/a.swift"}}]}}
        {"type":"assistant","message":{"content":[{"type":"text","text":"Terminé."}]}}
        """
        let details = TranscriptParser.details(in: text)

        #expect(details.pendingAction == nil)
        #expect(details.lastReply == "Terminé.")
    }

    @Test func describesNonShellToolsWithTheirName() {
        let text = """
        {"type":"assistant","message":{"content":[{"type":"tool_use","name":"Edit","input":{"file_path":"/tmp/a.swift"}}]}}
        """
        #expect(TranscriptParser.details(in: text).pendingAction == "Edit: /tmp/a.swift")
    }

    @Test func aFreshReadKeepsWhatAnOlderOneKnew() {
        let older = AgentDetails(title: "Titre", lastPrompt: "ancienne", pendingAction: "rm -rf build", cost: AgentCost(dollars: 1, modelTime: 2, linesAdded: 3, linesRemoved: 4))
        let fresh = AgentDetails(lastPrompt: "nouvelle").filling(from: older)

        #expect(fresh.title == "Titre")
        #expect(fresh.lastPrompt == "nouvelle")
        #expect(fresh.cost?.dollars == 1)
        // A pending action is only true of the newest message: it is never carried over.
        #expect(fresh.pendingAction == nil)
    }

    @Test func findsTheLastCostFurtherBackInABigTranscript() throws {
        let root = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: root) }
        let file = root.appendingPathComponent("s.jsonl")
        let filler = String(repeating: "{\"type\":\"user\",\"message\":{\"content\":\"\(String(repeating: "x", count: 900))\"}}\n", count: 1_200)
        try Data(("{\"type\":\"cost-state\",\"totalCostUSD\":7.5}\n" + filler).utf8).write(to: file)
        let reader = AgentSessionReader(claudeDirectory: root)

        // Over a megabyte of filler: the tail read misses the entry, the search further back finds it.
        #expect(reader.details(in: file).cost == nil)
        #expect(reader.lastCost(in: file)?.dollars == 7.5)
    }
}

@Suite struct SubAgentTests {
    /// A transcript with a `subagents` folder next to it, holding one pair of files per entry.
    private func transcript(_ agents: [(id: String, meta: String?, minutesAgo: Double)], now: Date) throws -> URL {
        let root = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        let folder = root.appendingPathComponent("session/subagents")
        try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
        for agent in agents {
            let file = folder.appendingPathComponent("agent-\(agent.id).jsonl")
            try Data("{}\n".utf8).write(to: file)
            try FileManager.default.setAttributes([.modificationDate: now.addingTimeInterval(-agent.minutesAgo * 60)], ofItemAtPath: file.path)
            if let meta = agent.meta {
                try Data(meta.utf8).write(to: folder.appendingPathComponent("agent-\(agent.id).meta.json"))
            }
        }
        return root.appendingPathComponent("session.jsonl")
    }

    @Test func keepsOnlyHelpersStillAtWork() throws {
        let now = Date()
        let file = try transcript([
            (id: "running", meta: #"{"description":"Review the migration"}"#, minutesAgo: 1),
            (id: "done", meta: #"{"description":"Design skins","finished":true}"#, minutesAgo: 1),
            // Never marked finished, but silent for hours: its session died.
            (id: "dead", meta: #"{"description":"Old"}"#, minutesAgo: 300),
            (id: "unknown", meta: nil, minutesAgo: 1),
            (id: "unnamed", meta: "{}", minutesAgo: 2),
        ], now: now)
        defer { try? FileManager.default.removeItem(at: file.deletingLastPathComponent()) }

        let agents = AgentSessionReader().subagents(besideTranscript: file, now: now)

        #expect(Set(agents.map(\.id)) == ["agent-running", "agent-unnamed"])
        #expect(agents.first { $0.id == "agent-running" }?.task == "Review the migration")
        #expect(agents.first { $0.id == "agent-unnamed" }?.task == "Sub-agent")
    }

    @Test func aSessionWithoutHelpersHasNone() {
        #expect(AgentSessionReader().subagents(besideTranscript: URL(fileURLWithPath: "/nonexistent/s.jsonl")).isEmpty)
    }

    @Test func theStatusLineCountsHelpers() {
        var agent = AgentSession(id: "a", pid: 1, directory: URL(fileURLWithPath: "/tmp"), name: "a", state: .working, stateSince: Date())
        #expect(agent.statusLabel == "Working")
        agent.subagents = [SubAgent(id: "1", task: "x"), SubAgent(id: "2", task: "y")]
        #expect(agent.statusLabel == "Working · 2 sub-agents")
    }
}

@Suite struct RunningCommandTests {
    private let prefix = "source /Users/me/.claude/shell-snapshots/snapshot-zsh-1.sh 2>/dev/null || true && setopt NO_EXTENDED_GLOB 2>/dev/null || true"

    @Test func findsTheCommandInClaudeCodesShellScript() {
        let script = prefix + " && eval /tmp/watch/alexis.sh < /dev/null && pwd -P >| /tmp/claude-235e-cwd"
        #expect(RunningCommand.userCommand(inShellScript: script) == "/tmp/watch/alexis.sh")
    }

    @Test func removesTheQuotesAroundACommand() {
        let script = prefix + #" && eval 'npm run test -- --grep '\''sync button'\''' < /dev/null && pwd -P >| /tmp/claude-1-cwd"#
        #expect(RunningCommand.userCommand(inShellScript: script) == "npm run test -- --grep 'sync button'")
    }

    @Test func putsALongScriptOnOneShortLine() {
        let body = "for i in 1 2 3; do\n  " + String(repeating: "echo hello; ", count: 30) + "\ndone"
        let command = RunningCommand.userCommand(inShellScript: prefix + " && eval '\(body)' < /dev/null && pwd -P >| /tmp/c")
        #expect(command?.hasPrefix("for i in 1 2 3; do echo hello;") == true)
        #expect(command?.hasSuffix("…") == true)
    }

    @Test func ignoresShellsThatAreNotClaudeCodes() {
        #expect(RunningCommand.userCommand(inShellScript: "npm run dev && eval foo && pwd -P >| /tmp/x") == nil)
        #expect(RunningCommand.userCommand(inShellScript: prefix) == nil)
    }

    @Test func readsTheArgumentsOfARunningProcess() throws {
        let process = Process()
        process.executableURL = URL(fileURLWithPath: "/bin/sleep")
        process.arguments = ["30"]
        try process.run()
        defer { process.terminate() }

        #expect(ProcessTree.arguments(of: process.processIdentifier) == ["/bin/sleep", "30"])
        let me = ProcessInfo.processInfo.processIdentifier
        #expect(ProcessTree.children(of: [me]).contains { $0.pid == process.processIdentifier && $0.parent == me })
    }
}

@Suite struct FormatDollarsTests {
    @Test func dollars() {
        #expect(Format.dollars(26.494) == "$26.49")
        #expect(Format.dollars(184.2) == "$184")
    }
}
