import Foundation
import Testing
@testable import ComponentManifest

@Suite("linear-workspace")
struct LinearWorkspaceTests {
    let repository: Repository
    let linearWorkspace: Manifest

    init() throws {
        repository = try Repository()
        linearWorkspace = try Manifest(contentsOf: repositoryRoot.appending(path: "components/linear-workspace/component.toml"))
    }

    var detection: Detection { Detection(root: repository.root) }

    @Test(arguments: [
        (".envrc", "export LINCTL_API_KEY=$(op read op://Private/Linear/key)\n"),
        (".envrc", "export LINEAR_API_KEY=lin_api_example\n"),
        (".envrc.example", "export LINCTL_API_KEY=\n"),
    ])
    func repositoryWithAKeyInItsEnvrc(path: String, text: String) throws {
        try repository.write(path, text)
        #expect(detection.detects(linearWorkspace))
        #expect(detection.inputs(of: linearWorkspace) == ["linear_teams": "", "linear_initiatives": "false"])
    }

    @Test func repositoryWithoutAKeyInItsEnvrc() throws {
        #expect(!detection.detects(linearWorkspace))
        try repository.write(".envrc", "export GITHUB_TOKEN=x\nexport MY_LINEAR_API_KEY_NAME=y\n")
        #expect(!detection.detects(linearWorkspace))
    }

    /// Every step that runs the script names it in the component's bin
    /// directory, which is executable.
    @Test func stepScriptsAreExecutable() throws {
        let script = "{{templates}}/components/linear-workspace/bin/linear-workspace"
        let commands = linearWorkspace.steps.flatMap { step -> [String] in
            var commands = [step.check]
            if case .command(let fix) = step.fix { commands.append(fix) }
            return commands
        }
        let usingScript = commands.filter { $0.contains("{{templates}}") }
        #expect(usingScript.count == 13)
        #expect(usingScript.allSatisfy { $0.contains(script + " check ") || $0.contains(script + " fix ") })
        let path = repositoryRoot.appending(path: "components/linear-workspace/bin/linear-workspace").path
        #expect(FileManager.default.isExecutableFile(atPath: path))
    }
}
