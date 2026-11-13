// swift-tools-version: 6.4
import PackageDescription

let package = Package(
    name: "TinyTouchApp",
    platforms: [.macOS(.v27)],
    dependencies: [
        // Self-updates from the appcast attached to each GitHub release.
        .package(url: "https://github.com/sparkle-project/Sparkle", exact: "2.10.1"),
    ],
    targets: [
        .executableTarget(
            name: "TinyTouchApp",
            dependencies: [.product(name: "Sparkle", package: "Sparkle")],
            path: "Sources/TinyTouchApp",
            linkerSettings: [
                // build-app.sh copies Sparkle.framework into Contents/Frameworks.
                .unsafeFlags(["-Xlinker", "-rpath", "-Xlinker", "@executable_path/../Frameworks"]),
            ]
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
