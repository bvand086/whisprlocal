// swift-tools-version: 5.9

import PackageDescription

let package = Package(
    name: "whisprlocal",
    platforms: [
        .macOS(.v14)
    ],
    dependencies: [
        .package(url: "https://github.com/exPHAT/SwiftWhisper.git", branch: "main")
    ],
    targets: [
        .executableTarget(
            name: "whisprlocal",
            dependencies: ["SwiftWhisper"]
        )
    ]
) 