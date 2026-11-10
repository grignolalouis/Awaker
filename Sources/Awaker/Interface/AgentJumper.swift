import AppKit
import AwakerCore

/// Brings the user to an agent: the app hosting its terminal, or its folder when that app can't be found.
@MainActor
enum AgentJumper {
    static func jump(to agent: AgentSession) {
        var pid: Int32? = agent.pid
        // Walk up from the CLI to the first regular app: Terminal, iTerm, an editor…
        while let current = pid {
            if let app = NSRunningApplication(processIdentifier: current), app.activationPolicy == .regular {
                app.activate()
                return
            }
            pid = ProcessTree.parent(of: current)
        }
        NSWorkspace.shared.open(agent.directory)
    }
}
