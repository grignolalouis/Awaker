import SwiftUI

/// Lets AppKit code (Dock clicks, launch) open the SwiftUI main window.
///
/// SwiftUI only hands out `OpenWindowAction` to views. The menu bar label is always alive,
/// so it registers the action here as soon as it appears.
@MainActor
final class WindowOpener {
    static let shared = WindowOpener()

    private var action: OpenWindowAction?
    private var isPending = false

    func register(_ action: OpenWindowAction) {
        self.action = action
        if isPending {
            isPending = false
            open()
        }
    }

    /// Opens (or brings forward) the main window. Queued until the action is registered.
    func open() {
        guard let action else {
            isPending = true
            return
        }
        NSApp.activate()
        action(id: WindowID.main)
    }
}
