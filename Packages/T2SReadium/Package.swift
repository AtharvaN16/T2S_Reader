// swift-tools-version: 6.0
import PackageDescription

// iOS only, on purpose: the Readium toolkit declares no macOS platform, and any package graph that
// contains it fails deployment-target validation on macOS. Keeping it here leaves the root package
// `swift test`-able on macOS. Test with `scripts/test-readium.sh` (xcodebuild on an iPhone simulator).
let package = Package(
    name: "T2SReadium",
    platforms: [.iOS(.v18)],
    products: [
        .library(name: "T2SReadium", targets: ["T2SReadium"]),
    ],
    dependencies: [
        .package(name: "T2S", path: "../.."),
        .package(url: "https://github.com/readium/swift-toolkit.git", exact: "3.11.0"),
    ],
    targets: [
        .target(
            name: "T2SReadium",
            dependencies: [
                .product(name: "T2SCore", package: "T2S"),
                .product(name: "T2SLibrary", package: "T2S"),
                .product(name: "ReadiumShared", package: "swift-toolkit"),
                .product(name: "ReadiumStreamer", package: "swift-toolkit"),
            ],
            swiftSettings: [.swiftLanguageMode(.v6)]
        ),
        .testTarget(
            name: "T2SReadiumTests",
            dependencies: [
                "T2SReadium",
                .product(name: "T2SCore", package: "T2S"),
                .product(name: "T2SLibrary", package: "T2S"),
            ],
            swiftSettings: [.swiftLanguageMode(.v6)]
        ),
    ]
)
