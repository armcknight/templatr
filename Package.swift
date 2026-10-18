// swift-tools-version: 6.0
import PackageDescription

let package = Package(
    name: "templatr",
    platforms: [.macOS(.v14)],
    products: [
        .library(name: "ComponentManifest", targets: ["ComponentManifest"]),
        .library(name: "Templatr", targets: ["Templatr"]),
        .executable(name: "validate-components", targets: ["validate-components"]),
        .executable(name: "templatr", targets: ["TemplatrCLI"]),
    ],
    dependencies: [
        .package(url: "https://github.com/LebJe/TOMLKit", from: "0.6.0"),
        .package(url: "https://github.com/jpsim/Yams", from: "5.1.0"),
    ],
    targets: [
        .target(
            name: "ComponentManifest",
            dependencies: [.product(name: "TOMLKit", package: "TOMLKit")]
        ),
        .target(
            name: "Templatr",
            dependencies: [
                "ComponentManifest",
                .product(name: "TOMLKit", package: "TOMLKit"),
                .product(name: "Yams", package: "Yams"),
            ]
        ),
        .executableTarget(
            name: "validate-components",
            dependencies: ["ComponentManifest"]
        ),
        .executableTarget(
            // The product is `templatr`. On a case-insensitive file system, a
            // target of that name would share its directories with Templatr's.
            name: "TemplatrCLI",
            dependencies: ["Templatr"]
        ),
        .testTarget(
            name: "ComponentManifestTests",
            dependencies: ["ComponentManifest", .product(name: "TOMLKit", package: "TOMLKit")]
        ),
        .testTarget(
            name: "TemplatrTests",
            dependencies: ["Templatr", "ComponentManifest"]
        ),
    ]
)
