import Foundation
import Testing
@testable import Templatr

/// Runs commands with a directory of stand-in programs first on `PATH`.
struct StubPathRunner: CommandRunner {
    let bin: URL

    func run(_ arguments: [String], input: Data?, in directory: URL?) throws -> CommandResult {
        let path = bin.path + ":" + (ProcessInfo.processInfo.environment["PATH"] ?? "/usr/bin:/bin")
        return try ProcessRunner().run(["PATH=\(path)"] + arguments, input: input, in: directory)
    }
}

/// The github-repo component's steps, with a stand-in `gh` whose answer to the
/// rules API is `rules`.
@Suite struct GitHubRepoStepTests {
    let project: Directory
    let bin: Directory
    let stubs = Stubs()

    init() throws {
        project = try Directory()
        try project.write(".github/workflows/ci.yml", "name: ci\n")
        bin = try Directory()
    }

    /// Writes a `gh` that logs each call to gh.log, and answers the rules API
    /// with `rules`, a shell fragment.
    func stubGitHub(rules: String) throws {
        try bin.writeExecutable("gh", """
            #!/bin/sh
            echo "$*" >> "\(bin.root.path)/gh.log"
            case "$*" in
              "auth status") exit 0 ;;
              "repo view --json viewerPermission"*) echo ADMIN ;;
              "repo view --json defaultBranchRef"*) echo main ;;
              "api repos/{owner}/{repo}/rules/branches/main"*) \(rules) ;;
              "api repos/{owner}/{repo} "*) ;;
              *) echo "unexpected: $*" >&2; exit 1 ;;
            esac
            """)
    }

    var bootstrapper: Bootstrapper {
        var services = stubs.services()
        services.runner = StubPathRunner(bin: bin.root)
        return Bootstrapper(templates: Templates(root: repositoryRoot, tag: "v1", tags: []), services: services)
    }

    var calls: [String] {
        (bin.read("gh.log") ?? "").split(separator: "\n").map(String.init)
    }

    let freePlan = #"echo 'gh: Upgrade to GitHub Pro or make this repository public to enable this feature. (HTTP 403)' >&2; exit 1"#

    @Test func privateRepositoryOnTheFreePlanIsAHumanStep() async throws {
        try stubGitHub(rules: freePlan)
        let report = try await bootstrapper.check(repository: project.root)
        #expect(report.failedSteps.map(\.id) == [])
        #expect(report.humanSteps.map(\.id) == ["rulesets-available"])
        #expect(report.humanSteps.first?.text.contains("accept the risk") == true)
    }

    @Test func bootstrapDoesNotTryToMakeARulesetOnTheFreePlan() async throws {
        try stubGitHub(rules: freePlan)
        let result = try await bootstrapper.bootstrap(
            repository: project.root, options: BootstrapOptions(answers: [:], links: [], setSecret: setEverySecret)
        )
        #expect(result.report.failedSteps.map(\.id) == [])
        #expect(result.report.humanSteps.map(\.id) == ["rulesets-available"])
        #expect(!calls.contains { $0.contains("rulesets") })
    }

    @Test func otherErrorsFromTheRulesAPIFail() async throws {
        try stubGitHub(rules: #"echo 'gh: Not Found (HTTP 404)' >&2; exit 1"#)
        let report = try await bootstrapper.check(repository: project.root)
        #expect(report.humanSteps.map(\.id) == [])
        let failed = try #require(report.failedSteps.first { $0.id == "default-branch-protection" })
        #expect(failed.output.contains("Not Found (HTTP 404)"))
        #expect(failed.output.contains("Could not read the rules for main."))
    }
}
