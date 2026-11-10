import Foundation

// Reading Claude Code's local files. Read-only, and defensive: these are internal formats.
//
// - `~/.claude/sessions/<pid>.json`: one status file per running session.
// - `~/.claude/projects/<project>/<sessionId>.jsonl`: the transcript, one JSON entry per line.
//   Entries used here: `ai-title`, `last-prompt`, `system` with subtype `away_summary`,
//   `cost-state`, and `assistant` messages (text and tool_use blocks).
// - `~/.claude/projects/<project>/<sessionId>/subagents/agent-<id>.jsonl` and `.meta.json`: one pair per
//   helper agent the session started. The meta file holds `description`, and `finished: true` once it is done.

/// Extracts a session's details from the lines of its transcript.
public enum TranscriptParser {
    /// Longest reply or prompt kept, in characters.
    private static let textLimit = 500

    /// Reads the lines from the newest to the oldest and keeps the newest of each kind.
    /// The first line may be cut (the text is usually a file's tail); invalid lines are skipped.
    public static func details(in text: String) -> AgentDetails {
        var details = AgentDetails()
        var sawAssistant = false
        for line in text.split(separator: "\n").reversed() {
            if details.title == nil, line.contains("\"type\":\"ai-title\"") {
                details.title = (object(line)?["aiTitle"] as? String).flatMap(clean)
            } else if details.lastPrompt == nil, line.contains("\"type\":\"last-prompt\"") {
                details.lastPrompt = (object(line)?["lastPrompt"] as? String).flatMap(clean)
            } else if details.summary == nil, line.contains("\"subtype\":\"away_summary\"") {
                details.summary = (object(line)?["content"] as? String).flatMap(clean)
            } else if details.cost == nil, line.contains("\"type\":\"cost-state\"") {
                details.cost = object(line).flatMap(cost)
            } else if details.lastReply == nil, line.contains("\"type\":\"assistant\""),
                      let entry = object(line), entry["isSidechain"] as? Bool != true,
                      let blocks = (entry["message"] as? [String: Any])?["content"] as? [[String: Any]] {
                // Only the newest assistant message can hold a pending tool call.
                if !sawAssistant {
                    details.pendingAction = blocks.last { $0["type"] as? String == "tool_use" }.flatMap(describe)
                    sawAssistant = true
                }
                details.lastReply = blocks.last { $0["type"] as? String == "text" }
                    .flatMap { $0["text"] as? String }
                    .flatMap(clean)
            }
        }
        return details
    }

    /// The newest `cost-state` entry in a chunk of transcript.
    public static func cost(in text: String) -> AgentCost? {
        for line in text.split(separator: "\n").reversed() where line.contains("\"type\":\"cost-state\"") {
            if let cost = object(line).flatMap(cost) { return cost }
        }
        return nil
    }

    private static func object(_ line: Substring) -> [String: Any]? {
        try? JSONSerialization.jsonObject(with: Data(line.utf8)) as? [String: Any]
    }

    private static func cost(_ entry: [String: Any]) -> AgentCost? {
        guard let dollars = entry["totalCostUSD"] as? Double else { return nil }
        return AgentCost(dollars: dollars,
                         modelTime: (entry["totalAPIDuration"] as? Double ?? 0) / 1_000,
                         linesAdded: entry["totalLinesAdded"] as? Int ?? 0,
                         linesRemoved: entry["totalLinesRemoved"] as? Int ?? 0)
    }

    /// One line of text, without the whitespace runs of a multi-line message, cut to a readable length.
    private static func clean(_ text: String) -> String? {
        let line = text.split(whereSeparator: \.isWhitespace).joined(separator: " ")
        guard !line.isEmpty else { return nil }
        return line.count > textLimit ? String(line.prefix(textLimit)) + "…" : line
    }

    /// What a tool call would do, in a few words: the command, the file, the address.
    private static func describe(_ toolUse: [String: Any]) -> String? {
        guard let name = toolUse["name"] as? String else { return nil }
        let input = toolUse["input"] as? [String: Any] ?? [:]
        let subject = ["command", "file_path", "url", "path", "description"]
            .compactMap { input[$0] as? String }
            .first
            .flatMap(clean)
        guard let subject else { return name }
        let short = subject.count > 80 ? String(subject.prefix(80)) + "…" : subject
        return name == "Bash" ? short : "\(name): \(short)"
    }
}

/// Reads the running sessions and their transcripts from Claude Code's folder.
public struct AgentSessionReader: Sendable {
    private let sessionsDirectory: URL
    private let projectsDirectory: URL
    /// How much of the end of a transcript is read each time. Transcripts can reach gigabytes.
    private let tailLength: UInt64 = 512_000
    /// How far back the one-off search for a session's cost may go, and in which steps.
    private let costSearchLimit: UInt64 = 64_000_000
    private let costSearchStep: UInt64 = 4_000_000
    /// A helper agent that wrote nothing for this long is no longer counted as running.
    private let subagentSilenceLimit: TimeInterval = 30 * 60

    public init(claudeDirectory: URL = FileManager.default.homeDirectoryForCurrentUser.appendingPathComponent(".claude")) {
        sessionsDirectory = claudeDirectory.appendingPathComponent("sessions")
        projectsDirectory = claudeDirectory.appendingPathComponent("projects")
    }

