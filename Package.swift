// swift-tools-version: 6.1
import PackageDescription

let package = Package(
  name: "symaira-meet",
  platforms: [
    .macOS(.v15)
  ],
  products: [
    .library(name: "SymMeetCore", targets: ["SymMeetCore"]),
    .library(name: "SymMeetMCP", targets: ["SymMeetMCP"]),
    .library(name: "SymMeetWhisperKit", targets: ["SymMeetWhisperKit"]),
    .executable(name: "symmeet", targets: ["symmeet"]),
  ],
  dependencies: [
    .package(url: "https://github.com/apple/swift-argument-parser.git", exact: "1.8.2"),
    .package(url: "https://github.com/argmaxinc/argmax-oss-swift", exact: "1.0.0"),
  ],
  targets: [
    .target(name: "SymMeetCore"),
    .target(name: "SymMeetMCP", dependencies: ["SymMeetCore"]),
    .target(
      name: "SymMeetWhisperKit",
      dependencies: [
        "SymMeetCore",
        .product(name: "WhisperKit", package: "argmax-oss-swift"),
      ],
      resources: [.copy("THIRD_PARTY_NOTICES.md")]
    ),
    .executableTarget(
      name: "symmeet",
      dependencies: [
        "SymMeetCore",
        "SymMeetMCP",
        "SymMeetWhisperKit",
        .product(name: "ArgumentParser", package: "swift-argument-parser"),
      ]
    ),
    .testTarget(
      name: "SymMeetCoreTests",
      dependencies: ["SymMeetCore"],
      path: "Tests",
      exclude: ["SymMeetCLITests", "SymMeetMCPTests", "SymMeetWhisperKitTests"],
      sources: ["Support/FakeTranscriptionEngine.swift", "SymMeetCoreTests"],
      resources: [.copy("Fixtures/contracts")]
    ),
    .testTarget(name: "SymMeetMCPTests", dependencies: ["SymMeetMCP"]),
    .testTarget(name: "SymMeetCLITests", dependencies: ["SymMeetCore"]),
    .testTarget(name: "SymMeetWhisperKitTests", dependencies: ["SymMeetWhisperKit"]),
  ],
  swiftLanguageModes: [.v6]
)
