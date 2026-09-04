// swift-tools-version: 5.9
import PackageDescription

// Vendored copy of the `swift/` directory of mattmireles/kokoro-coreml — see README.md. The
// sources are byte-identical to upstream; only this manifest differs, and only by subtraction:
// upstream's two `kokoro-bench` executable products and their targets are dropped (command-line
// benchmarks, not shipped) along with upstream's test target, whose fixtures we do not vendor.
// The tools version and the platform floors are upstream's.
let package = Package(
    name: "KokoroPipeline",
    platforms: [
        .macOS(.v13),
        .iOS(.v16),
    ],
    products: [
        .library(name: "KokoroPipeline", targets: ["KokoroPipeline"]),
    ],
    targets: [
        .target(
            name: "KokoroPipeline",
            path: "Sources/KokoroPipeline"
        ),
        .testTarget(
            name: "KokoroPipelineTests",
            dependencies: ["KokoroPipeline"],
            path: "Tests/KokoroPipelineTests"
        ),
    ]
)
