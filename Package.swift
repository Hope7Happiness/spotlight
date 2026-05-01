// swift-tools-version: 6.0

import PackageDescription

let package = Package(
    name: "QuickAsk",
    platforms: [
        .macOS(.v14)
    ],
    products: [
        .executable(name: "QuickAsk", targets: ["QuickAsk"])
    ],
    targets: [
        .executableTarget(
            name: "QuickAsk"
        )
    ]
)
