// swift-tools-version: 6.0

import PackageDescription

let package = Package(
    name: "tailGateway",
    platforms: [
        .macOS(.v13)
    ],
    products: [
        .executable(name: "TailGateway", targets: ["TailGateway"])
    ],
    targets: [
        .executableTarget(
            name: "TailGateway"
        )
    ]
)
