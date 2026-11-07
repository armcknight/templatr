import Foundation
import Testing
@testable import Templatr

/// The clone that a release build keeps for itself, against a local origin
/// repository with a component and release tags.
@Suite struct ManagedTemplatesTests {
    let origin: Directory
    let home: Directory
    let runner = ProcessRunner()

    var clone: URL { home.root.appending(path: "Application Support/templatr/templates") }

    init() throws {
        origin = try Directory()
        home = try Directory()
        try origin.write("components/demo/component.toml", demoManifest)
        try origin.write("components/demo/CLAUDE.md", "# demo\n")
        try git("init", "-q", "-b", "main")
        try git("add", ".")
        try git("commit", "-q", "-m", "demo")
        try git("tag", "v1.0.0")
        try git("tag", "v1")
    }

    @discardableResult
    func git(_ arguments: String...) throws -> String {
        let result = try runner.run(
            ["git", "-c", "user.name=Test", "-c", "user.email=test@example.com"] + arguments, input: nil, in: origin.root
        )
        #expect(result.succeeded, "\(result.transcript)")
        return result.text.trimmingCharacters(in: .whitespacesAndNewlines)
    }

    func managed(tag: String? = nil) throws -> Templates {
        try Templates.managed(at: clone, origin: origin.root.path, tag: tag, runner: runner)
    }

    @Test func clonesOnFirstUseAndChecksOutTheNewestAlias() throws {
        let templates = try managed()
        #expect(templates.root == clone.standardizedFileURL)
        #expect(templates.tag == "v1")
        #expect(templates.tags == ["v1"])
        #expect(try templates.components().map(\.name) == ["demo"])
        let head = try runner.run(["git", "-C", clone.path, "describe", "--tags", "--exact-match"], input: nil, in: nil)
        #expect(head.text.contains("v1"))
    }

    @Test func fetchesNewTagsOnEachRunAndMovesToTheNewestAlias() throws {
        _ = try managed()
        try origin.write("components/demo/CLAUDE.md", "# demo, changed\n")
        try git("commit", "-q", "-am", "change")
        try git("tag", "v2.0.0")
        try git("tag", "v2")
        let templates = try managed()
        #expect(templates.tag == "v2")
        #expect(templates.tags.sorted() == ["v1", "v2"])
        #expect(try String(contentsOf: clone.appending(path: "components/demo/CLAUDE.md"), encoding: .utf8) == "# demo, changed\n")
    }

    @Test func aMovedAliasIsFollowed() throws {
        _ = try managed()
        try origin.write("components/demo/CLAUDE.md", "# demo, 1.1\n")
        try git("commit", "-q", "-am", "change")
        try git("tag", "v1.1.0")
        try git("tag", "-f", "v1")
        let templates = try managed()
        #expect(templates.tag == "v1")
        #expect(try String(contentsOf: clone.appending(path: "components/demo/CLAUDE.md"), encoding: .utf8) == "# demo, 1.1\n")
    }

    @Test func aGivenTagIsCheckedOut() throws {
        try origin.write("components/demo/CLAUDE.md", "# demo, 1.1\n")
        try git("commit", "-q", "-am", "change")
        try git("tag", "v1.1.0")
        try git("tag", "-f", "v1")
        let templates = try managed(tag: "v1.0.0")
        #expect(templates.tag == "v1.0.0")
        #expect(try String(contentsOf: clone.appending(path: "components/demo/CLAUDE.md"), encoding: .utf8) == "# demo\n")
    }

    @Test func anOriginWithoutAnAliasIsAnError() throws {
        try git("tag", "-d", "v1")
        #expect(throws: TemplatrError.self) { try managed() }
    }
}
