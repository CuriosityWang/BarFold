// swift-tools-version: 6.0
import PackageDescription

let package = Package(
    name: "BarFold",
    platforms: [.macOS(.v15)],
    products: [.executable(name: "BarFold", targets: ["BarFold"])],
    targets: [
        .target(name: "BarFoldCore"),
        .target(name: "MenuBarBridge", publicHeadersPath: "include"),
        .executableTarget(name: "BarFold", dependencies: ["BarFoldCore", "MenuBarBridge"]),
        .testTarget(name: "BarFoldCoreTests", dependencies: ["BarFoldCore"]),
    ]
)
