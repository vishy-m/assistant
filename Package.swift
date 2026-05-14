// swift-tools-version: 5.10
import PackageDescription

let package = Package(
    name: "AssistantShared",
    platforms: [.macOS(.v13)],
    products: [
        .library(name: "AssistantShared", targets: ["AssistantShared"]),
        .library(name: "AssistantStore", targets: ["AssistantStore"]),
        .library(name: "AssistantLLM", targets: ["AssistantLLM"])
    ],
    dependencies: [
        .package(url: "https://github.com/groue/GRDB.swift.git", from: "6.29.0")
    ],
    targets: [
        .target(name: "AssistantShared"),
        .target(name: "AssistantStore",
                dependencies: ["AssistantShared", .product(name: "GRDB", package: "GRDB.swift")]),
        .target(name: "AssistantLLM",
                dependencies: ["AssistantShared", "AssistantStore"]),
        .testTarget(name: "AssistantSharedTests", dependencies: ["AssistantShared"]),
        .testTarget(name: "AssistantStoreTests", dependencies: ["AssistantStore", "AssistantShared"]),
        .testTarget(name: "AssistantLLMTests", dependencies: ["AssistantLLM"])
    ]
)
