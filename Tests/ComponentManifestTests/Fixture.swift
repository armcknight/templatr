import Foundation
@testable import ComponentManifest

/// This repository's root.
let repositoryRoot = URL(fileURLWithPath: #filePath)
    .deletingLastPathComponent().deletingLastPathComponent().deletingLastPathComponent()

let manifest = #"""
    name = "demo"
    description = "A demonstration component."

    [detect]
    all = [{ glob = "fly.toml" }]
    any = [{ glob = "Package.swift", contains = "vapor" }]

    [[inputs]]
    name = "app"
    description = "The Fly app."
    example = "demo-api"
    infer = [{ from = "toml", file = "fly.toml", key = "app" }]

    [[inputs]]
    name = "region"
    description = "The primary region."
    example = "sjc"
    infer = [{ from = "regex", glob = "fly.toml", pattern = "primary_region = \"([a-z]+)\"" }]

    [[secrets]]
    name = "FLY_API_TOKEN"
    description = "A deploy token."
    source = "keychain:demo.fly-token"
    scope = "app"
    human = { text = "Make a deploy token for {{inputs.app}}.", twoFactor = true }
    rotateEvery = "90d"

    [[steps]]
    id = "app-exists"
    description = "The Fly app exists."
    check = "fly status --app {{inputs.app}}"
    fix = "fly apps create {{inputs.app}}"

    [[steps]]
    id = "domain"
    description = "The domain points at the app."
    check = "{{templates}}/components/demo/bin/check-domain"
    fix = { human = { text = "Point the domain at {{inputs.app}}." } }

    [[shared]]
    kind = "workflow"
    path = ".github/workflows/demo.yml"
    version = "v1"
    description = "Deploys the app."

    [[docs]]
    title = "Builds"
    anchor = "builds.md#ci"

    """#

let readme = """
    # templates

    * [demo](components/demo/)
    * [the workflow](.github/workflows/demo.yml)

    """

let scaffoldReadme = """
    # {{inputs.app}}

    <!-- superlinear:begin how-this-is-built -->
    <!-- superlinear:end -->

    """

let workflow = """
    jobs:
      deploy:
        uses: armcknight/templatr/.github/workflows/demo.yml@{{templates.tag}}
        with:
          force: ${{ github.event_name == 'workflow_dispatch' }}

    """

let externalShared = """
    version = "v1"
    description = "Deploys the app."

    [[shared]]
    kind = "workflow"
    repo = "armcknight/workflows"
    path = ".github/workflows/ios-ci.yml"
    version = "4"
    description = "Runs the tests."
    """

/// A temporary repository with one valid component, `demo`. Deleted when the
/// fixture goes away.
final class Repository {
    let root: URL
    var anchors: Set<String>? = ["builds.md#ci", "bootstrap.md#components"]

    init() throws {
        root = FileManager.default.temporaryDirectory.appending(path: "templatr-\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
        try write(".github/workflows/demo.yml", "on: workflow_call\n")
        try write("README.md", readme)
        try write("components/demo/component.toml", manifest)
        try write("components/demo/CLAUDE.md", "# demo\n")
        try write("components/demo/scaffold/README.md", scaffoldReadme)
        try write("components/demo/scaffold/.github/workflows/deploy.yml", workflow)
    }

    deinit {
        try? FileManager.default.removeItem(at: root)
    }

    func write(_ path: String, _ text: String) throws {
        let url = root.appending(path: path)
        try FileManager.default.createDirectory(at: url.deletingLastPathComponent(), withIntermediateDirectories: true)
        try text.write(to: url, atomically: true, encoding: .utf8)
    }

    func delete(_ path: String) throws {
        try FileManager.default.removeItem(at: root.appending(path: path))
    }

    /// Replaces `old`, which the manifest must contain, with `new`.
    func editManifest(_ old: String, _ new: String) throws {
        let url = root.appending(path: "components/demo/component.toml")
        let text = try String(contentsOf: url, encoding: .utf8)
        precondition(text.contains(old), "the manifest does not contain \(old)")
        try text.replacingOccurrences(of: old, with: new).write(to: url, atomically: true, encoding: .utf8)
    }

    func problems() -> [String] {
        Validator(root: root, anchors: anchors).problems()
    }
}
