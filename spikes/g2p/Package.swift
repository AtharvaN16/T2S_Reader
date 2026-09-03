// swift-tools-version: 6.0
// Plan 0 Task 6 (§7.1): macOS tool that prints MisakiSwift's phonemes for each stdin line, so
// they can be diffed against the Python `misaki` reference. Throwaway; nothing imports it.
import PackageDescription

let package = Package(
    name: "g2pdump",
    platforms: [.macOS(.v15)],
    dependencies: [
        .package(url: "https://github.com/mlalma/MisakiSwift", exact: "1.0.6"),
        .package(name: "T2S", path: "../.."),   // the app's own TextNormalizer, to phonemize what the engine really receives
    ],
    targets: [
        .executableTarget(
            name: "g2pdump",
            dependencies: [.product(name: "MisakiSwift", package: "MisakiSwift")],
            swiftSettings: [.swiftLanguageMode(.v5)]
        ),
        .executableTarget(
            name: "normdump",
            dependencies: [.product(name: "T2SCore", package: "T2S")],
            swiftSettings: [.swiftLanguageMode(.v6)]
        ),
    ]
)
