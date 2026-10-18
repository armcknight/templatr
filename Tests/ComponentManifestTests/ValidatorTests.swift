import Foundation
import Testing
@testable import ComponentManifest

@Suite("Validator")
struct ValidatorTests {
    let repository: Repository

    init() throws {
        repository = try Repository()
    }

    /// Fails unless one problem contains `fragment`.
    func expectProblem(_ fragment: String) {
        let problems = repository.problems()
        #expect(
            problems.contains { $0.contains(fragment) },
            "no problem with '\(fragment)' in \(problems)"
        )
    }

    @Test func validComponent() {
        #expect(repository.problems() == [])
    }

    @Test func thisRepositoryIsValid() {
        #expect(Validator(root: repositoryRoot, anchors: nil).problems() == [])
    }

    @Test func formatErrorNamesTheField() throws {
        try repository.editManifest(#"source = "keychain:demo.fly-token""#, #"source = "vault:demo""#)
        expectProblem("secrets/0/source")
    }

    @Test func unknownField() throws {
        try repository.editManifest(
            #"description = "A demonstration component.""#,
            "description = \"A demonstration component.\"\ncolor = \"red\""
        )
        expectProblem("'color' was unexpected")
    }

    @Test func inferRuleFieldsDependOnFrom() throws {
        try repository.editManifest(
            #"{ from = "toml", file = "fly.toml", key = "app" }"#,
            #"{ from = "build-setting", file = "fly.toml", key = "app" }"#
        )
        expectProblem("inputs/0/infer/0")
    }

    @Test func nameMustMatchDirectory() throws {
        try repository.editManifest(#"name = "demo""#, #"name = "other""#)
        expectProblem("is not the directory's name")
    }

    @Test func duplicateStep() throws {
        try repository.editManifest(#"id = "domain""#, #"id = "app-exists""#)
        expectProblem("step 'app-exists' is declared more than one time")
    }

    @Test func regexInferNeedsAGroup() throws {
        try repository.editManifest(#"pattern = "primary_region = \"([a-z]+)\"""#, #"pattern = "primary_region""#)
        expectProblem("has no capture group")
    }

    @Test func globInferCannotBeBothExistsAndStem() throws {
        try repository.editManifest(
            #"infer = [{ from = "toml", file = "fly.toml", key = "app" }]"#,
            #"infer = [{ from = "glob", glob = "fly.toml", exists = true, stem = true }]"#
        )
        expectProblem("exists and stem cannot both be true")
    }

    @Test func rootRulesInAComponentWithADirectory() throws {
        try repository.editManifest(
            #"any = [{ glob = "Package.swift", contains = "vapor" }]"#,
            #"any = [{ glob = "server/Package.swift", contains = "vapor", root = true }]"#
        )
        try repository.editManifest(
            #"infer = [{ from = "toml", file = "fly.toml", key = "app" }]"#,
            #"infer = [{ from = "toml", file = "server/fly.toml", key = "app", root = true }]"#
        )
        #expect(repository.problems() == [])
    }

    @Test func aRootDetectRuleNeedsADirectory() throws {
        try repository.editManifest(#"directory = "server""#, "")
        try repository.editManifest(
            #"any = [{ glob = "Package.swift", contains = "vapor" }]"#,
            #"any = [{ glob = "Package.swift", contains = "vapor", root = true }]"#
        )
        expectProblem("detect.any[0]: root = true means nothing in a component without a directory")
    }

    @Test func aRootInferRuleNeedsADirectory() throws {
        try repository.editManifest(#"directory = "server""#, "")
        try repository.editManifest(
            #"infer = [{ from = "toml", file = "fly.toml", key = "app" }]"#,
            #"infer = [{ from = "toml", file = "fly.toml", key = "app", root = true }]"#
        )
        expectProblem("input app infer[0]: root = true means nothing in a component without a directory")
    }

    @Test func aBuildSettingHasNoRoot() throws {
        try repository.editManifest(
            #"{ from = "toml", file = "fly.toml", key = "app" }"#,
            #"{ from = "build-setting", key = "APP", root = true }"#
        )
        expectProblem("inputs/0/infer/0")
    }

    @Test func invalidDetectRegex() throws {
        try repository.editManifest(#"contains = "vapor""#, #"contains = "vapor(""#)
        expectProblem("invalid regular expression")
    }

    @Test func unknownPlaceholderInScaffold() throws {
        try repository.write(
            "components/demo/scaffold/server/README.md", scaffoldReadme.replacingOccurrences(of: "inputs.app", with: "inputs.name")
        )
        expectProblem("scaffold/server/README.md: unknown placeholder {{inputs.name}}")
    }

    @Test func unknownPlaceholderInBlurb() throws {
        try repository.editManifest("{{inputs.app}}.\"", "{{inputs.name}}.\"")
        expectProblem("blurb: unknown placeholder {{inputs.name}}")
    }

    @Test func unknownPlaceholderInHumanText() throws {
        try repository.editManifest("Point the domain at {{inputs.app}}.", "Point {{inputs.domain}} at the app.")
        expectProblem("step domain fix: unknown placeholder {{inputs.domain}}")
    }

    @Test func placeholderInSecretSource() throws {
        try repository.editManifest(#"source = "keychain:demo.fly-token""#, #"source = "keychain:demo.{{inputs.app}}.fly-token""#)
        #expect(repository.problems() == [])
    }

    @Test func unknownPlaceholderInSecretSource() throws {
        try repository.editManifest(#"source = "keychain:demo.fly-token""#, #"source = "keychain:demo.{{inputs.name}}.fly-token""#)
        expectProblem("secret FLY_API_TOKEN source: unknown placeholder {{inputs.name}}")
    }

    @Test func githubExpressionsAreNotPlaceholders() {
        #expect(Placeholders.names(in: "${{ github.sha }} {{templates.tag}}") == ["templates.tag"])
    }

    @Test func aComponentsReadmeIsInItsDirectory() throws {
        try repository.delete("components/demo/scaffold/server/README.md")
        expectProblem("components/demo: scaffold/server/README.md is missing")
    }

    @Test func aComponentsReadmeHasNoMarkers() throws {
        try repository.write("components/demo/scaffold/server/README.md", scaffoldReadme + baseReadme)
        expectProblem("has the how-this-is-built markers")
    }

    @Test func aScaffoldFileIsInTheComponentsDirectory() throws {
        try repository.write("components/demo/scaffold/Makefile", "all:\n")
        try repository.write("components/demo/scaffold/.github/workflows/ci.yml", workflow)
        expectProblem("components/demo/scaffold/Makefile: must be under server/ or a workflow named .github/workflows/demo-*")
        expectProblem("components/demo/scaffold/.github/workflows/ci.yml: must be under server/")
    }

    @Test func aBaseComponent() throws {
        try repository.addBase()
        #expect(repository.problems() == [])
    }

    @Test func theBaseReadmeNeedsMarkers() throws {
        try repository.addBase()
        try repository.write("components/base/scaffold/README.md", "# Project\n<!-- superlinear:end -->\n")
        expectProblem("one time each")
    }

    @Test func theBaseReadmesMarkersAreInOrder() throws {
        try repository.addBase()
        try repository.write(
            "components/base/scaffold/README.md",
            "<!-- superlinear:end -->\n<!-- superlinear:begin how-this-is-built -->\n"
        )
        expectProblem("one time each")
    }

    @Test func aBaseComponentHasNoDetectRules() throws {
        try repository.addBase()
        try repository.write(
            "components/base/component.toml", baseManifest + "\n[detect]\nall = [{ glob = \"Makefile\" }]\n"
        )
        expectProblem("a base component has no detect rules")
    }

    @Test func aComponentThatIsNotBaseNeedsDetectRules() throws {
        try repository.addBase()
        try repository.write("components/base/component.toml", baseManifest.replacingOccurrences(of: "base = true\n", with: ""))
        expectProblem("'detect' is required")
    }

    @Test func thereIsOneBaseComponent() throws {
        try repository.addBase()
        try repository.write("components/other/component.toml", baseManifest.replacingOccurrences(of: "\"base\"", with: "\"other\""))
        try repository.write("components/other/CLAUDE.md", "# other\n")
        try repository.write("components/other/scaffold/Makefile", "all:\n")
        expectProblem("base, other are base components")
    }

    @Test func twoScaffoldsDoNotShareAPath() throws {
        try repository.addBase()
        try repository.write("components/base/scaffold/.github/workflows/demo-deploy.yml", workflow)
        try repository.write("components/base/scaffold/server/fly.toml", "")
        expectProblem("components/demo/scaffold/.github/workflows/demo-deploy.yml: base's scaffold has it too")
        expectProblem("components/base/scaffold/server/fly.toml: is in demo's directory")
    }

    @Test func twoComponentsDoNotShareADirectory() throws {
        try repository.write(
            "components/other/component.toml",
            manifest.replacingOccurrences(of: "name = \"demo\"", with: "name = \"other\"")
        )
        try repository.write("components/other/CLAUDE.md", "# other\n")
        try repository.write("components/other/scaffold/server/OTHER.md", "")
        expectProblem("directory 'server' is also demo's")
    }

    @Test func missingClaudeMd() throws {
        try repository.delete("components/demo/CLAUDE.md")
        expectProblem("CLAUDE.md is missing")
    }

    @Test func missingSharedPath() throws {
        try repository.delete(".github/workflows/demo.yml")
        expectProblem("shared path '.github/workflows/demo.yml' does not exist")
    }

    @Test func sharedPieceInAnotherRepoNeedNotExistHere() throws {
        try repository.editManifest("version = \"v1\"\ndescription = \"Deploys the app.\"", externalShared)
        try repository.write(
            "README.md",
            readme + "* [ios-ci](https://github.com/armcknight/workflows/blob/4/.github/workflows/ios-ci.yml)\n"
        )
        #expect(repository.problems() == [])
    }

    @Test func readmeLinksASharedPieceInAnotherRepoAtItsVersion() throws {
        try repository.editManifest("version = \"v1\"\ndescription = \"Deploys the app.\"", externalShared)
        try repository.write(
            "README.md",
            readme + "* [ios-ci](https://github.com/armcknight/workflows/blob/main/.github/workflows/ios-ci.yml)\n"
        )
        expectProblem(
            "does not link to the shared workflow https://github.com/armcknight/workflows/blob/4/.github/workflows/ios-ci.yml"
        )
    }

    @Test func versionOfAPieceInThisRepoIsAVTag() throws {
        try repository.editManifest(#"version = "v1""#, #"version = "4""#)
        expectProblem("shared/0/version")
    }

    @Test func localSecret() throws {
        try repository.editManifest(#"scope = "app""#, #"scope = "local""#)
        #expect(repository.problems() == [])
    }

    @Test func localSecretComesFromTheKeychain() throws {
        try repository.editManifest(#"scope = "app""#, #"scope = "local""#)
        try repository.editManifest(#"source = "keychain:demo.fly-token""#, #"source = "generate:password""#)
        expectProblem("secret FLY_API_TOKEN is local")
    }

    @Test func unknownSecretScope() throws {
        try repository.editManifest(#"scope = "app""#, #"scope = "github""#)
        expectProblem("secrets/0/scope")
    }

    @Test func yamlInferRule() throws {
        try repository.editManifest(
            #"{ from = "toml", file = "fly.toml", key = "app" }"#,
            #"{ from = "yaml", file = ".arkana.yml", key = "global_secrets", separator = " " }"#
        )
        #expect(repository.problems() == [])
    }

    @Test func globInferRuleContainsMustCompile() throws {
        try repository.editManifest(
            #"{ from = "toml", file = "fly.toml", key = "app" }"#,
            #"{ from = "glob", glob = "**/*.xcconfig", contains = "MARKETING_VERSION(" }"#
        )
        expectProblem("invalid regular expression")
    }

    @Test func unknownAnchor() {
        repository.anchors = ["bootstrap.md#components"]
        expectProblem("docs anchor 'builds.md#ci'")
    }

    @Test func anchorCheckCanBeSkipped() {
        repository.anchors = nil
        #expect(repository.problems() == [])
    }

    @Test func readmeLinksEachComponentAndSharedPiece() throws {
        try repository.write("README.md", "# templates\n")
        expectProblem("does not link to components/demo")
        expectProblem("does not link to the shared workflow .github/workflows/demo.yml")
    }

    @Test func anchorMustNameAPage() throws {
        try repository.editManifest(#"anchor = "builds.md#ci""#, #"anchor = "ci""#)
        expectProblem("docs/0/anchor")
    }

    @Test func anchorsAreReadFromTheTables() async throws {
        try repository.write("anchors.md", """
            # Anchors

            Each section has an explicit anchor, `<a id="…"></a>`.

            ## [Builds](builds.md)

            | Anchor | Section |
            | --- | --- |
            | [`builds.md#ci`](builds.md#ci) | CI. |
            | [`builds.md#build-numbers`](builds.md#build-numbers) | Build numbers. |

            """)
        let anchors = try await Anchors.read(from: repository.root.appending(path: "anchors.md").path)
        #expect(anchors == ["builds.md#ci", "builds.md#build-numbers"])
    }

    @Test func missingManifestAndEmptyComponents() throws {
        try repository.delete("components/demo/component.toml")
        expectProblem("components/demo: component.toml is missing")
        try repository.delete("components/demo")
        expectProblem("components/: there are no components")
    }

    @Test func manifestThatIsNotToml() throws {
        try repository.write("components/demo/component.toml", "name = \n")
        expectProblem("components/demo/component.toml: ")
        #expect(repository.problems().count == 1)
    }
}
