// swift-tools-version: 6.0
import PackageDescription

let package = Package(
    name: "ListenUp",
    platforms: [
        .iOS(.v18),
        .macOS(.v15),
        .watchOS(.v11)
    ],
    products: [
        .library(name: "ListenUp", targets: ["ListenUp"]),
    ],
    targets: [
        .target(
            name: "ListenUp",
            path: "ListenUp",
            exclude: ["ListenUpApp.swift", "Info.plist", "Assets.xcassets"]
        ),
        .testTarget(
            name: "ListenUpTests",
            dependencies: ["ListenUp"],
            path: "Tests/ListenUpTests"
        )
    ]
)
