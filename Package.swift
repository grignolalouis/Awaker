// swift-tools-version: 6.2
import PackageDescription

let swift5: [SwiftSetting] = [.swiftLanguageMode(.v5)]

let package = Package(
    name: "Awaker",
    platforms: [.macOS(.v26)],
    products: [
        .executable(name: "Awaker", targets: ["Awaker"]),
    ],
    targets: [
        // Models, stats and system services. No UI.
        .target(name: "AwakerCore", swiftSettings: swift5),
        // The app: state and a small SwiftUI interface built from Apple's own components.
        .executableTarget(name: "Awaker", dependencies: ["AwakerCore"], swiftSettings: swift5),
        .testTarget(name: "AwakerCoreTests", dependencies: ["AwakerCore"]),
    ]
)
