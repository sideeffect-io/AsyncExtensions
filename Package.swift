// swift-tools-version:5.5
// The swift-tools-version declares the minimum version of Swift required to build this package.

import PackageDescription

let package = Package(
    name: "AsyncExtensions",
    platforms: [
            .iOS(.v13),
            .macOS(.v10_15),
            .tvOS(.v13),
            .watchOS(.v6)
        ],
    products: [
        .library(
            name: "AsyncExtensions",
            targets: ["AsyncExtensions"]),
    ],
    dependencies: [
        .package(url: "https://github.com/apple/swift-collections.git", .upToNextMajor(from: "1.0.3")),
        .package(url: "https://github.com/OpenCombine/OpenCombine.git", from: "0.14.0"),
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
                .product(name: "OpenCombine", package: "OpenCombine", condition: .when(platforms: [.linux])),
            ],
            path: "Tests"),
    ]
)
