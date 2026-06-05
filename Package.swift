// swift-tools-version: 5.9
import PackageDescription

let package = Package(
    name: "macmem",
    platforms: [.macOS(.v13)],
    products: [
        .library(name: "MacMemCore", targets: ["MacMemCore"]),
        .executable(name: "macmem", targets: ["macmem"]),
    ],
    dependencies: [
        .package(url: "https://github.com/apple/swift-argument-parser", from: "1.3.0"),
    ],
    targets: [
        .target(name: "MacMemCore"),
        .executableTarget(
            name: "macmem",
            dependencies: [
                "MacMemCore",
                .product(name: "ArgumentParser", package: "swift-argument-parser"),
            ]
        ),
        .testTarget(name: "MacMemCoreTests", dependencies: ["MacMemCore"]),
    ]
)
