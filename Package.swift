// swift-tools-version: 5.9
import PackageDescription

let package = Package(
    name: "SiftBar",
    platforms: [
        .macOS(.v13)
    ],
    products: [
        .executable(name: "SiftBar", targets: ["SiftBar"])
    ],
    targets: [
        .executableTarget(
            name: "SiftBar",
            path: "Sources/SiftBar"
        ),
        .testTarget(
            name: "SiftBarTests",
            dependencies: ["SiftBar"],
            path: "Tests/SiftBarTests"
        )
    ]
)
