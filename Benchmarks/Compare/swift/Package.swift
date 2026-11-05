// swift-tools-version: 6.4
import PackageDescription

// The Swift side of the tokenizer comparison (Benchmarks/Compare): AemiHTML. Release only.
let package = Package(
    name: "CompareHTML",
    platforms: [.macOS(.v26)],
    dependencies: [.package(path: "../../..")],
    targets: [
        .executableTarget(name: "CompareHTML", dependencies: [.product(name: "AemiHTML", package: "AemiHTML")])
    ]
)
