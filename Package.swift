// swift-tools-version: 5.10
import PackageDescription

let package = Package(
    name: "AssistantShared",
    platforms: [.macOS(.v13)],
    products: [
        .library(name: "AssistantShared", targets: ["AssistantShared"]),
        .library(name: "AssistantStore", targets: ["AssistantStore"]),
        .library(name: "AssistantLLM", targets: ["AssistantLLM"]),
        .library(name: "AssistantGCal", targets: ["AssistantGCal"])
    ],
    dependencies: [
        .package(url: "https://github.com/groue/GRDB.swift.git", from: "6.29.0"),
        .package(url: "https://github.com/openid/AppAuth-iOS.git", from: "1.7.5")
    ],
    targets: [
        .target(name: "AssistantShared"),
        .target(name: "AssistantStore",
                dependencies: ["AssistantShared", .product(name: "GRDB", package: "GRDB.swift")]),
        .target(name: "AssistantLLM",
                dependencies: ["AssistantShared", "AssistantStore"]),
        .target(name: "AssistantGCal",
                dependencies: [
                    "AssistantShared", "AssistantStore", "AssistantLLM",
                    .product(name: "AppAuth", package: "AppAuth-iOS")
                ]),
        .testTarget(name: "AssistantSharedTests", dependencies: ["AssistantShared"]),
        .testTarget(name: "AssistantStoreTests", dependencies: ["AssistantStore", "AssistantShared"]),
        .testTarget(name: "AssistantLLMTests", dependencies: ["AssistantLLM", "AssistantStore"]),
        .testTarget(name: "AssistantGCalTests", dependencies: ["AssistantGCal", "AssistantStore"])
    ]
)
