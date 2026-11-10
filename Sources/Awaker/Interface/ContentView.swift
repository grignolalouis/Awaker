import SwiftUI

enum Screen: String, CaseIterable, Identifiable {
    case home, history, settings

    var id: Self { self }

    var title: String {
        switch self {
        case .home: "Home"
        case .history: "History"
        case .settings: "Settings"
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
    static let defaultSize = CGSize(width: 1020, height: 720)
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
                ScreenPicker(screen: $screen)
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

/// The screens as a segmented control with an icon and a title on each segment.
/// SwiftUI's segmented `Picker` drops the icons on macOS, so this is AppKit's own control, as it is.
private struct ScreenPicker: NSViewRepresentable {
    @Binding var screen: Screen

    func makeNSView(context: Context) -> NSSegmentedControl {
        let control = NSSegmentedControl()
        control.trackingMode = .selectOne
        control.controlSize = .large
        control.segmentCount = Screen.allCases.count
        for (index, screen) in Screen.allCases.enumerated() {
            control.setLabel(screen.title, forSegment: index)
            control.setImage(NSImage(systemSymbolName: screen.symbol, accessibilityDescription: nil), forSegment: index)
            control.setImageScaling(.scaleProportionallyDown, forSegment: index)
        }
        control.target = context.coordinator
        control.action = #selector(Coordinator.select(_:))
        control.setAccessibilityLabel("Screen")
        return control
    }

    func updateNSView(_ control: NSSegmentedControl, context: Context) {
        context.coordinator.select = { screen = $0 }
        control.selectedSegment = Screen.allCases.firstIndex(of: screen) ?? 0
    }

    func makeCoordinator() -> Coordinator { Coordinator() }

    @MainActor
    final class Coordinator: NSObject {
        var select: (Screen) -> Void = { _ in }

        @objc func select(_ control: NSSegmentedControl) {
            guard Screen.allCases.indices.contains(control.selectedSegment) else { return }
            select(Screen.allCases[control.selectedSegment])
        }
    }
}
