// swift-tools-version: 5.10
import PackageDescription

let package = Package(
    name: "AssistantShared",
    platforms: [.macOS(.v13)],
    products: [
        .library(name: "AssistantShared", targets: ["AssistantShared"])
    ],
    targets: [
        .target(name: "AssistantShared"),
        .testTarget(name: "AssistantSharedTests", dependencies: ["AssistantShared"])
    ]
)
