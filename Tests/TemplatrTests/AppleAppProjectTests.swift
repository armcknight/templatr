import Foundation
import Testing
@testable import Templatr

/// The apple-app component's xcode-project step, with its real check and fix:
/// a new app gets an XcodeGen spec for the platforms it builds for.
@Suite struct AppleAppProjectTests {
    let project: Directory
    let inputs = [
        "app_name": "My App", "scheme": "Demo", "project": "Demo.xcodeproj", "bundle_id": "io.example.demo",
        "team_id": "ABCDE12345", "xcconfig": "config/Demo.xcconfig", "platforms": "ios mac",
    ]

    init() throws {
        project = try Directory()
        try project.write("apple/README.md", "# Demo\n")
    }

    var apple: URL { project.root.appending(path: "apple") }

    /// The step's check and fix commands, with `inputs` in them.
    func commands(_ inputs: [String: String]) throws -> (check: String, fix: String) {
        let component = try #require(try Templates(root: repositoryRoot, tag: "v1", tags: []).components().first { $0.name == "apple-app" })
        let step = try #require(component.manifest.steps.first { $0.id == "xcode-project" })
        guard case .command(let fix) = step.fix else {
            Issue.record("The xcode-project step's fix is not a command.")
            throw CancellationError()
        }
        let values = PlaceholderValues(inputs: inputs, templates: repositoryRoot, tag: "v1")
        return (values.render(step.check, quoted: true).text, values.render(fix, quoted: true).text)
    }

    func shell(_ command: String) throws -> CommandResult {
        try ProcessRunner().shell(command, in: apple)
    }

    @Test func aNewAppGetsASpecForItsPlatforms() throws {
        let (check, fix) = try commands(inputs)
        #expect(try !shell(check).succeeded)
        let fixed = try shell(fix)
        #expect(fixed.succeeded, "\(fixed.transcript)")
        #expect(try shell(check).succeeded)

        let spec = try #require(project.read("apple/project.yml"))
        #expect(!spec.contains("@"), "A template placeholder is left in the spec.")
        #expect(spec.contains("name: \"Demo\"\n"))
        #expect(spec.components(separatedBy: "supportedDestinations: [iOS, macOS]\n").count == 3)
        #expect(spec.contains("  deploymentTarget:\n    iOS: \"18.0\"\n    macOS: \"15.0\"\n"))
        #expect(spec.contains("PRODUCT_NAME: \"My App\"\n"))
        #expect(spec.contains("PRODUCT_BUNDLE_IDENTIFIER: \"io.example.demo\"\n"))
        #expect(spec.contains("DEVELOPMENT_TEAM: \"ABCDE12345\"\n"))
        #expect(spec.contains("Release: \"config/Demo.xcconfig\"\n"))
        #expect(spec.contains("TEST_HOST[sdk=macosx*]: \"$(BUILT_PRODUCTS_DIR)/My App.app/Contents/MacOS/My App\"\n"))
        #expect(project.read("apple/config/Demo.xcconfig") == "MARKETING_VERSION = 1.0\nCURRENT_PROJECT_VERSION = 1\n")
        #expect(project.read("apple/Demo/App.swift")?.contains("@main") == true)
        #expect(project.read("apple/DemoTests/Tests.swift")?.contains("@Test") == true)

        // The spec is detected, and its inputs are inferred from it.
        let resolved = try #require(try resolve("apple-app", in: project.root))
        #expect(resolved.values["xcodegen"] == "true")
        #expect(resolved.values["xcconfig"] == "config/Demo.xcconfig")
    }

    @Test(arguments: [("tvos", "[tvOS]"), ("mac ios mac", "[macOS, iOS]")])
    func eachPlatformIsNamedOneTime(platforms: String, destinations: String) throws {
        var inputs = inputs
        inputs["platforms"] = platforms
        let fixed = try shell(try commands(inputs).fix)
        #expect(fixed.succeeded, "\(fixed.transcript)")
        #expect(project.read("apple/project.yml")?.contains("supportedDestinations: \(destinations)\n") == true)
    }

    @Test func anUnknownPlatformWritesNothing() throws {
        var inputs = inputs
        inputs["platforms"] = "ios watchos"
        let fixed = try shell(try commands(inputs).fix)
        #expect(!fixed.succeeded)
        #expect(fixed.transcript.contains("Unknown platform: watchos"))
        #expect(project.snapshot().keys.sorted() == ["apple/README.md"])
    }

    /// An app that has a project, a workspace or a spec already passes the
    /// check, and its files are not changed.
    @Test(arguments: ["Demo.xcodeproj/project.pbxproj", "Demo.xcworkspace/contents.xcworkspacedata", "project.yml", "Project.swift"])
    func anAppWithAProjectPassesTheCheck(path: String) throws {
        try project.write("apple/\(path)", "existing\n")
        #expect(try shell(try commands(inputs).check).succeeded)
    }

    @Test func theFixDoesNotOverwriteASpecOrTheAppsFiles() throws {
        try project.write("apple/project.yml", "existing\n")
        try project.write("apple/config/Demo.xcconfig", "MARKETING_VERSION = 2.0\n")
        #expect(try !shell(try commands(inputs).fix).succeeded)
        #expect(project.read("apple/project.yml") == "existing\n")

        try project.delete("apple/project.yml")
        #expect(try shell(try commands(inputs).fix).succeeded)
        #expect(project.read("apple/config/Demo.xcconfig") == "MARKETING_VERSION = 2.0\n")
    }
}
