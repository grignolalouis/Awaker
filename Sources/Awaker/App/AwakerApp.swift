import SwiftUI

@main
struct AwakerApp: App {
    @NSApplicationDelegateAdaptor(AppDelegate.self) private var appDelegate
    private let environment = AppEnvironment.shared

    var body: some Scene {
        MenuBarExtra {
            MenuBarContent()
                .environment(environment.awake)
                .environment(environment.settings)
                .environment(environment.agents)
                .environment(environment.updater)
        } label: {
            MenuBarLabel(awake: environment.awake, settings: environment.settings, monitor: environment.agents)
        }
        .menuBarExtraStyle(.menu)

        Window("Awaker", id: WindowID.main) {
            ContentView()
                .environment(environment.awake)
                .environment(environment.settings)
                .environment(environment.history)
                .environment(environment.agents)
                .environment(environment.updater)
        }
        .windowToolbarStyle(.unified(showsTitle: false))
        .defaultSize(ContentView.defaultSize)
        .windowResizability(.contentMinSize)
        // The app delegate decides at launch (open by hand: shown; login item: hidden).
        .defaultLaunchBehavior(.suppressed)
        .restorationBehavior(.disabled)
    }
}

enum WindowID {
    static let main = "main"
}
