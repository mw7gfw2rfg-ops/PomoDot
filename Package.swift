// swift-tools-version: 6.2
// (6.2 is the minimum that knows about `.macOS(.v26)`, which is where Liquid Glass lands.)
import PackageDescription

// PomoDot — a transparent Liquid Glass Pomodoro timer for the macOS menu bar.
// Zero dependencies by design (see ISA.md § Constraints).
//
// Split into a pure, testable core (PomoDotKit: state machine + glyph table + theme)
// and a thin AppKit/SwiftUI shell (PomoDot). The core is what `swift test` exercises;
// executable targets can't be imported by test targets cleanly, hence the split.
let package = Package(
    name: "PomoDot",
    platforms: [.macOS(.v26)],
    targets: [
        .target(
            name: "PomoDotKit",
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
