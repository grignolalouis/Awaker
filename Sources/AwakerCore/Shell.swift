import Foundation

enum Shell {
    struct Result {
        let status: Int32
        let output: String

        var succeeded: Bool { status == 0 }
    }

    static func run(_ executable: String, _ arguments: [String]) -> Result {
        let process = Process()
        process.executableURL = URL(fileURLWithPath: executable)
        process.arguments = arguments
        let pipe = Pipe()
        process.standardOutput = pipe
        process.standardError = pipe
        do {
            try process.run()
        } catch {
            return Result(status: -1, output: error.localizedDescription)
        }
        let data = pipe.fileHandleForReading.readDataToEndOfFile()
        process.waitUntilExit()
        return Result(status: process.terminationStatus, output: String(decoding: data, as: UTF8.self))
    }

    /// Runs a shell script as root through the native macOS admin prompt.
    /// Returns nil on success or cancel, an error message otherwise.
    static func runAsAdministrator(_ script: String) -> String? {
        let escaped = script
            .replacingOccurrences(of: "\\", with: "\\\\")
            .replacingOccurrences(of: "\"", with: "\\\"")
        var error: NSDictionary?
        NSAppleScript(source: "do shell script \"\(escaped)\" with administrator privileges")?
            .executeAndReturnError(&error)
        guard let error else { return nil }
        let userCancelled = -128
        if error[NSAppleScript.errorNumber] as? Int == userCancelled { return nil }
        return error[NSAppleScript.errorMessage] as? String ?? "Erreur inconnue."
    }
}
