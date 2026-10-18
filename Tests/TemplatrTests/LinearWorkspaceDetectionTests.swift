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

    var linearWorkspace: ResolvedComponent? {
        get throws { try resolve("linear-workspace", in: repository.root) }
    }

    @Test(arguments: [
        (".envrc", "export LINCTL_API_KEY=$(op read op://Private/Linear/key)\n"),
        (".envrc", "export LINEAR_API_KEY=lin_api_example\n"),
        (".envrc.example", "export LINCTL_API_KEY=\n"),
    ])
    func repositoryWithAKeyInItsEnvrc(path: String, text: String) throws {
        try repository.write(path, text)
        #expect(try #require(try linearWorkspace).inputs == ["linear_teams": "", "linear_initiatives": "false"])
    }

    @Test func repositoryWithoutAKeyInItsEnvrc() throws {
        #expect(try linearWorkspace == nil)
        try repository.write(".envrc", "export GITHUB_TOKEN=x\nexport MY_LINEAR_API_KEY_NAME=y\n")
        #expect(try linearWorkspace == nil)
    }
}
