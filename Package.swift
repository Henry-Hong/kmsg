// swift-tools-version: 5.9
// The swift-tools-version declares the minimum version of Swift required to build this package.

import PackageDescription

let package = Package(
    name: "kmsg",
    platforms: [
        .macOS(.v13)
    ],
    products: [
        .executable(name: "kmsg", targets: ["kmsg"]),
        .library(name: "KakaoTalkAccessibility", targets: ["KakaoTalkAccessibility"])
    ],
    dependencies: [
        .package(url: "https://github.com/apple/swift-argument-parser.git", from: "1.3.0")
    ],
    targets: [
        .executableTarget(
            name: "kmsg",
            dependencies: [
                "KakaoTalkAccessibility",
                .product(name: "ArgumentParser", package: "swift-argument-parser")
            ]
        ),
        .target(
            name: "KakaoTalkAccessibility",
            dependencies: []
        ),
        .testTarget(
            name: "KakaoTalkAccessibilityTests",
            dependencies: ["KakaoTalkAccessibility"]
        )
    ]
)
