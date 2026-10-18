import ComponentManifest
import Foundation
import Testing
@testable import Templatr

/// A component whose directory its `platform` input names, with a blurb, and a
/// step that makes a file where it runs.
let namedDirectoryManifest = """
    name = "app"
    description = "The app."
    directory = { input = "platform", names = { ios = "ios", tvos = "tvos", mac = "macos" } }
    blurb = "The app, for {{inputs.platform}}. `make {{directory}} test` tests it."
    secrets = []
    shared = []

    [detect]
    all = [{ glob = "app.toml" }]

    [[inputs]]
    name = "platform"
    description = "The platform."
    example = "ios"
    infer = [{ from = "toml", file = "app.toml", key = "platform" }]

    [[steps]]
    id = "made-here"
    description = "The step ran in the component's directory."
    check = "test -f made-here && grep -qs \\"NAMESPACES += \\"{{directory}} component.mk"
    fix = "touch made-here"

    [[docs]]
    title = "Builds"
    anchor = "builds.md#ci"
    """

/// A templatr checkout with a base component and the `app` component.
func makeNamedDirectoryTemplates() throws -> Directory {
    let templates = try Directory()
    try templates.write("components/base/component.toml", layoutBaseManifest)
    try templates.write("components/base/CLAUDE.md", "# base\n")
    try templates.write("components/base/scaffold/README.md", """
        # Project

        <!-- superlinear:begin how-this-is-built -->
        <!-- superlinear:end -->

        """)
    try templates.write("components/app/component.toml", namedDirectoryManifest)
    try templates.write("components/app/CLAUDE.md", "The app is in `{{directory}}/`.\n")
    try templates.write("components/app/scaffold/{{directory}}/README.md", "# The app, in {{directory}}/\n")
    try templates.write("components/app/scaffold/{{directory}}/component.mk", "NAMESPACES += {{directory}}\n")
    try templates.write("components/app/scaffold/.github/workflows/app-ci.yml", "working-directory: {{directory}}\n")
    return templates
}

@Suite struct NamedDirectoryTests {
    let templates: Directory
    let project: Directory
    let stubs = Stubs()

    init() throws {
        templates = try makeNamedDirectoryTemplates()
        project = try Directory()
    }

    var bootstrapper: Bootstrapper {
        Bootstrapper(templates: Templates(root: templates.root, tag: "v1", tags: ["v1"]), services: stubs.services())
    }

    func bootstrap(answers: [String: [String: String]] = [:]) async throws -> BootstrapResult {
        try await bootstrapper.bootstrap(
            repository: project.root, options: BootstrapOptions(answers: answers, links: [], setSecret: setEverySecret)
        )
    }

    func app(_ resolution: Resolution) throws -> ResolvedComponent {
        try #require(resolution.components.first { $0.component.name == "app" })
    }

    @Test func theComponentIsFoundInTheDirectoryItsRulesMatch() throws {
        try project.write("tvos/app.toml", "platform = \"tvos\"\n")
        let app = try app(bootstrapper.resolve(repository: project.root, answers: [:]))
        #expect(app.directory == "tvos")
        // Its infer rules read the files there.
        #expect(app.values["platform"] == "tvos")
    }

    @Test func theDirectoryTheFilesAreInWinsOverTheInput() throws {
        // A tvOS app that is in ios/ stays there.
        try project.write("ios/app.toml", "platform = \"tvos\"\n")
        let app = try app(bootstrapper.resolve(repository: project.root, answers: [:]))
        #expect(app.directory == "ios")
        #expect(app.values["platform"] == "tvos")
    }

    @Test func noOtherDirectoryIsSearched() throws {
        try project.write("app.toml", "platform = \"tvos\"\n")
        try project.write("android/app.toml", "platform = \"tvos\"\n")
        #expect(try bootstrapper.resolve(repository: project.root, answers: [:]).components.isEmpty)
    }

