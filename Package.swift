// swift-tools-version: 6.2
import PackageDescription

let package = Package(
    name: "Clipt",
    platforms: [.macOS(.v26)],
    targets: [
        .target(name: "CliptCore", linkerSettings: [.linkedLibrary("sqlite3")]),
        .executableTarget(name: "Clipt", dependencies: ["CliptCore"]),
        // XCTest and swift-testing need Xcode; tests run as a plain executable.
        .executableTarget(name: "CliptTests", dependencies: ["CliptCore"]),
    ]
)
