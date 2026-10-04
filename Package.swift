// swift-tools-version:6.1
// The swift-tools-version declares the minimum version of Swift required to build this package.

import PackageDescription

let package = Package(
    name: "AsyncExtensions",
    platforms: [
            .iOS(.v18),
            .macOS(.v15),
            .tvOS(.v18),
            .watchOS(.v11)
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
    ],
    swiftLanguageModes: [.v5]
)
