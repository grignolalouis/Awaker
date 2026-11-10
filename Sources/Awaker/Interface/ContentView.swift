import SwiftUI

enum Screen: String, CaseIterable, Identifiable {
    case home, history, settings

    var id: Self { self }

    var title: String {
        switch self {
        case .home: "Accueil"
        case .history: "Historique"
        case .settings: "Réglages"
        }
    }

    var symbol: String {
        switch self {
        case .home: "house"
        case .history: "clock.arrow.circlepath"
        case .settings: "gearshape"
        }
    }
}

/// The window: the illustration edge to edge, one screen on top, and a native toolbar picker to switch.
/// Everything is Apple's own components; the Liquid Glass comes from the system.
struct ContentView: View {
    static let defaultSize = CGSize(width: 880, height: 620)
    private let minimumSize = CGSize(width: 680, height: 520)

    @State private var screen: Screen = .home

    var body: some View {
        ZStack {
            BackdropView()
                .ignoresSafeArea()
            Group {
                switch screen {
                case .home: HomeView()
                case .history: HistoryView()
                case .settings: SettingsView()
                }
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
        }
        .toolbar {
            ToolbarItem(placement: .principal) {
                Picker("Écran", selection: $screen) {
                    ForEach(Screen.allCases) { screen in
                        Label(screen.title, systemImage: screen.symbol).tag(screen)
                    }
                }
                .pickerStyle(.segmented)
                .labelStyle(.titleAndIcon)
            }
        }
        .toolbarBackgroundVisibility(.hidden, for: .windowToolbar)
        .frame(minWidth: minimumSize.width, minHeight: minimumSize.height)
        // The backdrop is an image, so the window is always dark: light text, dark-tinted glass.
        .preferredColorScheme(.dark)
        .onAppear {
            // Behave like a regular app (Dock, ⌘-Tab) while the window is open.
            NSApp.setActivationPolicy(.regular)
            NSApp.activate()
        }
        .onDisappear { NSApp.setActivationPolicy(.accessory) }
        .task { await SnapshotRunner.run { screen = $0 } }
    }
}