    @Test func scaffoldsStepsAndBlurbsUseTheDirectory() async throws {
        try project.write("tvos/app.toml", "platform = \"tvos\"\n")
        let result = try await bootstrap()
        #expect(result.copiedFiles.sorted() == [".github/workflows/app-ci.yml", "README.md", "tvos/README.md", "tvos/component.mk"])
        #expect(project.read("tvos/README.md") == "# The app, in tvos/\n")
        #expect(project.read("tvos/component.mk") == "NAMESPACES += tvos\n")
        #expect(project.read(".github/workflows/app-ci.yml") == "working-directory: tvos\n")
        #expect(result.fixedSteps == ["app/made-here"])
        #expect(project.read("tvos/made-here") == "")
        #expect(project.read(Bootstrapper.vendoredClaudePath("app")) == "The app is in `tvos/`.\n")
        let readme = try #require(project.read("README.md"))
        #expect(readme.contains("[tvos/](tvos/README.md): The app, for tvos. `make tvos test` tests it."))
        #expect(readme.contains("at `v1`, in `tvos/`: The app."))
        #expect(result.report.errors.isEmpty)
        #expect(result.report.blockedSteps.isEmpty)

        let files = project.snapshot()
        let second = try await bootstrap()
        #expect(project.snapshot() == files)
        #expect(second.changedFiles.isEmpty)
    }

    @Test func withoutItsFilesTheRecordedInputNamesTheDirectory() async throws {
        try project.write(Record.fileName, """
            [components.app]
            tag = "v1"

            [components.app.inputs]
            platform = "mac"

            """)
        let result = try await bootstrap()
        #expect(result.copiedFiles.contains("macos/component.mk"))
        #expect(project.read("macos/component.mk") == "NAMESPACES += macos\n")
        #expect(result.fixedSteps == ["app/made-here"])
        #expect(project.read("macos/made-here") == "")
    }

    @Test func anAnswerNamesTheDirectoryOfARecordedComponent() throws {
        try project.write(Record.fileName, "[components.app]\ntag = \"v1\"\n")
        let resolution = try bootstrapper.resolve(repository: project.root, answers: ["app": ["platform": "tvos"]])
        #expect(try app(resolution).directory == "tvos")
    }

    @Test func untilTheInputHasAValueTheDirectoryWaits() async throws {
        try project.write(Record.fileName, "[components.app]\ntag = \"v1\"\n")
        let result = try await bootstrap()
        #expect(result.report.missingInputs.map(\.name) == ["platform"])
        #expect(result.copiedFiles.isEmpty)
        #expect(result.report.blockedSteps.map(\.id).sorted() == [
            "made-here", "scaffold:.github/workflows/app-ci.yml", "scaffold:{{directory}}/README.md",
            "scaffold:{{directory}}/component.mk",
        ])
        #expect(result.report.blockedSteps.first { $0.id == "made-here" }?.missingInputs == ["platform"])
        #expect(result.report.blockedSteps.first { $0.id == "scaffold:{{directory}}/README.md" }?.missingInputs == ["inputs.platform"])
        // Nothing runs, or is made, at the root.
        #expect(project.read("made-here") == nil)
        #expect(project.read("README.md")?.contains("<!-- templatr:begin app -->\nThe app, for {{inputs.platform}}.") == true)
    }

    @Test func aValueThatNamesNoDirectoryIsAnError() async throws {
        try project.write(Record.fileName, """
            [components.app]
            tag = "v1"

            [components.app.inputs]
            platform = "watchos"

            """)
        let result = try await bootstrap()
        #expect(result.report.errors == ["app: platform 'watchos' names no directory; it can be ios, mac, tvos."])
        #expect(result.report.missingInputs.isEmpty)
        #expect(result.copiedFiles.isEmpty)
        #expect(result.report.blockedSteps.first { $0.id == "made-here" }?.missingInputs == ["platform"])
        #expect(project.read("made-here") == nil)
    }
}
