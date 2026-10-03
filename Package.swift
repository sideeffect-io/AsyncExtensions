// swift-tools-version:5.9
// The swift-tools-version declares the minimum version of Swift required to build this package.

import PackageDescription

let package = Package(
    name: "AsyncExtensions",
    platforms: [
            .iOS("18.0"),
            .macOS("15.0"),
            .tvOS("18.0"),
            .watchOS("11.0"),
            .visionOS("2.0")
        ],
    products: [
        .library(
            name: "AsyncExtensions",
            targets: ["AsyncExtensions"]),
    ],
    dependencies: [
        .package(url: "https://github.com/apple/swift-async-algorithms.git", .upToNextMajor(from: "1.0.0")),
        .package(url: "https://github.com/apple/swift-collections.git", .upToNextMajor(from: "1.0.3"))
    ],
    targets: [
        .target(
            name: "AsyncExtensions",
            dependencies: [.product(name: "Collections", package: "swift-collections")],
            path: "Sources"
//            ,
//            swiftSettings: [
//              .unsafeFlags([
//                "-Xfrontend", "-warn-concurrency",
//                "-Xfrontend", "-enable-actor-data-race-checks",
//              ])
//            ]
        ),
        .testTarget(
            name: "AsyncExtensionsTests",
            dependencies: [
                "AsyncExtensions",
                .product(name: "AsyncAlgorithms", package: "swift-async-algorithms")
            ],
            path: "Tests"),
    ]
)
