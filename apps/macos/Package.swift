// swift-tools-version: 5.9
import PackageDescription
let package = Package(
    name: "FocusCount",
    platforms: [.macOS(.v13)],
    products: [.executable(name: "FocusCount", targets: ["FocusCount"])],
    dependencies: [.package(path: "../../packages/FocusCountCore")],
    targets: [.executableTarget(name: "FocusCount", dependencies: ["FocusCountCore"]), .testTarget(name: "FocusCountTests", dependencies: ["FocusCount"])]
)
