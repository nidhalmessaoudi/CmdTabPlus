// swift-tools-version: 5.9
import PackageDescription

let package = Package(
    name: "CmdTabPlus",
    platforms: [.macOS(.v13)],
    products: [.executable(name: "CmdTabPlus", targets: ["CmdTabPlus"])],
    targets: [
        .target(name: "SwitchingCore"),
        .executableTarget(name: "CmdTabPlus", dependencies: ["SwitchingCore"]),
        .testTarget(name: "SwitchingCoreTests", dependencies: ["SwitchingCore"]),
    ]
)
