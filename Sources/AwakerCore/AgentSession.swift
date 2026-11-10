import Foundation

/// What a Claude Code session is doing right now, from the user's point of view.
public enum AgentState: Equatable, Sendable {
    /// Running a turn.
    case working
    /// Blocked until the user answers: a permission request (`tool` names it) or a question.
    case waiting(tool: String?)
    /// Finished its response; the next move is the user's.
    case finished
    /// Finished its response, with a shell command still running in the background.
    case background

    /// Maps Claude Code's own status strings (`busy`, `waiting`, `idle`, `shell`). Unknown values count as finished.
    init(status: String?, waitingFor: String?) {
        switch status {
        case "busy": self = .working
        case "waiting": self = .waiting(tool: waitingFor)
        case "shell": self = .background
        default: self = .finished
        }
    }

    public var needsUser: Bool {
        if case .waiting = self { return true }
        return false
    }

    /// True while something is running that a sleeping Mac would stop: a turn, or a background command.
    /// An agent waiting for the user makes no progress, so it does not count.
    public var keepsMacBusy: Bool {
        switch self {
        case .working, .background: true
        case .waiting, .finished: false
        }
    }

    /// True while something is going on: a turn, a question to the user, a background command.
    public var isActive: Bool {
        switch self {
        case .working, .waiting, .background: true
        case .finished: false
        }
    }

    /// Display order: who needs you first, then who is working, then the rest.
    public var priority: Int {
        switch self {
        case .waiting: 0
        case .working: 1
        case .background: 2
        case .finished: 3
        }
    }
}

/// What Claude Code last recorded about a session's cost and effort. Not live: it is written now and then.
public struct AgentCost: Equatable, Sendable {
    /// API-equivalent cost in US dollars, as computed by Claude Code.
    public let dollars: Double
    /// Time spent waiting on the model, across the whole session.
    public let modelTime: TimeInterval
    public let linesAdded: Int
    public let linesRemoved: Int

    public init(dollars: Double, modelTime: TimeInterval, linesAdded: Int, linesRemoved: Int) {
        self.dollars = dollars
        self.modelTime = modelTime
        self.linesAdded = linesAdded
        self.linesRemoved = linesRemoved
    }
}

/// What a session's transcript says about it.
public struct AgentDetails: Equatable, Sendable {
    /// The conversation's generated title.
    public var title: String?
    /// The user's last message.
    public var lastPrompt: String?
    /// The agent's last written reply.
    public var lastReply: String?
    /// Claude Code's own recap of where things stand, when it wrote one.
    public var summary: String?
    /// The tool call the agent last asked to make ("git push origin main"). Meaningful while it waits for approval.
    public var pendingAction: String?
    public var cost: AgentCost?

    public init(title: String? = nil, lastPrompt: String? = nil, lastReply: String? = nil, summary: String? = nil,
                pendingAction: String? = nil, cost: AgentCost? = nil) {
        self.title = title
        self.lastPrompt = lastPrompt
        self.lastReply = lastReply
        self.summary = summary
        self.pendingAction = pendingAction
        self.cost = cost
    }

    /// Fills the gaps of a fresh read with what an earlier read knew. A transcript's tail does not always
    /// contain every kind of entry.
    public func filling(from older: AgentDetails) -> AgentDetails {
        AgentDetails(title: title ?? older.title, lastPrompt: lastPrompt ?? older.lastPrompt,
                     lastReply: lastReply ?? older.lastReply, summary: summary ?? older.summary,
                     pendingAction: pendingAction, cost: cost ?? older.cost)
    }
}

/// One running Claude Code session, as described by its status file and its transcript.
public struct AgentSession: Identifiable, Equatable, Sendable {
    public let id: String
    public let pid: Int32
    public let directory: URL
    /// Claude Code's short generated name ("dev-5d"). Shown only when the session has no title yet.
    public let name: String
    public let state: AgentState
    public let stateSince: Date
    /// When Claude Code says the session's process started. Used to tell it from another process reusing its pid.
    public let startedAt: Date?
    public var details: AgentDetails

