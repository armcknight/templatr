import Foundation
import Testing
@testable import Templatr

/// Detection and inference with this repository's apple-app manifest.
@Suite struct AppleAppTests {
    let project: Directory
    let stubs = Stubs()

    init() throws {
        project = try Directory()
        try project.write("Demo.xcodeproj/project.pbxproj", """
            /* Begin PBXNativeTarget section */
            productType = "com.apple.product-type.application";
            """)
        // The scheme's file name, not the product it builds, is its name. A
        // framework's scheme comes first by name, but does not build an app.
        try project.write("Demo.xcodeproj/xcshareddata/xcschemes/Demo.xcscheme", """
            <BuildableReference BuildableName = "Demo Dev.app" BlueprintName = "Demo">
            """)
        try project.write("Demo.xcodeproj/xcshareddata/xcschemes/Common.xcscheme", """
            <BuildableReference BuildableName = "Common.framework" BlueprintName = "Common">
            """)
        try project.write("config/Demo.xcconfig", "MARKETING_VERSION = 1.2\nCURRENT_PROJECT_VERSION = 7\n")
        try project.write("fastlane/Appfile", """
            app_identifier("io.example.demo")
            team_id "ABCDE12345"
            """)
        try project.write("fastlane/Matchfile", """
            git_url("git@github.com:example/match.git")
            app_identifier(["io.example.demo", "io.example.demo.adhoc", 'io.example.demo.watchkitapp'])
            """)
        try project.write(".arkana.yml", "global_secrets:\n  - SentryDSN\n  - FeedbackEmail\n")
        stubs.settings = [
            "PRODUCT_NAME": "Demo",
            // xcodebuild prints SDKROOT as a path.
            "SDKROOT": "/Applications/Xcode.app/Contents/Developer/Platforms/iPhoneOS.platform/Developer/SDKs/iPhoneOS26.1.sdk",
            "PLATFORM_NAME": "iphoneos", "PRODUCT_BUNDLE_IDENTIFIER": "io.example.other",
            "DEVELOPMENT_TEAM": "ZZZZZ99999",
        ]
    }

    var bootstrapper: Bootstrapper {
        Bootstrapper(templates: Templates(root: repositoryRoot, tag: "v1", tags: []), services: stubs.services())
    }

    @Test func detectsTheAppleApp() throws {
        let resolution = try bootstrapper.resolve(repository: project.root, answers: [:])
        #expect(resolution.components.map(\.component.name) == ["apple-app"])
        #expect(!resolution.recorded)
    }

    @Test func doesNotDetectAPackage() throws {
        let package = try Directory()
        try package.write("Package.swift", "// swift-tools-version: 6.0\n")
        try package.write("Demo.xcodeproj/project.pbxproj", "productType = \"com.apple.product-type.tool\";\n")
        let resolution = try bootstrapper.resolve(repository: package.root, answers: [:])
        #expect(resolution.components.isEmpty)
    }

