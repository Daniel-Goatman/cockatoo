// swift-tools-version: 5.10
import PackageDescription

let package = Package(
    name: "cockatoo",
    platforms: [.macOS(.v14)],
    products: [
        .library(name: "LearnerCore", targets: ["LearnerCore"]),
        .executable(name: "packtool", targets: ["packtool"]),
        .executable(name: "learnerctl", targets: ["learnerctl"]),
        .executable(name: "Cockatoo", targets: ["Cockatoo"]),
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
        .executableTarget(name: "Cockatoo", dependencies: ["LearnerCore"]),
        .testTarget(name: "LearnerCoreTests", dependencies: ["LearnerCore"]),
    ]
)
