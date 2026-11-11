import AwakerCore
import Foundation

/// Asks the user's own Claude Code to write the away recap. It runs the installed `claude` command once,
/// under the user's login, so it draws on their usage: only ever called when the setting is on.
struct RecapWriter: Sendable {
    enum Failure: Error {
        case claudeNotFound, timedOut, noAnswer

        var message: String {
            switch self {
            case .claudeNotFound: "Claude Code wasn't found on this Mac."
            case .timedOut: "Claude Code took too long to answer."
            case .noAnswer: "Claude Code returned no recap."
            }
        }
    }

    /// The recap for this material (`WrittenRecap.material`).
    var write: @Sendable (String) async -> Result<String, Failure>

    static let live = RecapWriter { material in
        guard let claude = claudeCommand() else { return .failure(.claudeNotFound) }
        return await Task.detached(priority: .utility) { run(claude, material: material) }.value
    }

    private static let timeout: TimeInterval = 90

    /// An app started from the Dock has no shell PATH: look where Claude Code installs itself.
    private static func claudeCommand() -> URL? {
        let home = FileManager.default.homeDirectoryForCurrentUser.path
        return ["\(home)/.local/bin/claude", "\(home)/.claude/local/claude", "/opt/homebrew/bin/claude", "/usr/local/bin/claude"]
            .first { FileManager.default.isExecutableFile(atPath: $0) }
            .map { URL(fileURLWithPath: $0) }
    }

    private static func run(_ claude: URL, material: String) -> Result<String, Failure> {
        let process = Process()
        process.executableURL = claude
        process.arguments = WrittenRecap.arguments
        // Away from any project, so no project instructions or files come along.
        process.currentDirectoryURL = FileManager.default.temporaryDirectory
        let input = Pipe(), output = Pipe()
        process.standardInput = input
        process.standardOutput = output
        process.standardError = FileHandle.nullDevice
        do { try process.run() } catch { return .failure(.claudeNotFound) }

        let deadline = DispatchWorkItem { if process.isRunning { process.terminate() } }
        DispatchQueue.global().asyncAfter(deadline: .now() + timeout, execute: deadline)
        input.fileHandleForWriting.write(Data(material.utf8))
        try? input.fileHandleForWriting.close()
        let data = output.fileHandleForReading.readDataToEndOfFile()
        process.waitUntilExit()
        deadline.cancel()

        if process.terminationReason == .uncaughtSignal { return .failure(.timedOut) }
        guard let text = WrittenRecap.text(fromOutput: String(decoding: data, as: UTF8.self)) else { return .failure(.noAnswer) }
        return .success(text)
    }
}