    @Test func infersTheInputs() throws {
        let resolution = try bootstrapper.resolve(repository: project.root, answers: [:])
        let app = try #require(resolution.components.first)
        #expect(app.missing.map(\.name) == [])
        #expect(app.values == [
            "app_name": "Demo",
            "scheme": "Demo",
            "project": "Demo.xcodeproj",
            "workspace": "",
            "xcconfig": "config/Demo.xcconfig",
            "xcodegen": "false",
            "platform": "ios",
            // The fastlane configuration comes before the build settings.
            "bundle_id": "io.example.demo",
            "adhoc_bundle_id": "io.example.demo.adhoc",
            "stage_xcargs": "",
            "arkana_keys": "SentryDSN FeedbackEmail",
            "app_identifiers": "io.example.demo,io.example.demo.adhoc,io.example.demo.watchkitapp",
            "team_id": "ABCDE12345",
            "match_git_url": "git@github.com:example/match.git",
            "test_device": "iPhone 16 Pro",
            "tester_group": "Internal",
        ])
        // Defaults are not shown as inferred.
        #expect(app.inferred["test_device"] == nil)
        #expect(app.inferred["app_name"] == "Demo")
        // xcodebuild runs one time, for the project and scheme found first.
        #expect(stubs.settingsRequests == [["Demo.xcodeproj", nil, "Demo"]])
    }

    @Test func aMappedValueThatIsNotInTheMapIsNotFound() throws {
        stubs.settings?["PLATFORM_NAME"] = "watchos"
        let resolution = try bootstrapper.resolve(repository: project.root, answers: [:])
        #expect(resolution.components.first?.missing.map(\.name) == ["platform"])
    }

    @Test func aSchemeThatBuildsNoAppIsChosenWhenNoneDoes() throws {
        try FileManager.default.removeItem(at: project.root.appending(path: "Demo.xcodeproj/xcshareddata/xcschemes/Demo.xcscheme"))
        let resolution = try bootstrapper.resolve(repository: project.root, answers: [:])
        #expect(resolution.components.first?.values["scheme"] == "Common")
    }

    @Test func aRecordedValueIsNotInferredAgain() throws {
        try project.write(Record.fileName, """
            [components.apple-app]
            tag = "v1"

            [components.apple-app.inputs]
            bundle_id = "io.example.recorded"

            """)
        let resolution = try bootstrapper.resolve(repository: project.root, answers: [:])
        let app = try #require(resolution.components.first)
        #expect(resolution.recorded)
        #expect(app.values["bundle_id"] == "io.example.recorded")
        #expect(app.inferred["bundle_id"] == nil)
    }
}

@Suite struct UnitTests {
    @Test(arguments: [
        ("**/*.xcodeproj/project.pbxproj", "A.xcodeproj/project.pbxproj", true),
        ("**/*.xcodeproj/project.pbxproj", "apps/ios/A.xcodeproj/project.pbxproj", true),
        ("*.xcodeproj", "apps/A.xcodeproj", false),
        ("fly.toml", "fly.toml", true),
        ("fly.toml", "sub/fly.toml", false),
        ("**/*.xcconfig", "config/a.xcconfig", true),
        ("fastlane/Fast?ile", "fastlane/Fastfile", true),
        ("a.b", "axb", false),
    ])
    func glob(pattern: String, path: String, matches: Bool) {
        #expect(Glob(pattern).matches(path) == matches)
    }

    @Test func fastlaneArguments() {
        #expect(Inferrer.fastlaneArgument("team_id", in: "team_id(\"ABC\")\n") == "ABC")
        #expect(Inferrer.fastlaneArgument("team_id", in: "  team_id 'ABC'\n") == "ABC")
        #expect(Inferrer.fastlaneArgument("app_identifier", in: "app_identifier [\"a\", 'b']\n") == "a,b")
        #expect(Inferrer.fastlaneArgument("team_id", in: "# team_id(\"ABC\")\n") == nil)
        #expect(Inferrer.fastlaneArgument("team_id", in: "itc_team_id(\"ABC\")\n") == nil)
    }

    @Test func recordRoundTrips() throws {
        let record = Record(components: [
            "apple-app": Record.Entry(tag: "v1", inputs: ["b": "two \"quoted\"\nlines", "a": ""]),
            "vapor-fly": Record.Entry(tag: "v1.1", inputs: [:]),
        ])
        let toml = record.toml()
        #expect(try Record(toml: toml) == record)
        #expect(toml == Record(components: record.components).toml())
        #expect(toml.contains("[components.apple-app.inputs]\na = \"\"\nb = \"two \\\"quoted\\\"\\nlines\""))
    }

    @Test func versions() {
        #expect(Version.isOlder("v1", than: "v1.1"))
        #expect(!Version.isOlder("v1.0", than: "v1"))
        #expect(Version.isOlder("v9", than: "v10"))
        #expect(Version.newest(of: ["v1", "v10", "v9", "main"]) == "v10")
    }

