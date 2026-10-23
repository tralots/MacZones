// swift-tools-version:5.10
import PackageDescription

let package = Package(
    name: "MacZones",
    platforms: [.macOS(.v14)],
    targets: [
        .executableTarget(
            name: "MacZones",
            path: "Sources/MacZones",
            linkerSettings: [.linkedFramework("Carbon")]
        ),
        .testTarget(
            name: "MacZonesTests",
            dependencies: ["MacZones"],
            path: "Tests/MacZonesTests"
        ),
    ]
)
