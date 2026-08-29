// swift-tools-version: 6.0
import PackageDescription

let package = Package(
    name: "MosaicLite",
    defaultLocalization: "en",
    platforms: [.macOS(.v15)],
    products: [
        .executable(name: "MosaicLite", targets: ["MosaicLite"])
    ],
    targets: [
        .executableTarget(
            name: "MosaicLite",
            path: "Sources/MosaicLite",
            resources: [.process("Resources")]
        ),
        .testTarget(
            name: "MosaicLiteTests",
            dependencies: ["MosaicLite"],
            path: "Tests/MosaicLiteTests"
        )
    ]
)
