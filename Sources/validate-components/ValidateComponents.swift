import ComponentManifest
import Foundation

/// Validates every component in a checkout of this repository. Prints each
/// problem to stderr and exits 1 when there are any.
@main
struct ValidateComponents {
    static let usage = """
        Usage: validate-components [--root DIR] [--anchors PATH_OR_URL|none]

          --root DIR       The repository root. The current directory by default.
          --anchors X      docs/anchors.md from the superlinear repository, as a
                           path or a URL; 'none' skips the anchor check.
                           \(Anchors.defaultSource) by default.
        """

    static func main() async {
        var root = FileManager.default.currentDirectoryPath
        var anchorsSource = Anchors.defaultSource

        var arguments = CommandLine.arguments.dropFirst()[...]
        while let argument = arguments.popFirst() {
            switch argument {
            case "--root":
                guard let value = arguments.popFirst() else { return fail("--root needs a directory") }
                root = value
            case "--anchors":
                guard let value = arguments.popFirst() else { return fail("--anchors needs a path, a URL or none") }
                anchorsSource = value
            case "-h", "--help":
                print(usage)
                return
            default:
                return fail("unknown argument '\(argument)'")
            }
        }

        var anchors: Set<String>?
        if anchorsSource != "none" {
            do {
                anchors = try await Anchors.read(from: anchorsSource)
            } catch {
                printError("could not read the anchors from \(anchorsSource): \(error)")
                exit(1)
            }
        }

        let problems = Validator(root: URL(fileURLWithPath: root), anchors: anchors).problems()
        for problem in problems {
            printError(problem)
        }
        if !problems.isEmpty {
            printError("\(problems.count) problem(s).")
            exit(1)
        }
        print("All components are valid.")
    }

    static func fail(_ message: String) {
        printError("validate-components: \(message)\n\(usage)")
        exit(2)
    }

    static func printError(_ message: String) {
        FileHandle.standardError.write(Data((message + "\n").utf8))
    }
}
