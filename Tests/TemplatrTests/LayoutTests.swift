import ComponentManifest
import Foundation
import Testing
@testable import Templatr

/// A component in its own directory, with a blurb, and a step that makes a
/// file where it runs.
func directoryManifest(_ name: String) -> String {
    """
    name = "\(name)"
    description = "The \(name) part."
    directory = "\(name)"
    blurb = "The \(name) part, {{inputs.app}}."
    secrets = []
    shared = []

    [detect]
    all = [{ glob = "\(name).toml" }]

    [[inputs]]
    name = "app"
    description = "The app."
    example = "demo"
    infer = [{ from = "toml", file = "\(name).toml", key = "app" }]

    [[steps]]
    id = "made-here"
    description = "The step ran in the component's directory."
    check = "test -f made-here"
    fix = "touch made-here"

    [[docs]]
    title = "Builds"
    anchor = "builds.md#ci"
    """
}

let layoutBaseManifest = """
    name = "base"
    description = "The root files."
    base = true
    inputs = []
    secrets = []
    steps = []
    shared = []

    [[docs]]
    title = "Builds"
    anchor = "builds.md#ci"
    """

/// A templatr checkout with a base component and the `api` and `web`
/// components, whose scaffolds both have `.github/workflows/shared.yml`.
func makeLayoutTemplates() throws -> Directory {
    let templates = try Directory()
    try templates.write("components/base/component.toml", layoutBaseManifest)
    try templates.write("components/base/CLAUDE.md", "# base\n")
    try templates.write("components/base/scaffold/README.md", """
        # Project

        <!-- superlinear:begin how-this-is-built -->
        <!-- superlinear:end -->

        """)
    try templates.write("components/base/scaffold/Makefile", "include $(wildcard */component.mk)\n")
    for name in ["api", "web"] {
        try templates.write("components/\(name)/component.toml", directoryManifest(name))
        try templates.write("components/\(name)/CLAUDE.md", "# \(name)\n")
        try templates.write("components/\(name)/scaffold/\(name)/README.md", "# {{inputs.app}}\n")
        try templates.write("components/\(name)/scaffold/\(name)/component.mk", "NAMESPACES += \(name)\n")
        try templates.write("components/\(name)/scaffold/.github/workflows/\(name)-ci.yml", "name: \(name)\n")
        try templates.write("components/\(name)/scaffold/.github/workflows/shared.yml", "name: \(name)\n")
    }
    return templates
}

@Suite struct LayoutTests {
    let templates: Directory
    let project: Directory
    let stubs = Stubs()

    init() throws {
        templates = try makeLayoutTemplates()
        project = try Directory()
        try project.write("api/api.toml", "app = \"demo-api\"\n")
        try project.write("web/web.toml", "app = \"demo-web\"\n")
    }

    var bootstrapper: Bootstrapper {
        Bootstrapper(templates: Templates(root: templates.root, tag: "v1", tags: ["v1"]), services: stubs.services())
    }

    func bootstrap() async throws -> BootstrapResult {
        try await bootstrapper.bootstrap(
            repository: project.root, options: BootstrapOptions(answers: [:], links: [], setSecret: setEverySecret)
        )
    }

    @Test func theBaseComponentComesFirstWithTheOthers() throws {
        let resolution = try bootstrapper.resolve(repository: project.root, answers: [:])
        #expect(resolution.components.map(\.component.name) == ["base", "api", "web"])
        // Each component's infer rules read the files in its directory.
        #expect(resolution.components.map { $0.values["app"] } == [nil, "demo-api", "demo-web"])
    }

    @Test func detectRulesReadTheComponentsDirectory() throws {
        let root = try Directory()
        try root.write("api.toml", "app = \"demo-api\"\n")
        let resolution = try bootstrapper.resolve(repository: root.root, answers: [:])
        #expect(resolution.components.isEmpty)
    }

