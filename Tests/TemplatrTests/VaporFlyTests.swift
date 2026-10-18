import Foundation
import Testing
@testable import Templatr

// The parts of mtg's files that the vapor-fly rules read, cut down.

let mtgPackage = """
    // swift-tools-version: 5.9
    import PackageDescription

    let package = Package(
        name: "mtg-server",
        platforms: [.macOS(.v14)],
        products: [
            .executable(name: "mtg-server", targets: ["mtg-server"]),
        ],
        dependencies: [
            .package(url: "https://github.com/vapor/vapor", from: "4.0.0"),
            .package(url: "https://github.com/vapor/fluent", from: "4.0.0"),
        ],
        targets: [
            .executableTarget(
                name: "mtg-server",
                dependencies: [.product(name: "Vapor", package: "vapor")],
                path: "mtg-server"
            ),
        ]
    )

    """

let mtgFlyToml = """
    app = "mtg-server"
    primary_region = "sjc"  # the nearest West-coast region

    [build]
      dockerfile = "Dockerfile"

    [env]
      MTG_SERVER_PORT = "8080"

    [http_service]
      internal_port = 8080
      force_https = true
      auto_stop_machines = "stop"
      auto_start_machines = true
      min_machines_running = 0

      [http_service.concurrency]
        type = "requests"
        hard_limit = 250
        soft_limit = 200

      [[http_service.checks]]
        interval = "30s"
        timeout = "5s"
        grace_period = "15s"
        method = "GET"
        path = "/api/status"

    [[vm]]
      size = "shared-cpu-1x"
      memory = "1gb"

    """

let mtgDockerfile = """
    # syntax=docker/dockerfile:1
    FROM swift:6.0-jammy AS build
    WORKDIR /build
    COPY Package.swift Package.resolved ./
    RUN swift package resolve
    COPY mtg-server mtg-server
    RUN swift build -c release --product mtg-server

    FROM swift:6.0-jammy-slim
    ARG GIT_SHA=unknown
    ENV MTG_GIT_SHA=$GIT_SHA
    ENTRYPOINT ["./mtg-server"]

    """

let mtgInputs: [String: String?] = [
    "product": "mtg-server",
    "fly_app": "mtg-server",
    "fly_org": "personal",
    "primary_region": "sjc",
    "health_check_path": "/api/status",
    "internal_port": "8080",
    "swift_version": "6.0",
    "linux_distribution": "jammy",
    "fly_secrets": "",
    "default_branch": "main",
]

/// Detection and inference with this repository's vapor-fly manifest, as
/// bootstrap runs them.
@Suite("vapor-fly")
struct VaporFlyTests {
    let repository: Directory

    init() throws {
        repository = try Directory()
    }

    var vaporFly: ResolvedComponent? {
        get throws { try resolve("vapor-fly", in: repository.root) }
    }

    @Test func readsTheFilesInItsDirectory() throws {
        try repository.write("Package.swift", mtgPackage)
        #expect(try vaporFly == nil)
    }

    @Test func mtg() throws {
        try repository.write("server/Package.swift", mtgPackage)
        try repository.write("server/fly.toml", mtgFlyToml)
        try repository.write("server/Dockerfile", mtgDockerfile)
        #expect(try #require(try vaporFly).inputs == mtgInputs)
    }

    @Test func newServerHasOnlyAPackage() throws {
        try repository.write("server/Package.swift", mtgPackage)
        let inputs = try #require(try vaporFly).inputs
        #expect(inputs["product"] == "mtg-server")
        #expect(inputs["swift_version"] == "5.9")
        #expect(inputs["health_check_path"] == "/healthz")
        #expect(inputs["internal_port"] == "8080")
        #expect(inputs["linux_distribution"] == "noble")
        // Asked for.
        #expect(inputs["fly_app"] == .some(nil))
        #expect(inputs["primary_region"] == .some(nil))
    }

    @Test func packageWithoutVapor() throws {
        try repository.write(
            "server/Package.swift",
            mtgPackage.replacingOccurrences(of: "github.com/vapor/vapor", with: "github.com/hummingbird-project/hummingbird")
        )
        #expect(try vaporFly == nil)
    }

    @Test func libraryThatUsesVapor() throws {
        try repository.write(
            "server/Package.swift", mtgPackage.replacingOccurrences(of: #".executable(name: "mtg-server""#, with: #".library(name: "mtg-server""#)
        )
        #expect(try vaporFly == nil)
    }

    @Test func packageInADependencyCheckout() throws {
        try repository.write("server/.build/checkouts/vapor/Package.swift", mtgPackage)
        #expect(try vaporFly == nil)
    }

    @Test func healthCheckInServices() throws {
        try repository.write("server/Package.swift", mtgPackage)
        try repository.write(
            "server/fly.toml", "app = \"demo\"\n\n[[services]]\n  internal_port = 8080\n\n  [[services.http_checks]]\n    path = \"/status\"\n"
        )
        #expect(try #require(try vaporFly).inputs["health_check_path"] == "/status")
    }

    @Test func dockerfileProductComesFirst() throws {
        try repository.write(
            "server/Package.swift",
            mtgPackage.replacingOccurrences(
                of: #".executable(name: "mtg-server""#,
                with: #".executable(name: "migrate", targets: ["migrate"]),"# + "\n" + #"        .executable(name: "mtg-server""#
            )
        )
        try repository.write("server/Dockerfile", mtgDockerfile)
        #expect(try #require(try vaporFly).inputs["product"] == "mtg-server")
    }

    /// Set MTG_REPOSITORY to a checkout of mtg to run it.
    @Test(.enabled(if: ProcessInfo.processInfo.environment["MTG_REPOSITORY"] != nil))
    func mtgCheckout() throws {
        let checkout = URL(fileURLWithPath: ProcessInfo.processInfo.environment["MTG_REPOSITORY"]!)
        let vaporFly = try #require(try resolve("vapor-fly", in: checkout))
        #expect(vaporFly.missing.map(\.name) == [])
    }
}
