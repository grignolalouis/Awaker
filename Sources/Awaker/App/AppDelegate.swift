import AppKit
import AwakerCore
import UserNotifications

final class AppDelegate: NSObject, NSApplicationDelegate, UNUserNotificationCenterDelegate {
    private var terminationSignal: DispatchSourceSignal?

    private var launchedAsLoginItem = false

    func applicationWillFinishLaunching(_ notification: Notification) {
        let event = NSAppleEventManager.shared().currentAppleEvent
        launchedAsLoginItem = event?.eventID == kAEOpenApplication
            && event?.paramDescriptor(forKeyword: keyAEPropData)?.enumCodeValue == keyAELaunchedAsLogInItem
    }

    func applicationDidFinishLaunching(_ notification: Notification) {
        routeSIGTERMToQuit()
        UNUserNotificationCenter.current().delegate = self
        MainActor.assumeIsolated {
            let environment = AppEnvironment.shared
            environment.awake.start()
            if environment.usesLiveAgents { environment.agents.start() }
            environment.updater.start()
            if environment.settings.notifications && !environment.isSnapshot {
                Notifier.requestAuthorization()
            }
            // Opened by hand (Dock, Finder, Spotlight): show the window. At login: stay in the menu bar.
            if !launchedAsLoginItem { WindowOpener.shared.open() }
        }
    }

    /// Dock icon clicked while the app runs.
    func applicationShouldHandleReopen(_ sender: NSApplication, hasVisibleWindows flag: Bool) -> Bool {
        MainActor.assumeIsolated { WindowOpener.shared.open() }
        return false
    }

    /// Never leave the Mac unable to sleep after the app quits.
    func applicationWillTerminate(_ notification: Notification) {
        MainActor.assumeIsolated {
            AppEnvironment.shared.awake.deactivate(.quit)
        }
    }

    /// `kill` sends SIGTERM, which skips `applicationWillTerminate` by default. Turn it into a normal quit.
    private func routeSIGTERMToQuit() {
        signal(SIGTERM, SIG_IGN)
        let source = DispatchSource.makeSignalSource(signal: SIGTERM, queue: .main)
        source.setEventHandler { NSApp.terminate(nil) }
        source.resume()
        terminationSignal = source
    }

    /// Show banners even while the window is focused.
    func userNotificationCenter(
        _ center: UNUserNotificationCenter,
        willPresent notification: UNNotification,
        withCompletionHandler completionHandler: @escaping (UNNotificationPresentationOptions) -> Void
    ) {
        completionHandler([.banner, .sound])
    }
}
