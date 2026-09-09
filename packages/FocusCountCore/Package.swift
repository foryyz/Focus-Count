// swift-tools-version: 5.9
import PackageDescription
let package = Package(
    name: "FocusCountCore",
    platforms: [.macOS(.v13), .iOS(.v17)],
    products: [.library(name: "FocusCountCore", targets: ["FocusCountCore"])],
    targets: [.target(name: "FocusCountCore"), .testTarget(name: "FocusCountCoreTests", dependencies: ["FocusCountCore"])]
)