    public init(id: String, pid: Int32, directory: URL, name: String, state: AgentState, stateSince: Date,
                startedAt: Date? = nil, details: AgentDetails = AgentDetails()) {
        self.id = id
        self.pid = pid
        self.directory = directory
        self.name = name
        self.state = state
        self.stateSince = stateSince
        self.startedAt = startedAt
        self.details = details
    }

    public var displayTitle: String { details.title ?? name }

    /// Folder name shown to the user ("nexus"), or "~" for the home folder.
    public var projectName: String {
        directory.path == FileManager.default.homeDirectoryForCurrentUser.path ? "~" : directory.lastPathComponent
    }

    /// Decodes a `~/.claude/sessions/<pid>.json` file. Nil when the essentials are missing.
    /// This file is Claude Code's internal format: every field is read defensively.
    public static func decode(_ data: Data) -> AgentSession? {
        guard let object = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
              let pid = (object["pid"] as? Int).flatMap(Int32.init(exactly:)), pid > 0,
              let id = object["sessionId"] as? String,
              let cwd = object["cwd"] as? String else { return nil }
        let milliseconds = (object["statusUpdatedAt"] ?? object["updatedAt"] ?? object["startedAt"]) as? Double
        let started = (object["startedAt"] as? Double).map { Date(timeIntervalSince1970: $0 / 1_000) }
        return AgentSession(
            id: id,
            pid: pid,
            directory: URL(fileURLWithPath: cwd),
            name: object["name"] as? String ?? "Session \(pid)",
            state: AgentState(status: object["status"] as? String, waitingFor: object["waitingFor"] as? String),
            stateSince: milliseconds.map { Date(timeIntervalSince1970: $0 / 1_000) } ?? Date(),
            startedAt: started
        )
    }
}

public extension Array where Element == AgentSession {
    /// Who needs you first, then who is working, then the rest; most recent change first within each group.
    func sortedForDisplay() -> [AgentSession] {
        sorted { ($0.state.priority, $1.stateSince) < ($1.state.priority, $0.stateSince) }
    }
}

/// What happened to the agents while the user was away from the Mac.
public struct AwayRecap: Equatable, Sendable {
    public let duration: TimeInterval
    /// Titles of the agents that finished meanwhile.
    public let finished: [String]
    /// Titles of the agents waiting for the user now.
    public let waiting: [String]

    /// Nil when nothing worth telling happened.
    public init?(agents: [AgentSession], leftAt: Date, now: Date) {
        finished = agents.filter { !$0.state.keepsMacBusy && !$0.state.needsUser && $0.stateSince > leftAt }.map(\.displayTitle)
        waiting = agents.filter(\.state.needsUser).map(\.displayTitle)
        duration = now.timeIntervalSince(leftAt)
        if finished.isEmpty && waiting.isEmpty { return nil }
    }

    /// "2 agents ont terminé, 1 t'attend."
    public var sentence: String {
        var parts: [String] = []
        if !finished.isEmpty { parts.append(Format.plural(finished.count, "agent a terminé", "agents ont terminé")) }
        if !waiting.isEmpty { parts.append(Format.plural(waiting.count, "t'attend", "t'attendent")) }
        return parts.joined(separator: ", ") + "."
    }
}

/// Facts about running processes, read from the kernel.
public enum ProcessTree {
    /// The parent of a process, to walk up from a CLI to the app that hosts its terminal.
    public static func parent(of pid: Int32) -> Int32? {
        guard let info = info(of: pid) else { return nil }
        let parent = info.kp_eproc.e_ppid
        return parent > 1 ? parent : nil
    }

    /// When a process started. Nil when no process has this pid.
    public static func startTime(of pid: Int32) -> Date? {
        guard let start = info(of: pid)?.kp_proc.p_starttime else { return nil }
        return Date(timeIntervalSince1970: Double(start.tv_sec) + Double(start.tv_usec) / 1_000_000)
    }

    private static func info(of pid: Int32) -> kinfo_proc? {
        var info = kinfo_proc()
        var size = MemoryLayout<kinfo_proc>.stride
        var name: [Int32] = [CTL_KERN, KERN_PROC, KERN_PROC_PID, pid]
        guard sysctl(&name, UInt32(name.count), &info, &size, nil, 0) == 0, size > 0, info.kp_proc.p_pid == pid else { return nil }
        return info
    }
}
