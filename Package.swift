// swift-tools-version: 6.4
import PackageDescription

let strictSettings: [SwiftSetting] = [
    .swiftLanguageMode(.v6),
    .treatAllWarnings(as: .error),
    .enableUpcomingFeature("ExistentialAny"),
    .enableUpcomingFeature("InferIsolatedConformances"),
    .enableUpcomingFeature("InternalImportsByDefault"),
    .enableUpcomingFeature("MemberImportVisibility")
]

let kernelSettings: [SwiftSetting] = strictSettings + [.strictMemorySafety()]

let aemiDependency: Package.Dependency = .package(
    url: "https://github.com/Aemi-Studio/aemi.git",
    revision: "340c49040faa49313d5632003d8224d9d0084fb0"
)

let markdownDependency: Package.Dependency = .package(
    url: "https://github.com/g-cqd/AemiMarkdown.git",
    revision: "269d403d416e3fb5aff9bab9087907d8eb322866"
)

let isDev = Context.environment["AEMIHTML_DEV"] != nil

var package = Package(
    name: "AemiHTML",
    platforms: [.macOS(.v15), .iOS(.v18), .tvOS(.v18), .watchOS(.v11), .visionOS(.v2)],
    products: [.library(name: "AemiHTML", targets: ["AemiHTML"])],
    dependencies: [aemiDependency, markdownDependency],
    targets: [
        .target(
            name: "AemiHTML",
            dependencies: [
                .product(name: "AemiKernel", package: "aemi"),
                .product(name: "AemiKernels", package: "aemi")
            ],
            swiftSettings: kernelSettings
        ),
        .testTarget(
            name: "AemiHTMLTests",
            dependencies: [
                "AemiHTML", .product(name: "AemiTestKit", package: "aemi"),
                .product(name: "AemiMarkdown", package: "AemiMarkdown")
            ],
            swiftSettings: strictSettings
        )
    ]
)

if isDev {
    package.dependencies.append(.package(url: "https://github.com/ordo-one/benchmark", from: "1.38.0"))
    package.targets.append(
        .executableTarget(
            name: "AemiHTMLSuite",
            dependencies: ["AemiHTML", .product(name: "Benchmark", package: "benchmark")],
            path: "Benchmarks/AemiHTMLSuite",
            swiftSettings: strictSettings,
            plugins: [.plugin(name: "BenchmarkPlugin", package: "benchmark")]
        )
    )
}