    @Test func placeholdersAreQuotedInCommands() {
        let values = PlaceholderValues(inputs: ["name": "it's"], templates: URL(fileURLWithPath: "/t p"), tag: "v1")
        #expect(values.render("echo {{inputs.name}} {{ templates }}/x ${{ github.ref }} {{inputs.other}}", quoted: true)
            == ("echo 'it'\\''s' '/t p'/x ${{ github.ref }} {{inputs.other}}", ["inputs.other"]))
    }

    @Test func keychainModificationDate() {
        let attributes = #"    "mdat"<timedate>=0x32303236313031373132303030305A00  "20261017120000Z\000""#
        #expect(SystemKeychain.modified(in: attributes) == Date(timeIntervalSince1970: 1_792_238_400))
    }

    @Test func keychainPasswords() {
        #expect(SystemKeychain.password(in: "keychain: \"x\"\npassword: \"plain \"q\" v\"\n") == "plain \"q\" v")
        #expect(SystemKeychain.password(in: "password: 0x6122620A63  \"a\"b\\012c\"\n") == "a\"b\nc")
        #expect(SystemKeychain.password(in: "password: \"\"\n") == "")
        #expect(SystemKeychain.password(in: "nothing\n") == nil)
    }

    @Test func markedSectionReplacesOnlyItsBody() {
        let section = MarkedSection(begin: "<!-- b -->", end: "<!-- e -->")
        #expect(section.replace(in: "x\n<!-- b -->\nold\n<!-- e -->\ny", with: "new\n") == "x\n<!-- b -->\nnew\n<!-- e -->\ny")
        #expect(section.replace(in: "x", with: "new\n") == "x\n\n<!-- b -->\nnew\n<!-- e -->\n")
        #expect(section.replace(in: "", with: "new\n") == "<!-- b -->\nnew\n<!-- e -->\n")
    }

    @Test func stems() {
        #expect(Inferrer.stem("A.xcodeproj/xcshareddata/xcschemes/Demo App.xcscheme") == "Demo App")
        #expect(Inferrer.stem("Demo") == "Demo")
    }

    @Test(arguments: [true, false])
    func buildSettingsAreForTheReleaseConfiguration(hasRelease: Bool) throws {
        let runner = XcodebuildStub(hasRelease: hasRelease)
        let settings = XcodeBuildSettings(runner: runner)
            .buildSettings(repository: URL(fileURLWithPath: "/"), project: "Demo.xcodeproj", workspace: nil, scheme: "Demo")
        #expect(settings?["CONFIGURATION"] == (hasRelease ? "Release" : "Debug"))
        let base = ["xcodebuild", "-showBuildSettings", "-json", "-project", "Demo.xcodeproj", "-scheme", "Demo"]
        #expect(runner.calls == (hasRelease ? [base + ["-configuration", "Release"]] : [base + ["-configuration", "Release"], base]))
    }
}

/// xcodebuild for a project with a Debug configuration and, when `hasRelease`,
/// a Release one.
final class XcodebuildStub: CommandRunner, @unchecked Sendable {
    let hasRelease: Bool
    private let lock = NSLock()
    private var _calls: [[String]] = []

    init(hasRelease: Bool) {
        self.hasRelease = hasRelease
    }

    var calls: [[String]] { lock.withLock { _calls } }

    func run(_ arguments: [String], input: Data?, in directory: URL?) throws -> CommandResult {
        lock.withLock { _calls.append(arguments) }
        let configuration = arguments.firstIndex(of: "-configuration").map { arguments[$0 + 1] } ?? "Debug"
        guard configuration == "Debug" || hasRelease else {
            return CommandResult(status: 65, output: Data(), error: Data("no configuration \(configuration)".utf8))
        }
        let json = #"[{"buildSettings": {"WRAPPER_EXTENSION": "app", "CONFIGURATION": "\#(configuration)"}}]"#
        return CommandResult(status: 0, output: Data(json.utf8), error: Data())
    }
}
