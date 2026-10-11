// swift-tools-version: 6.4
import PackageDescription

let package = Package(
    name: "TinyTouchApp",
    platforms: [.macOS(.v27)],
    targets: [
        .executableTarget(
            name: "TinyTouchApp",
            path: "Sources/TinyTouchApp"
        ),
        .executableTarget(
            name: "TinyTouchAskpass",
            path: "Sources/TinyTouchAskpass"
        ),
        .testTarget(
            name: "TinyTouchAppTests",
            dependencies: ["TinyTouchApp"],
            path: "Tests/TinyTouchAppTests"
        ),
    ]
)
