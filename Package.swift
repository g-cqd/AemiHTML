// swift-tools-version: 6.4
import PackageDescription

// AemiHTML: an HTML tokenizer and a content tree on Aemi's kernels, promoted from the archived ADHTML (ask roadmap 0139, reopened 2026-11-05). Swift 6 language mode, warnings as errors, the
// upcoming features that tighten existentials and imports, no unsafe flags: the same strictness as AemiMarkdown and AemiJSON.
let strictSettings: [SwiftSetting] = [
    .swiftLanguageMode(.v6),
    .treatAllWarnings(as: .error),
    .enableUpcomingFeature("ExistentialAny"),
    .enableUpcomingFeature("InferIsolatedConformances"),
    .enableUpcomingFeature("InternalImportsByDefault"),
    .enableUpcomingFeature("MemberImportVisibility")
]

// The tokenizer reads attacker-controlled bytes (a fetched page), so every unsafe construct in it is marked `unsafe` and justified where it stands.
let kernelSettings: [SwiftSetting] = strictSettings + [.strictMemorySafety()]

let aemiDependency: Package.Dependency = .package(
    url: "https://github.com/Aemi-Studio/aemi.git",
    revision: "4879ca7522a6277e9425c69309a801de43b57771"
)

let package = Package(
    name: "AemiHTML",
    platforms: [.macOS(.v15), .iOS(.v18), .tvOS(.v18), .watchOS(.v11), .visionOS(.v2)],
    products: [.library(name: "AemiHTML", targets: ["AemiHTML"])],
    dependencies: [aemiDependency],
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
            dependencies: ["AemiHTML", .product(name: "AemiTestKit", package: "aemi")],
            swiftSettings: strictSettings
        )
    ]
)