    @Test func scaffoldsAreCopiedIntoTheirDirectories() async throws {
        let result = try await bootstrap()
        #expect(result.copiedFiles.sorted() == [
            ".github/workflows/api-ci.yml", ".github/workflows/web-ci.yml", "Makefile", "README.md",
            "api/README.md", "api/component.mk", "web/README.md", "web/component.mk",
        ])
        #expect(project.read("api/README.md") == "# demo-api\n")
        #expect(project.read("web/README.md") == "# demo-web\n")
    }

    @Test func aPathInTwoScaffoldsIsAConflict() async throws {
        let result = try await bootstrap()
        #expect(result.report.errors == [
            ".github/workflows/shared.yml is in the scaffolds of api and web, so it is not copied from either.",
        ])
        #expect(project.read(".github/workflows/shared.yml") == nil)
    }

    @Test func stepsRunInTheComponentsDirectory() async throws {
        let result = try await bootstrap()
        #expect(result.fixedSteps == ["api/made-here", "web/made-here"])
        #expect(project.read("api/made-here") == "")
        #expect(project.read("web/made-here") == "")
        #expect(project.read("made-here") == nil)
    }

    @Test func theRootReadmeHasEachBlurbAboveTheSection() async throws {
        _ = try await bootstrap()
        let readme = try #require(project.read("README.md"))
        let api = try #require(readme.range(of: """
            <!-- templatr:begin api -->
            [api/](api/README.md): The api part, demo-api.
            <!-- templatr:end -->
            """))
        let web = try #require(readme.range(of: """
            <!-- templatr:begin web -->
            [web/](web/README.md): The web part, demo-web.
            <!-- templatr:end -->
            """))
        let section = try #require(readme.range(of: Validator.beginMarker))
        #expect(readme.hasPrefix("# Project\n\n<!-- templatr:begin api -->"))
        #expect(api.upperBound < web.lowerBound)
        #expect(web.upperBound < section.lowerBound)
        #expect(readme.contains("at `v1`, in `api/`: The api part."))
        // The components' READMEs do not get the section.
        #expect(project.read("api/README.md")?.contains(Validator.beginMarker) == false)
        // The links resolve.
        let report = try await bootstrapper.check(repository: project.root)
        #expect(report.brokenLinks.isEmpty)
    }

    @Test func aSecondRunChangesNothing() async throws {
        _ = try await bootstrap()
        let files = project.snapshot()
        let second = try await bootstrap()
        #expect(project.snapshot() == files)
        #expect(second.changedFiles.isEmpty)
        #expect(second.copiedFiles.isEmpty)
    }

    @Test func aBlurbChangesOnlyBetweenItsMarkers() async throws {
        try project.write("README.md", """
            # Mine

            <!-- templatr:begin api -->
            Old.
            <!-- templatr:end -->

            Between.

            """)
        _ = try await bootstrap()
        let readme = try #require(project.read("README.md"))
        #expect(readme.hasPrefix("""
            # Mine

            <!-- templatr:begin api -->
            [api/](api/README.md): The api part, demo-api.
            <!-- templatr:end -->

            Between.

            <!-- templatr:begin web -->
            """))
    }

    @Test func aRecordWithoutTheBaseComponentReportsIt() async throws {
        try project.write(Record.fileName, """
            [components.api]
            tag = "v1"

            """)
        let resolution = try bootstrapper.resolve(repository: project.root, answers: [:])
        #expect(resolution.components.map(\.component.name) == ["api"])
        #expect(resolution.newComponents == ["base", "web"])
    }

    @Test func theBaseComponentAloneIsNoMatch() async throws {
        let empty = try Directory()
        let result = try await bootstrapper.bootstrap(
            repository: empty.root, options: BootstrapOptions(answers: [:], links: [], setSecret: setEverySecret)
        )
        #expect(result.report.errors == ["No component matches this repository."])
    }

    @Test func markedSectionsGoBeforeALine() {
        let section = MarkedSection(begin: "<!-- b -->", end: "<!-- e -->")
        #expect(section.replace(in: "x\n\n<!-- s -->\n", with: "new\n", before: "<!-- s -->")
            == "x\n\n<!-- b -->\nnew\n<!-- e -->\n\n<!-- s -->\n")
        #expect(section.replace(in: "x\n", with: "new\n", before: "<!-- s -->") == "x\n\n<!-- b -->\nnew\n<!-- e -->\n")
    }
}
