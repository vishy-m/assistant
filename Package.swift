// swift-tools-version: 5.10
import PackageDescription

let package = Package(
    name: "AssistantShared",
    platforms: [.macOS(.v13)],
    products: [
        .library(name: "AssistantShared", targets: ["AssistantShared"]),
        .library(name: "AssistantStore", targets: ["AssistantStore"])
    ],
    dependencies: [
        .package(url: "https://github.com/groue/GRDB.swift.git", from: "6.29.0")
    ],
    targets: [
        .target(name: "AssistantShared"),
        .target(
            name: "AssistantStore",
            dependencies: [
                "AssistantShared",
                .product(name: "GRDB", package: "GRDB.swift")
            ]
        ),
        .testTarget(name: "AssistantSharedTests", dependencies: ["AssistantShared"]),
        .testTarget(
            name: "AssistantStoreTests",
            dependencies: ["AssistantStore", "AssistantShared"]
        )
    ]
)
