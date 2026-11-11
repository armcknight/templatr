import Foundation
import Testing
@testable import Templatr

// The parts of the tools' packages that the swift-cli rules read, cut down.

/// superlinear: one executable target and no products.
let superlinearPackage = """
    // swift-tools-version: 6.0
    import PackageDescription

    let package = Package(
        name: "superlinear",
        platforms: [.macOS(.v14)],
        targets: [
            .executableTarget(
                name: "superlinear",
                path: "Sources/superlinear"
            ),
            .testTarget(name: "superlinearTests", dependencies: ["superlinear"]),
        ]
    )

    """

/// templatr: two executable products, of which the tool is the one whose
/// target has the version, and whose target's name is not the product's.
let templatrPackage = """
    // swift-tools-version: 6.0
    import PackageDescription

    let package = Package(
        name: "templatr",
        products: [
            .library(name: "Templatr", targets: ["Templatr"]),
            .executable(name: "validate-components", targets: ["validate-components"]),
            .executable(name: "templatr", targets: ["TemplatrCLI"]),
        ],
        targets: [
            .target(name: "Templatr"),
            .executableTarget(name: "validate-components"),
            .executableTarget(
                // The product is `templatr`.
                name: "TemplatrCLI",
                dependencies: ["Templatr"]
            ),
        ]
    )

    """

/// armcknight/tools: many executable targets that share a version in a
/// library.
let toolsPackage = """
    // swift-tools-version: 6.1
    import PackageDescription

    let package = Package(
        name: "tools",
        targets: [
            .target(name: "Shared"),
            .executableTarget(name: "vrsn", dependencies: ["Shared"]),
            .executableTarget(name: "prepare-release", dependencies: ["Shared"]),
        ]
    )

    """

let toolsRelease = """
    name: release

    on:
      push:
        tags:
          - '[0-9]+.[0-9]+.[0-9]+'

    jobs:
      release:
        uses: armcknight/workflows/.github/workflows/swiftpm-cask-release.yml@4
        with:
          cask-name: tools
          binaries: |
            vrsn
            prepare-release
          version-file: Sources/Shared/Version.swift
          version-regex: '.*toolsVersion.*"([^"]+)".*'
          sign: true
          match-git-url: git@github.com:armcknight/fastlane-match.git
          team-id: 29274SF4VL
          bundle-id: io.mcknight.tools
        secrets: inherit

    """

/// Detection and inference with this repository's swift-cli manifest, as
/// bootstrap runs them.
@Suite("swift-cli")
struct SwiftCLITests {
    let repository: Directory

    init() throws {
        repository = try Directory()
    }

    var swiftCLI: ResolvedComponent? {
        get throws { try resolve("swift-cli", in: repository.root) }
    }

    @Test func superlinear() throws {
        try repository.write("Package.swift", superlinearPackage)
        try repository.write("Sources/superlinear/Version.swift", "extension Superlinear {\n    static let version = \"2.0.0\"\n}\n")
        let inputs = try #require(try swiftCLI).inputs
        #expect(inputs["name"] == "superlinear")
        #expect(inputs["binaries"] == "superlinear")
        #expect(inputs["version_file"] == "Sources/superlinear/Version.swift")
        #expect(inputs["vrsn_key"] == "version")
        #expect(inputs["cask"] == "superlinear")
        #expect(inputs["distribution"] == "cask")
        #expect(inputs["sign"] == "true")
        // Asked for, until a release workflow names them.
        #expect(inputs["team_id"] == .some(nil))
    }

    @Test func theProductWhoseTargetHasTheVersion() throws {
        try repository.write("Package.swift", templatrPackage)
        try repository.write("Sources/TemplatrCLI/Version.swift", "extension TemplatrCommand {\nstatic let version = \"2.1.1\"\n}\n")
        try repository.write("Sources/validate-components/Main.swift", "print(\"valid\")\n")
        let inputs = try #require(try swiftCLI).inputs
        #expect(inputs["name"] == "templatr")
        #expect(inputs["binaries"] == "templatr")
        #expect(inputs["version_file"] == "Sources/TemplatrCLI/Version.swift")
    }

