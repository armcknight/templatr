import Foundation
import Testing
@testable import Templatr

@Suite("mcknight-io-listing")
struct McknightIoListingTests {
    let repository: Directory

    init() throws {
        repository = try Directory()
        try repository.write(".github/workflows/ci.yml", """
            jobs:
              ci:
                uses: armcknight/workflows/.github/workflows/swift-package-ci.yml@4
                secrets: inherit

            """)
    }

    func resolution() throws -> Resolution {
        let bootstrapper = Bootstrapper(templates: Templates(root: repositoryRoot, tag: "v1", tags: []), services: Stubs().services())
        return try bootstrapper.resolve(repository: repository.root, answers: [:])
    }

    /// Being listed on mcknight.io is not in a project's files, so its
    /// workflows alone do not choose the component.
    @Test func isNotDetectedFromTheFiles() throws {
        #expect(try resolve("mcknight-io-listing", in: repository.root) == nil)
        try repository.write(".templatr.toml", """
            [components.github-repo]
            tag = "v1"

            """)
        let resolution = try resolution()
        #expect(!resolution.components.map(\.component.name).contains("mcknight-io-listing"))
        #expect(!resolution.newComponents.contains("mcknight-io-listing"))
    }

    @Test func isChosenInTheRecord() throws {
        try repository.write(".templatr.toml", """
            [components.github-repo]
            tag = "v1"

            [components.mcknight-io-listing]
            tag = "v1"

            """)
        let resolution = try resolution()
        #expect(resolution.components.map(\.component.name).contains("mcknight-io-listing"))
        #expect(!resolution.newComponents.contains("mcknight-io-listing"))
    }

    /// Runs the secrets-inherit step's script in the repository, and returns
    /// its exit status and standard error.
    func checkSecretsInherit() throws -> (status: Int32, error: String) {
        let process = Process()
        process.executableURL = repositoryRoot.appending(path: "components/mcknight-io-listing/bin/check-secrets-inherit")
        process.currentDirectoryURL = repository.root
        let error = Pipe()
        process.standardError = error
        try process.run()
        let data = error.fileHandleForReading.readDataToEndOfFile()
        process.waitUntilExit()
        return (process.terminationStatus, String(decoding: data, as: UTF8.self))
    }

    @Test func passesWhenEachCallInheritsSecrets() throws {
        try repository.write(".github/workflows/release.yaml", """
            name: release
            jobs:
              # Passes the one secret the notify step needs.
              release:
                uses: "armcknight/workflows/.github/workflows/github-release.yml@4"
                secrets:
                  SITE_DISPATCH_TOKEN: ${{ secrets.SITE_DISPATCH_TOKEN }}
              local:
                runs-on: ubuntu-latest
                steps:
                  - uses: actions/checkout@v4

            """)
        #expect(try checkSecretsInherit().status == 0)
    }

    @Test func failsForACallWithoutSecrets() throws {
        try repository.write(".github/workflows/deploy.yml", """
            jobs:
              deploy:
                uses: armcknight/workflows/.github/workflows/fly-deploy.yml@4
                with:
                  secrets: inherit

            """)
        let result = try checkSecretsInherit()
        #expect(result.status == 1)
        #expect(result.error == ".github/workflows/deploy.yml: job deploy calls armcknight/workflows without secrets: inherit.\n")
    }

    @Test func failsWhenNoJobCallsTheSharedWorkflows() throws {
        try repository.write(".github/workflows/ci.yml", """
            jobs:
              build:
                runs-on: ubuntu-latest

            """)
        let result = try checkSecretsInherit()
        #expect(result.status == 1)
        #expect(result.error.contains("nothing asks mcknight.io to refresh"))
    }
}
