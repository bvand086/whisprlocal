// swift-tools-version: 5.9

import PackageDescription

let package = Package(
    name: "whisprlocal",
    platforms: [.macOS(.v14)],
    products: [
        .executable(name: "whisprlocal", targets: ["whisprlocal"]),
    ],
    dependencies: [
        .package(url: "https://github.com/exPHAT/SwiftWhisper.git", branch: "master")
    ],
    targets: [
        .executableTarget(
            name: "whisprlocal",
            dependencies: ["SwiftWhisper"]
        )
    ]
) 