    @Test func toolsShareAVersionInALibrary() throws {
        try repository.write("Package.swift", toolsPackage)
        try repository.write("Sources/Shared/Version.swift", "public let toolsVersion = \"5.2.0\"\n")
        try repository.write(".github/workflows/release.yml", toolsRelease)
        let inputs = try #require(try swiftCLI).inputs
        #expect(inputs["name"] == "tools")
        #expect(inputs["binaries"] == "vrsn prepare-release")
        #expect(inputs["version_file"] == "Sources/Shared/Version.swift")
        #expect(inputs["vrsn_key"] == "toolsVersion")
        #expect(inputs["cask"] == "tools")
        #expect(inputs["distribution"] == "cask")
        #expect(inputs["sign"] == "true")
        #expect(inputs["match_git_url"] == "git@github.com:armcknight/fastlane-match.git")
        #expect(inputs["team_id"] == "29274SF4VL")
        #expect(inputs["bundle_id"] == "io.mcknight.tools")
    }

    @Test func aGitHubRelease() throws {
        try repository.write("Package.swift", superlinearPackage)
        try repository.write(".github/workflows/release.yml", """
            jobs:
              release:
                uses: armcknight/workflows/.github/workflows/github-release.yml@4

            """)
        #expect(try #require(try swiftCLI).inputs["distribution"] == "github-release")
    }

    @Test func aNewToolGetsVersionSwiftInItsTarget() throws {
        try repository.write("Package.swift", superlinearPackage.replacingOccurrences(of: "superlinear", with: "mytool"))
        let inputs = try #require(try swiftCLI).inputs
        #expect(inputs["name"] == "mytool")
        #expect(inputs["version_file"] == "Sources/mytool/Version.swift")
        #expect(inputs["vrsn_key"] == "version")
    }

    @Test(arguments: [
        "App.xcodeproj/project.pbxproj", "apple/App.xcodeproj/project.pbxproj", "App.xcworkspace/contents.xcworkspacedata",
        "project.yml", "apple/project.yml",
    ])
    func anAppIsNotATool(path: String) throws {
        try repository.write("Package.swift", superlinearPackage)
        try repository.write(path, "existing\n")
        #expect(try swiftCLI == nil)
    }

    @Test func aServerIsNotATool() throws {
        try repository.write("Package.swift", mtgPackage)
        #expect(try swiftCLI == nil)
        // Nor is a server in server/, which vapor-fly has.
        try repository.delete("Package.swift")
        try repository.write("server/Package.swift", mtgPackage)
        #expect(try swiftCLI == nil)
    }

    @Test func aLibraryIsNotATool() throws {
        try repository.write("Package.swift", toolsPackage.replacingOccurrences(of: ".executableTarget", with: ".target"))
        #expect(try swiftCLI == nil)
    }

    /// Set SWIFT_CLI_REPOSITORIES to checkouts of tools, separated by colons,
    /// to run it.
    @Test(.enabled(if: ProcessInfo.processInfo.environment["SWIFT_CLI_REPOSITORIES"] != nil))
    func checkouts() throws {
        for path in ProcessInfo.processInfo.environment["SWIFT_CLI_REPOSITORIES"]!.split(separator: ":") {
            let checkout = URL(fileURLWithPath: String(path))
            let swiftCLI = try #require(try resolve("swift-cli", in: checkout), "\(path)")
            #expect(swiftCLI.missing.map(\.name) == [], "\(path)")
        }
    }
}

/// `templatr bootstrap` on a new repository with only a Package.swift.
@Suite struct SwiftCLIBootstrapTests {
    let project: Directory
    let stubs = Stubs()

    init() throws {
        project = try Directory()
        try project.write("Package.swift", superlinearPackage.replacingOccurrences(of: "superlinear", with: "my-tool"))
        _ = try ProcessRunner().run(["git", "init", "-q"], input: nil, in: project.root)
    }

    func bootstrap(_ answers: [String: String]) async throws -> BootstrapResult {
        let bootstrapper = Bootstrapper(templates: Templates(root: repositoryRoot, tag: "v1", tags: []), services: stubs.services())
        return try await bootstrapper.bootstrap(
            repository: project.root,
            options: BootstrapOptions(answers: ["swift-cli": answers], links: [], setSecret: { _ in false })
        )
    }

