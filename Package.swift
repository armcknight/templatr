// swift-tools-version: 6.0
import PackageDescription

let package = Package(
    name: "templatr",
    platforms: [.macOS(.v14)],
    products: [
        .library(name: "ComponentManifest", targets: ["ComponentManifest"]),
        .executable(name: "validate-components", targets: ["validate-components"]),
    ],
    dependencies: [
        .package(url: "https://github.com/LebJe/TOMLKit", from: "0.6.0"),
    ],
    targets: [
        .target(
            name: "ComponentManifest",
            dependencies: [.product(name: "TOMLKit", package: "TOMLKit")]
        ),
        .executableTarget(
            name: "validate-components",
            dependencies: ["ComponentManifest"]
        ),
        .testTarget(
            name: "ComponentManifestTests",
            dependencies: ["ComponentManifest"]
        ),
    ]
)
