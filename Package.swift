// swift-tools-version:5.9
import PackageDescription

let package = Package(
    name: "ng-thm-ch",
    platforms: [.macOS(.v14)],
    targets: [.executableTarget(name: "ng-thm-ch", path: "Sources/ng-thm-ch")]
)
