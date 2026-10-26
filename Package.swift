// swift-tools-version: 6.0
import PackageDescription

let package = Package(
    name: "LockIn",
    platforms: [.macOS(.v14)],
    targets: [
        // Pure logic: timer state machine, stats, blocklist matching. Unit-tested.
        .target(name: "LockInCore"),
        // AppKit shell. Swift 5 mode keeps Carbon/AppKit callbacks free of Sendable noise.
        .executableTarget(
            name: "LockIn",
            dependencies: ["LockInCore"],
            swiftSettings: [.swiftLanguageMode(.v5)]
        ),
        .testTarget(name: "LockInCoreTests", dependencies: ["LockInCore"]),
    ]
)
