// swift-tools-version: 6.2
// (6.2 is the minimum that knows about `.macOS(.v26)`, which is where Liquid Glass lands.)
import PackageDescription

// PomoDot — a transparent Liquid Glass Pomodoro timer for the macOS menu bar.
//
// The look and the menu-bar plumbing live in GlassKit, a sibling package. What's left here
// is only what's actually about pomodoros: the state machine, the focus log, and the panel
// that composes GlassKit's parts into this app's layout.
let package = Package(
    name: "PomoDot",
    platforms: [.macOS(.v26)],
    dependencies: [
        // URL rather than a local path so a standalone clone of this repo actually
        // builds. For local GlassKit work, `swift package edit GlassKit --path ../GlassKit`
        // swaps in a sibling checkout without touching this file.
        .package(url: "https://github.com/mw7gfw2rfg-ops/GlassKit.git", from: "1.0.0"),
    ],
    targets: [
        .target(
            name: "PomoDotKit",
            dependencies: [.product(name: "GlassKit", package: "GlassKit")],
            swiftSettings: [.swiftLanguageMode(.v6)]
        ),
        .executableTarget(
            name: "PomoDot",
            dependencies: ["PomoDotKit"],
            swiftSettings: [.swiftLanguageMode(.v6)]
        ),
        .testTarget(
            name: "PomoDotTests",
            dependencies: ["PomoDotKit"],
            swiftSettings: [.swiftLanguageMode(.v6)]
        ),
    ]
)
