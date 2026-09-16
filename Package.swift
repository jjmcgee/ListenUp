// swift-tools-version: 6.0
import PackageDescription

let package = Package(
    name: "ListenUp",
    platforms: [
        .iOS("27.0"),
        .macOS(.v15),
        .watchOS("27.0")
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
