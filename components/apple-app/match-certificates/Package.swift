// swift-tools-version: 6.0
import PackageDescription

// The apple-app component's list-match-certificates command, which
// `bin/list-match-certificates` builds and runs. It reads the certificates and
// profiles with the Security framework, so it builds only on macOS. It is a
// package of its own, and not a target of the templatr package, so that the
// templatr package still builds on Linux and its users do not get these
// dependencies.
let package = Package(
    name: "match-certificates",
    platforms: [.macOS(.v14)],
    products: [
        .executable(name: "list-match-certificates", targets: ["list-match-certificates"]),
    ],
    dependencies: [
        .package(url: "https://github.com/apple/swift-argument-parser", from: "1.5.0"),
        .package(url: "https://github.com/pointfreeco/swift-tagged", from: "0.10.0"),
    ],
    targets: [
        .target(
            name: "MatchCertificates",
            dependencies: [.product(name: "Tagged", package: "swift-tagged")]
        ),
        .executableTarget(
            name: "list-match-certificates",
            dependencies: [
                "MatchCertificates",
                .product(name: "ArgumentParser", package: "swift-argument-parser"),
            ]
        ),
        .testTarget(
            name: "MatchCertificatesTests",
            dependencies: ["MatchCertificates"]
        ),
    ]
)
