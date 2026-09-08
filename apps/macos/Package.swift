// swift-tools-version: 5.9
import PackageDescription
let package = Package(
    name: "FocusCount",
    platforms: [.macOS(.v13)],
    products: [.executable(name: "FocusCount", targets: ["FocusCount"])],
    targets: [.executableTarget(name: "FocusCount"), .testTarget(name: "FocusCountTests", dependencies: ["FocusCount"])]
)