    @Test func aNewToolGetsItsFiles() async throws {
        // A GitHub release, so that no step asks GitHub for the cask, and
        // nothing to sign.
        let result = try await bootstrap(["distribution": "github-release", "sign": "false"])
        let report = result.report
        #expect(report.failedSteps.isEmpty, "\(report.failedSteps)")
        #expect(report.humanSteps.filter { $0.component == "swift-cli" }.isEmpty, "\(report.humanSteps)")
        #expect(report.blockedSteps.filter { $0.component == "swift-cli" }.isEmpty, "\(report.blockedSteps)")
        #expect(result.fixedSteps.filter { $0.hasPrefix("swift-cli/") }.sorted() == [
            "swift-cli/build-ignored", "swift-cli/changelog", "swift-cli/github-release-workflow", "swift-cli/version",
        ])

        let componentMk = try #require(project.read("cli/component.mk"))
        #expect(componentMk.contains("SWIFT_CLI_NAME = my-tool\n"))
        #expect(componentMk.contains("SWIFT_CLI_VERSION_FILE = Sources/my-tool/Version.swift\n"))
        #expect(componentMk.contains("SWIFT_CLI_DISTRIBUTION = github-release\n"))
        #expect(project.read("cli/Brewfile")?.contains("armcknight/tools/tools") == true)
        #expect(project.read("cli/README.md")?.hasPrefix("# my-tool\n") == true)
        #expect(project.read(".github/workflows/swift-cli-ci.yml")?.contains("swift-package-ci.yml@4") == true)
        #expect(project.read(".github/workflows/swift-cli-release.yml")?.contains("github-release.yml@4") == true)
        #expect(project.read("CHANGELOG.md")?.contains("## [Unreleased]\n") == true)

        #expect(project.read("Sources/my-tool/Version.swift")?.contains("    static let version = \"0.1.0\"\n") == true)
        let metadata = try #require(project.read("Sources/my-tool/BuildMetadata.swift"))
        #expect(metadata.contains("#if !MY_TOOL_DEV_BUILD\nlet buildMetadata: String? = nil\n#endif\n"))
        #expect(project.read("Sources/my-tool/main.swift")?.contains("ToolVersion.fullVersion") == true)
        let gitignore = try #require(project.read(".gitignore"))
        #expect(gitignore.contains("\n/Sources/my-tool/BuildMetadata.generated.swift\n"))
        #expect(gitignore.contains("\n.build/\n.swiftpm/\n"))
    }

    @Test func aCaskGetsTheCaskReleaseWorkflow() throws {
        let component = try #require(try Templates(root: repositoryRoot, tag: "v1", tags: []).components().first { $0.name == "swift-cli" })
        let step = try #require(component.manifest.steps.first { $0.id == "cask-release-workflow" })
        guard case .command(let fix) = step.fix else {
            Issue.record("The cask-release-workflow step's fix is not a command.")
            return
        }
        let values = PlaceholderValues(inputs: [
            "cask": "tools", "binaries": "vrsn prepare-release", "version_file": "Sources/Shared/Version.swift",
            "vrsn_key": "toolsVersion", "sign": "true", "match_git_url": "git@github.com:armcknight/fastlane-match.git",
            "team_id": "29274SF4VL", "bundle_id": "io.mcknight.tools",
        ], templates: repositoryRoot, tag: "v1")
        try FileManager.default.createDirectory(at: project.root.appending(path: "cli"), withIntermediateDirectories: true)
        let fixed = try ProcessRunner().shell(values.render(fix, quoted: true).text, in: project.root.appending(path: "cli"))
        #expect(fixed.succeeded, "\(fixed.transcript)")
        let workflow = try #require(project.read(".github/workflows/swift-cli-release.yml"))
        #expect(workflow.contains("""
                  cask-name: tools
                  binaries: |
                    vrsn
                    prepare-release
                  version-file: Sources/Shared/Version.swift
                  version-regex: '.*[^A-Za-z0-9_]toolsVersion = "([^"]+)".*'
                  sign: true
                  match-git-url: git@github.com:armcknight/fastlane-match.git
                  team-id: 29274SF4VL
                  bundle-id: io.mcknight.tools

            """))
        let check = try ProcessRunner().shell(values.render(step.check, quoted: true).text, in: project.root.appending(path: "cli"))
        #expect(check.succeeded)
    }
}
