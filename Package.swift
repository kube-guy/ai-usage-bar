// swift-tools-version:5.9
import PackageDescription

let package = Package(
    name: "ai-usage-bar",
    platforms: [.macOS(.v13)],
    targets: [
        .executableTarget(name: "AIUsageBar", path: "Sources/AIUsageBar")
    ]
)
