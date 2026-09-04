// swift-tools-version: 6.0
import PackageDescription

// Out of the root package on purpose: KokoroSwift runs on MLX, and MLX needs the compiled Metal
// library that mlx-swift ships as a built resource. `swift test` neither builds nor stages it, so a
// root-package dependency would break CI's `swift test` and the iOS simulator cannot provide it
// either. Keeping Kokoro here leaves the root package MLX-free. Test with `scripts/test-kokoro.sh`
// (xcodebuild on macOS, where MLX runs on the Apple silicon GPU). Pins are exact: the resolved
// revisions must stay the ones the Plan 0 spike harness measured.
let package = Package(
    name: "T2SKokoro",
    platforms: [.iOS(.v18), .macOS(.v15)],
    products: [
        .library(name: "T2SKokoro", targets: ["T2SKokoro"]),
    ],
    dependencies: [
        .package(name: "T2S", path: "../.."),
        .package(url: "https://github.com/mlalma/kokoro-ios", exact: "1.0.11"),
        // Vendored: upstream depends on `weichsel/ZIPFoundation`, whose SwiftPM identity collides
        // with Readium's fork of the same library and makes the app's graph unresolvable. A local
        // package takes the identity `mlxutilslibrary` for the whole graph — see its README.
        .package(name: "MLXUtilsLibrary", path: "../MLXUtilsLibrary"),
        // Vendored: the upstream repo root has no Package.swift — the package lives in its
        // `swift/` subdirectory, which SwiftPM cannot consume by URL. See its README.
        .package(name: "KokoroPipeline", path: "../KokoroPipeline"),
    ],
    targets: [
        .target(
            name: "T2SKokoro",
            dependencies: [
                .product(name: "T2SCore", package: "T2S"),
                .product(name: "T2SAudio", package: "T2S"),
                .product(name: "KokoroSwift", package: "kokoro-ios"),
                .product(name: "MLXUtilsLibrary", package: "MLXUtilsLibrary"),
                .product(name: "KokoroPipeline", package: "KokoroPipeline"),
            ],
            swiftSettings: [.swiftLanguageMode(.v6)]
        ),
        .testTarget(
            name: "T2SKokoroTests",
            dependencies: [
                "T2SKokoro",
                .product(name: "T2SCore", package: "T2S"),
                .product(name: "T2SAudio", package: "T2S"),
                // For NpzArchiveTests: the vendored package's zip reader is tested here, where the
                // package is already in the graph.
                .product(name: "MLXUtilsLibrary", package: "MLXUtilsLibrary"),
                .product(name: "KokoroPipeline", package: "KokoroPipeline"),
            ],
            swiftSettings: [.swiftLanguageMode(.v6)]
        ),
    ]
)
