// swift-tools-version:5.9
import PackageDescription

let package = Package(
    name: "PingWatch",
    platforms: [.macOS("26.0")],
    targets: [
        .target(name: "PingCore"),
        .executableTarget(name: "PingWatch", dependencies: ["PingCore"]),
        .testTarget(name: "PingCoreTests", dependencies: ["PingCore"]),
    ]
)
