// swift-tools-version: 6.1
import PackageDescription

let package = Package(
    name: "symaira-meet",
    platforms: [
        .macOS(.v15),
    ],
    products: [
        .library(name: "SymMeetCore", targets: ["SymMeetCore"]),
        .library(name: "SymMeetMCP", targets: ["SymMeetMCP"]),
        .executable(name: "symmeet", targets: ["symmeet"]),
    ],
    dependencies: [
        .package(url: "https://github.com/apple/swift-argument-parser.git", exact: "1.8.2"),
    ],
    targets: [
        .target(name: "SymMeetCore"),
        .target(name: "SymMeetMCP", dependencies: ["SymMeetCore"]),
        .executableTarget(
            name: "symmeet",
            dependencies: [
                "SymMeetCore",
                "SymMeetMCP",
                .product(name: "ArgumentParser", package: "swift-argument-parser"),
            ]
        ),
        .testTarget(
            name: "SymMeetCoreTests",
            dependencies: ["SymMeetCore"],
            resources: [.copy("../Fixtures/contracts")]
        ),
        .testTarget(name: "SymMeetMCPTests", dependencies: ["SymMeetMCP"]),
        .testTarget(name: "SymMeetCLITests", dependencies: ["SymMeetCore"]),
    ],
    swiftLanguageModes: [.v6]
)
