// swift-tools-version: 5.10
import PackageDescription

let package = Package(
    name: "cockatoo",
    platforms: [.macOS(.v14)],
    products: [
        .library(name: "LearnerCore", targets: ["LearnerCore"]),
        .executable(name: "packtool", targets: ["packtool"]),
        .executable(name: "learnerctl", targets: ["learnerctl"]),
        .executable(name: "CockatooDev", targets: ["CockatooDev"]),
    ],
    dependencies: [
        .package(url: "https://github.com/groue/GRDB.swift.git", from: "6.29.0"),
    ],
    targets: [
        .target(
            name: "LearnerCore",
            dependencies: [.product(name: "GRDB", package: "GRDB.swift")]
        ),
        .executableTarget(name: "packtool", dependencies: ["LearnerCore"]),
        .executableTarget(name: "learnerctl", dependencies: ["LearnerCore"]),
        // Single source of truth for the app: the same folder the Xcode app
        // target synchronizes with. `swift run CockatooDev` = dev loop.
        .executableTarget(
            name: "CockatooDev",
            dependencies: ["LearnerCore"],
            path: "App/Cockatoo/Cockatoo",
            exclude: ["Assets.xcassets", "Cockatoo.entitlements"],
            // The starter pack (a copy of packs/build/de-2026.07.json) ships
            // in the bundle so onboarding is one click. The Xcode app target
            // picks it up via the synchronized folder.
            resources: [.copy("Resources")]
        ),
        .testTarget(name: "LearnerCoreTests", dependencies: ["LearnerCore"]),
    ]
)
