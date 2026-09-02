// swift-tools-version: 6.0
import PackageDescription

let package = Package(
    name: "T2S",
    platforms: [.iOS(.v18), .macOS(.v15)],
    products: [
        .library(name: "T2SCore", targets: ["T2SCore"]),
    ],
    targets: [
        .target(name: "T2SCore", swiftSettings: [.swiftLanguageMode(.v6)]),
        .testTarget(
            name: "T2SCoreTests",
            dependencies: ["T2SCore"],
            resources: [.copy("Fixtures")],
            swiftSettings: [.swiftLanguageMode(.v6)]
        ),
    ]
)
