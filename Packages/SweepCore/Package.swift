// swift-tools-version: 6.2
import PackageDescription

let package = Package(
    name: "SweepCore",
    platforms: [.macOS("27.0")],
    products: [.library(name: "SweepCore", targets: ["SweepCore"])],
    targets: [
        .target(
            name: "SweepCore",
            swiftSettings: [.treatAllWarnings(as: .error)]
        ),
        .testTarget(
            name: "SweepCoreTests",
            dependencies: ["SweepCore"],
            swiftSettings: [.treatAllWarnings(as: .error)]
        ),
    ]
)
