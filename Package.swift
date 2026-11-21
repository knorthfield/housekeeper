// swift-tools-version: 6.0
import PackageDescription

let package = Package(
    name: "Housekeeper",
    platforms: [.macOS(.v14)],
    products: [
        .library(name: "HousekeeperCore", targets: ["HousekeeperCore"]),
        .executable(name: "HousekeeperApp", targets: ["HousekeeperApp"]),
    ],
    dependencies: [
        .package(url: "https://github.com/weichsel/ZIPFoundation.git", from: "0.9.18"),
    ],
    targets: [
        .target(
            name: "HousekeeperCore",
            dependencies: [
                .product(name: "ZIPFoundation", package: "ZIPFoundation"),
            ]
        ),
        .executableTarget(
            name: "HousekeeperApp",
            dependencies: [
                "HousekeeperCore",
            ],
            resources: [.copy("Resources")]
        ),
        .executableTarget(
            name: "HousekeeperCLI",
            dependencies: ["HousekeeperCore"]
        ),
        .testTarget(
            name: "HousekeeperCoreTests",
            dependencies: ["HousekeeperCore"]
        ),
    ]
)