    /// Sessions whose process is still alive, without their transcript details.
    public func sessions(isAlive: (AgentSession) -> Bool = AgentSessionReader.processIsAlive) -> [AgentSession] {
        let files = (try? FileManager.default.contentsOfDirectory(at: sessionsDirectory, includingPropertiesForKeys: nil)) ?? []
        return files
            .filter { $0.pathExtension == "json" }
            .compactMap { try? Data(contentsOf: $0) }
            .compactMap(AgentSession.decode)
            .filter(isAlive)
    }

    /// The transcript of a session, wherever Claude Code filed it.
    public func transcript(of session: AgentSession) -> URL? {
        let projects = (try? FileManager.default.contentsOfDirectory(at: projectsDirectory, includingPropertiesForKeys: nil)) ?? []
        return projects
            .map { $0.appendingPathComponent("\(session.id).jsonl") }
            .first { FileManager.default.fileExists(atPath: $0.path) }
    }

    /// What the end of a transcript says about its session.
    public func details(in transcript: URL) -> AgentDetails {
        guard let handle = try? FileHandle(forReadingFrom: transcript) else { return AgentDetails() }
        defer { try? handle.close() }
        let end = (try? handle.seekToEnd()) ?? 0
        return TranscriptParser.details(in: read(handle, from: end > tailLength ? end - tailLength : 0, length: tailLength))
    }

    /// Looks further back for the last recorded cost, which Claude Code only writes now and then.
    /// Expensive on big transcripts: call it once per session, off the main thread.
    public func lastCost(in transcript: URL) -> AgentCost? {
        guard let handle = try? FileHandle(forReadingFrom: transcript) else { return nil }
        defer { try? handle.close() }
        let end = (try? handle.seekToEnd()) ?? 0
        var upper = end
        while upper > 0, end - upper < costSearchLimit {
            let lower = upper > costSearchStep ? upper - costSearchStep : 0
            // Overlap the next chunk a little so an entry cut at the boundary is still found whole.
            if let cost = TranscriptParser.cost(in: read(handle, from: lower, length: upper - lower + 4_096)) { return cost }
            upper = lower
        }
        return nil
    }

    /// The helper agents of a session that are still at work, oldest first.
    /// One whose transcript has not moved for a long while is taken for dead (its session crashed, or it was
    /// stopped without a word): better a missing mascot than a phantom one.
    public func subagents(besideTranscript transcript: URL, now: Date = Date()) -> [SubAgent] {
        let directory = transcript.deletingPathExtension().appendingPathComponent("subagents")
        let keys: Set<URLResourceKey> = [.contentModificationDateKey, .creationDateKey]
        let files = (try? FileManager.default.contentsOfDirectory(at: directory, includingPropertiesForKeys: Array(keys))) ?? []
        return files
            .filter { $0.pathExtension == "jsonl" }
            .compactMap { file -> (agent: SubAgent, created: Date)? in
                guard let values = try? file.resourceValues(forKeys: keys),
                      let modified = values.contentModificationDate,
                      now.timeIntervalSince(modified) < subagentSilenceLimit else { return nil }
                let meta = file.deletingPathExtension().appendingPathExtension("meta.json")
                guard let data = try? Data(contentsOf: meta),
                      let object = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
                      object["finished"] as? Bool != true else { return nil }
                let task = (object["description"] as? String).flatMap { $0.isEmpty ? nil : $0 } ?? "Sub-agent"
                return (SubAgent(id: file.deletingPathExtension().lastPathComponent, task: task), values.creationDate ?? modified)
            }
            .sorted { $0.created < $1.created }
            .map(\.agent)
    }

    /// The shell commands each session is running, by session pid. Commands that only just started are left out:
    /// most last a blink, and the list is read every couple of seconds.
    public static func runningCommands(of sessions: Set<Int32>, now: Date = Date()) -> [Int32: [RunningCommand]] {
        var commands: [Int32: [RunningCommand]] = [:]
        for child in ProcessTree.children(of: sessions) where now.timeIntervalSince(child.startedAt) >= commandMinimumAge {
            guard let arguments = ProcessTree.arguments(of: child.pid), arguments.count >= 3, arguments[1] == "-c",
                  let command = RunningCommand.userCommand(inShellScript: arguments[2]) else { continue }
            commands[child.parent, default: []].append(RunningCommand(id: child.pid, command: command, startedAt: child.startedAt))
        }
        return commands.mapValues { $0.sorted { $0.startedAt < $1.startedAt } }
    }

    private func read(_ handle: FileHandle, from offset: UInt64, length: UInt64) -> String {
        try? handle.seek(toOffset: offset)
        let data = (try? handle.read(upToCount: Int(length))) ?? Data()
        return String(decoding: data, as: UTF8.self)
    }

    /// True when the session's own process is still running. A pid alone is not enough: after a crash or a
    /// reboot, a leftover status file could match an unrelated process that reused the pid, and a phantom
    /// "busy" agent would keep the Mac awake for ever. So the process must also have started when the file says.
    public static func processIsAlive(_ session: AgentSession) -> Bool {
        guard let processStart = ProcessTree.startTime(of: session.pid) else { return false }
        guard let startedAt = session.startedAt else { return true }
        return abs(processStart.timeIntervalSince(startedAt)) < startTolerance
    }

    /// Claude Code notes its start a moment after the process is created.
    private static let startTolerance: TimeInterval = 120
    private static let commandMinimumAge: TimeInterval = 5
}
