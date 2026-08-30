// swift-tools-version: 6.3
// The swift-tools-version declares the minimum version of Swift required to build this package.

import PackageDescription

let package = Package(
    name: "RedisSessionDriver",
    platforms: [
        // Vapor and RediStack require 10.15; without this SwiftPM defaults to 10.13
        // and fails dependency resolution on macOS.
        .macOS(.v10_15)
    ],
    products: [
        // Products define the executables and libraries a package produces, making them visible to other packages.
        .library(
            name: "RedisSessionDriver",
            targets: ["RedisSessionDriver"]),
    ],
    dependencies: [
        // 💧 A server-side Swift web framework.
        .package(url: "https://github.com/vapor/vapor.git", from: "4.99.0"),
        // 🔴 Redis-backed sessions.
        .package(url: "https://github.com/vapor/redis.git", from: "4.10.0"),
    ],
    targets: [
        // Targets are the basic building blocks of a package, defining a module or a test suite.
        // Targets can depend on other targets in this package and products from dependencies.
        .target(
            name: "RedisSessionDriver",
            dependencies: [
                .product(name: "Vapor", package: "vapor"),
                .product(name: "Redis", package: "redis"),
            ]),
        .testTarget(
            name: "RedisSessionDriverTests",
            dependencies: [
                "RedisSessionDriver",
                .product(name: "XCTVapor", package: "vapor"),
            ]
        ),
    ]
)
