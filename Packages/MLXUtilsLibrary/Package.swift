// swift-tools-version: 6.2
import PackageDescription

// Vendored copy of mlalma/MLXUtilsLibrary 0.0.6 — see README.md. Two deliberate changes from
// upstream: the `weichsel/ZIPFoundation` dependency is gone (the whole reason this copy exists),
// and `mlx-swift` is pinned exact to the revision the Plan 0 spike measured rather than `from:`.
// The upstream test target is dropped with it: its fixture is a 14 MB `voices.npz`, and the
// replacement zip reader is tested in `Packages/T2SKokoro`.
let package = Package(
    name: "MLXUtilsLibrary",
    platforms: [
        .iOS(.v18), .macOS(.v15),
    ],
    products: [
        .library(
            name: "MLXUtilsLibrary",
            targets: ["MLXUtilsLibrary"]
        ),
    ],
    dependencies: [
        .package(url: "https://github.com/ml-explore/mlx-swift", exact: "0.30.2"),
    ],
    targets: [
        .target(
            name: "MLXUtilsLibrary",
            dependencies: [
                .product(name: "MLX", package: "mlx-swift"),
            ]
        ),
    ]
)
