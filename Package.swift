// swift-tools-version: 5.9
import PackageDescription
let package = Package(name: "AlienPing", platforms: [.macOS(.v14)], products: [.executable(name: "AlienPing", targets: ["AlienPing"])], targets: [.target(name: "AlienCore"), .executableTarget(name: "AlienPing", dependencies: ["AlienCore"]), .executableTarget(name: "AlienCoreTests", dependencies: ["AlienCore"], path: "Tests/AlienCoreTests")])
