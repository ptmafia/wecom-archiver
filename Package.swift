// swift-tools-version: 6.0
import PackageDescription

let package = Package(
    name: "wecom-reader",
    platforms: [.macOS(.v14)],
    targets: [
        .target(name: "WeComCore"),
        .executableTarget(name: "wecom-reader", dependencies: ["WeComCore"]),
        .executableTarget(name: "wecom-reader-launcher"),
        .testTarget(name: "WeComCoreTests", dependencies: ["WeComCore"]),
    ],
    swiftLanguageModes: [.v5]
)
