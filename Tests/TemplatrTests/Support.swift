import ComponentManifest
import Foundation
@testable import Templatr

/// This repository's root.
let repositoryRoot = URL(fileURLWithPath: #filePath)
    .deletingLastPathComponent().deletingLastPathComponent().deletingLastPathComponent()

/// A temporary directory, deleted when the value goes away.
final class Directory {
    let root: URL

    init() throws {
        root = FileManager.default.temporaryDirectory.appending(path: "templatr-\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
    }

    deinit {
        try? FileManager.default.removeItem(at: root)
    }

    func write(_ path: String, _ text: String) throws {
        let url = root.appending(path: path)
        try FileManager.default.createDirectory(at: url.deletingLastPathComponent(), withIntermediateDirectories: true)
        try text.write(to: url, atomically: true, encoding: .utf8)
    }

    func writeExecutable(_ path: String, _ text: String) throws {
        try write(path, text)
        try FileManager.default.setAttributes([.posixPermissions: 0o755], ofItemAtPath: root.appending(path: path).path)
    }

    func delete(_ path: String) throws {
        try FileManager.default.removeItem(at: root.appending(path: path))
    }

    func read(_ path: String) -> String? {
        try? String(contentsOf: root.appending(path: path), encoding: .utf8)
    }

    /// Every file's contents and permissions, by path.
    func snapshot() -> [String: String] {
        var files: [String: String] = [:]
        let enumerator = FileManager.default.enumerator(atPath: root.path)
        while let path = enumerator?.nextObject() as? String {
            guard enumerator?.fileAttributes?[.type] as? FileAttributeType == .typeRegular else { continue }
            let permissions = (enumerator?.fileAttributes?[.posixPermissions] as? Int) ?? 0
            files[path] = "\(String(permissions, radix: 8)) " + (read(path) ?? "<binary>")
        }
        return files
    }
}

let demoManifest = #"""
    name = "demo"
    description = "A demonstration component."

    [detect]
    all = [{ glob = "fly.toml" }]

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

    [[inputs]]
    name = "team"
    description = "The team."
    example = "core"
    default = "core"

    [[secrets]]
    name = "DEPLOY_TOKEN"
    description = "A deploy token."
    source = "keychain:demo.{{inputs.app}}.deploy-token"
    scope = "app"

    [[secrets]]
    name = "SIGNING_KEY"
    description = "A signing key."
    source = "1password:op://Vault/Signing/key"
    scope = "team"
    human = { text = "Make a signing key for {{inputs.app}}." }

    [[secrets]]
    name = "WEBHOOK_SECRET"
    description = "The webhook's shared secret."
    source = "generate:hex32"
    scope = "repo"

    [[secrets]]
    name = "LOCAL_TOKEN"
    description = "A token for commands run on the owner's Mac."
    source = "keychain:demo.local-token"
    scope = "local"
    human = { text = "Store a token in the Keychain item demo.local-token.", twoFactor = true }
    rotateEvery = "90d"

    [[steps]]
    id = "configured"
    description = "The app has a configuration file."
    check = "test -f config/{{inputs.app}}.conf"
    fix = "mkdir -p config && touch config/{{inputs.app}}.conf"

    [[steps]]
    id = "dns"
    description = "The domain points at the app."
    check = "test -f .dns-done"
    fix = { human = { text = "Point the domain at {{inputs.app}} in {{inputs.region}}.", twoFactor = true } }

    [[shared]]
    kind = "make"
    path = "make/demo.mk"
    version = "v1"
    description = "The deploy target."

    [[docs]]
    title = "Builds"
    anchor = "builds.md#ci"

    [[certificates]]
    id = "signing"
    description = "The signing certificates."
    list = "test ! -e certs.fail || { echo 'Could not read the certificates of {{inputs.app}}.' >&2; exit 2; }; cat certs.tsv 2>/dev/null || true"
    renew = { text = "Renew the signing certificates of {{inputs.app}}.", twoFactor = true }
    """#

let otherManifest = """
    name = "other"
    description = "Another component."
    inputs = []
    secrets = []
    steps = []
    shared = []

    [detect]
    all = [{ glob = "OTHER" }]

    [[docs]]
    title = "Builds"
    anchor = "builds.md#ci"
    """

/// A templatr checkout with the `demo` and `other` components.
func makeTemplates() throws -> Directory {
    let templates = try Directory()
    try templates.write("components/demo/component.toml", demoManifest)
    try templates.write("components/demo/CLAUDE.md", "# demo\n\nConventions.\n")
    try templates.write("components/demo/scaffold/README.md", """
        # {{inputs.app}}

        <!-- superlinear:begin how-this-is-built -->
        <!-- superlinear:end -->

        """)
    try templates.writeExecutable("components/demo/scaffold/bin/deploy", "#!/bin/sh\nfly deploy --app {{inputs.app}}\n")
    try templates.write("components/demo/scaffold/.github/workflows/ci.yml", """
        jobs:
          deploy:
            uses: armcknight/templatr/.github/workflows/demo.yml@{{templates.tag}}
            if: ${{ github.ref == 'refs/heads/main' }}

        """)
    try templates.write("components/other/component.toml", otherManifest)
    try templates.write("components/other/CLAUDE.md", "# other\n")
    try templates.write("make/demo.mk", "deploy:\n")
    return templates
}

/// A project that uses `demo`, with a README of its own.
func makeProject() throws -> Directory {
    let project = try Directory()
    try project.write("fly.toml", "app = \"demo-api\"\nprimary_region = \"sjc\"\n")
    try project.write("README.md", projectReadme)
    return project
}

let projectReadme = """
    # Demo

    Intro text.

    <!-- superlinear:begin how-this-is-built -->
    Old text.
    <!-- superlinear:end -->

    Footer.

    """

/// Stand-ins for the Keychain, 1Password, GitHub, xcodebuild and the web.
final class Stubs: Keychain, PasswordManager, SecretStore, BuildSettingsProvider, LinkChecker, @unchecked Sendable {
    private let lock = NSLock()
    private var _keychain: [String: (value: String, modified: Date)] = [:]
    private var _github: [String: (value: String, updated: Date)] = [:]
    var onePassword: [String: String] = [:]
    var settings: [String: String]?
    private var _settingsRequests: [[String?]] = []
    var now = Date(timeIntervalSince1970: 1_800_000_000)

    func locked<T>(_ body: () -> T) -> T {
        lock.lock()
        defer { lock.unlock() }
        return body()
    }

    var github: [String: String] { locked { _github.mapValues(\.value) } }
    var keychain: [String: String] { locked { _keychain.mapValues(\.value) } }
    var settingsRequests: [[String?]] { locked { _settingsRequests } }

    func setKeychain(_ item: String, _ value: String, modified: Date) {
        locked { _keychain[item] = (value, modified) }
    }

    func setGitHub(_ name: String, _ value: String, updated: Date) {
        locked { _github[name] = (value, updated) }
    }

    func read(_ item: String) throws -> String? { locked { _keychain[item]?.value } }

    func lookup(_ item: String) throws -> KeychainItem? {
        locked { _keychain[item].map { KeychainItem(modified: $0.modified) } }
    }

    func store(_ item: String, value: String) throws {
        locked { _keychain[item] = (value, now) }
    }

    func read(reference: String) throws -> String? { onePassword[reference] }

    func list(repository: URL) throws -> [String: Date] { locked { _github.mapValues(\.updated) } }

    func set(_ name: String, value: String, repository: URL) throws {
        locked { _github[name] = (value, now) }
    }

    func buildSettings(repository: URL, project: String?, workspace: String?, scheme: String?) -> [String: String]? {
        locked { _settingsRequests.append([project, workspace, scheme]) }
        return settings
    }

    func resolves(_ url: URL) async -> Bool { true }

    func services() -> Services {
        Services(
            runner: ProcessRunner(), buildSettings: self, keychain: self, passwordManager: self, secrets: self, links: self,
            now: { [now] in now }
        )
    }
}

let setEverySecret: @Sendable (Secret) -> Bool = { _ in true }

/// The component `name` of this repository, resolved in `repository` as
/// bootstrap resolves it, or `nil` when its `detect` rules do not match.
func resolve(_ name: String, in repository: URL) throws -> ResolvedComponent? {
    let bootstrapper = Bootstrapper(templates: Templates(root: repositoryRoot, tag: "v1", tags: []), services: Stubs().services())
    return try bootstrapper.resolve(repository: repository, answers: [:]).components.first { $0.component.name == name }
}

extension ResolvedComponent {
    /// Each input's value: inferred, else its default, else `nil`, which
    /// bootstrap asks for.
    var inputs: [String: String?] {
        values.mapValues { $0 }.merging(missing.map { ($0.name, nil) }) { value, _ in value }
    }
}
