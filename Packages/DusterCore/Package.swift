// swift-tools-version: 6.2
import PackageDescription

let package = Package(
    name: "DusterCore",
    platforms: [.macOS("27.0")],
    products: [.library(name: "DusterCore", targets: ["DusterCore"])],
    targets: [
        .target(
            name: "DusterCore",
            swiftSettings: [.treatAllWarnings(as: .error)]
        ),
        .testTarget(
            name: "DusterCoreTests",
            dependencies: ["DusterCore"],
            swiftSettings: [.treatAllWarnings(as: .error)]
        ),
    ]
)
