// swift-tools-version: 5.9
import PackageDescription

let package = Package(
    name: "OneStepCore",
    platforms: [.macOS(.v13)],
    products: [.library(name: "OneStepCore", targets: ["OneStepCore"])],
    targets: [
        .target(name: "OneStepCore", path: "OneStep/Core"),
        .testTarget(name: "OneStepCoreTests", dependencies: ["OneStepCore"], path: "Tests")
    ]
)
