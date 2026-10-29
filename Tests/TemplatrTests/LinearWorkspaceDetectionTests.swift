import Foundation
import Testing
@testable import Templatr

/// Detection and inference with this repository's linear-workspace manifest,
/// as bootstrap runs them.
@Suite("linear-workspace detection")
struct LinearWorkspaceDetectionTests {
    let repository: Directory

    init() throws {
        repository = try Directory()
    }

    /// Resolves with no Linear API key and an API that does not answer, so
    /// that the linear_workspace command finds nothing and reaches no server.
    var linearWorkspace: ResolvedComponent? {
        get throws {
            let runner = ProcessRunner(environment: ["LINEAR_API_KEY": "", "LINCTL_API_KEY": "", "LINEAR_API_URL": "http://127.0.0.1:9/graphql"])
            return try resolve("linear-workspace", in: repository.root, runner: runner)
        }
    }

    @Test(arguments: [
        (".envrc", "export LINCTL_API_KEY=$(op read op://Private/Linear/key)\n"),
        (".envrc", "export LINEAR_API_KEY=lin_api_example\n"),
        (".envrc.example", "export LINCTL_API_KEY=\n"),
    ])
    func repositoryWithAKeyInItsEnvrc(path: String, text: String) throws {
        try repository.write(path, text)
        #expect(try #require(try linearWorkspace).inputs == ["linear_teams": "", "linear_initiatives": "false", "linear_workspace": nil])
    }

    #if os(macOS)
    @Test func theWorkspaceComesFromTheAPIWhenTheKeyIsInTheEnvironment() throws {
        let linear = try FakeLinear()
        linear.urlKey = "babysittr"
        try repository.write(".envrc", "export LINCTL_API_KEY=\n")
        let runner = ProcessRunner(environment: ["LINEAR_API_URL": linear.url, "LINEAR_API_KEY": FakeLinear.key, "LINCTL_API_KEY": ""])
        let resolved = try #require(try resolve("linear-workspace", in: repository.root, runner: runner))
        #expect(resolved.inferred["linear_workspace"] == "babysittr")
        #expect(resolved.values["linear_workspace"] == "babysittr")
    }
    #endif

    @Test func repositoryWithoutAKeyInItsEnvrc() throws {
        #expect(try linearWorkspace == nil)
        try repository.write(".envrc", "export GITHUB_TOKEN=x\nexport MY_LINEAR_API_KEY_NAME=y\n")
        #expect(try linearWorkspace == nil)
    }
}
