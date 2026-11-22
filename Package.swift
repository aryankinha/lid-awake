// swift-tools-version: 5.9
import PackageDescription

let package = Package(
    name: "LidAwake",
    platforms: [.macOS(.v13)],
    products: [
        .library(name: "LidAwakeCore", targets: ["LidAwakeCore"]),
        .executable(name: "LidAwake", targets: ["LidAwakeApp"]),
        .executable(name: "lidawake-ctl", targets: ["LidAwakeCtl"]),
    ],
    targets: [
        .target(
            name: "LidAwakeCore",
            path: "Sources/LidAwakeCore"
        ),
        .executableTarget(
            name: "LidAwakeApp",
            dependencies: ["LidAwakeCore"],
            path: "Sources/LidAwakeApp"
        ),
        .executableTarget(
            name: "LidAwakeCtl",
            dependencies: ["LidAwakeCore"],
            path: "Sources/LidAwakeCtl"
        ),
        .testTarget(
            name: "LidAwakeAppTests",
            dependencies: ["LidAwakeApp"]
        ),
        .testTarget(
            name: "LidAwakeCoreTests",
            dependencies: ["LidAwakeCore"],
            path: "Tests/LidAwakeCoreTests"
        ),
    ]
)
