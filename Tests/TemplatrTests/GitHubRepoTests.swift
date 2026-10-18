import Foundation
import Testing
import ComponentManifest
@testable import Templatr

@Suite("github-repo")
struct GitHubRepoTests {
    let repository: Directory
    let githubRepo: Manifest

    init() throws {
        repository = try Directory()
        githubRepo = try Manifest(contentsOf: repositoryRoot.appending(path: "components/github-repo/component.toml"))
    }

    @Test func repositoryWithWorkflows() throws {
        try repository.write(".github/workflows/ci.yml", "name: ci\n")
        #expect(try #require(try resolve("github-repo", in: repository.root)).inputs.isEmpty)
    }

    @Test func repositoryWithoutGitHubDirectory() throws {
        try repository.write("Package.swift", mtgPackage)
        #expect(try resolve("github-repo", in: repository.root) == nil)
    }

    /// Each step's check and fix that runs a script names one in the
    /// component's bin directory, and each of those is executable.
    @Test func stepScriptsAreExecutable() throws {
        let prefix = "{{templates}}/"
        let commands = githubRepo.steps.flatMap { step -> [String] in
            var commands = [step.check]
            if case .command(let fix) = step.fix { commands.append(fix) }
            return commands
        }
        let scripts = commands.filter { $0.hasPrefix(prefix) }.map { String($0.dropFirst(prefix.count).split(separator: " ")[0]) }
        #expect(scripts.count == 4)
        for script in scripts {
            #expect(FileManager.default.isExecutableFile(atPath: repositoryRoot.appending(path: script).path), "\(script)")
        }
    }
}
