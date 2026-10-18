import Foundation
import Testing
@testable import ComponentManifest

@Suite("linear-workspace")
struct LinearWorkspaceTests {
    let linearWorkspace: Manifest

    init() throws {
        linearWorkspace = try Manifest(contentsOf: repositoryRoot.appending(path: "components/linear-workspace/component.toml"))
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
