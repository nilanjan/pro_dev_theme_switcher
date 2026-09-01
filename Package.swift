// swift-tools-version:5.9
import PackageDescription

// macOS only: the app is a menu bar item that drives the system appearance.
let package = Package(
    name: "prodev-theme-switcher",
    platforms: [.macOS(.v14)],
    targets: [
        // Pure Foundation, no AppKit -- this is the part CI can actually cover.
        .target(name: "ThemeSwitcherCore", path: "Sources/ThemeSwitcherCore"),
        .executableTarget(
            name: "prodev-theme-switcher",
            dependencies: ["ThemeSwitcherCore"],
            path: "Sources/prodev-theme-switcher"
        ),
        // A plain executable, not a testTarget: XCTest needs a full Xcode install
        // and an accepted licence, which a Command Line Tools box does not have.
        .executableTarget(
            name: "core-tests",
            dependencies: ["ThemeSwitcherCore"],
            path: "Tests/CoreTests"
        ),
    ]
)
